## Go io package implementation in Nim
import std/[streams, os]
import ../runtime

type
  Reader* = concept x
    x.Read(var openArray[byte]) is tuple[n: int, err: GoError]
  
  Writer* = concept x
    x.Write(openArray[byte]) is tuple[n: int, err: GoError]
  
  Closer* = concept x
    x.Close() is GoError
  
  Seeker* = concept x
    x.Seek(int64, int) is tuple[n: int64, err: GoError]
  
  ReadWriter* = concept x
    x is Reader
    x is Writer
  
  ReadCloser* = concept x
    x is Reader
    x is Closer
  
  WriteCloser* = concept x
    x is Writer
    x is Closer
  
  ReadWriteCloser* = concept x
    x is Reader
    x is Writer
    x is Closer
  
  ReadSeeker* = concept x
    x is Reader
    x is Seeker
  
  WriteSeeker* = concept x
    x is Writer
    x is Seeker
  
  ReadWriteSeeker* = concept x
    x is Reader
    x is Writer
    x is Seeker
  
  ByteReader* = ref object
    data: seq[byte]
    pos: int
  
  ByteWriter* = ref object
    data: seq[byte]
  
  LimitedReader* = ref object
    reader: Reader
    limit: int64
  
  SectionReader* = ref object
    reader: ReaderAt
    offset: int64
    limit: int64
    pos: int64
  
  PipeReader* = ref object
    pipe: Pipe
  
  PipeWriter* = ref object
    pipe: Pipe
  
  Pipe* = ref object
    buffer: seq[byte]
    closed: bool
  
  MultiReader* = ref object
    readers: seq[Reader]
    current: int
  
  MultiWriter* = ref object
    writers: seq[Writer]
  
  TeeReader* = ref object
    reader: Reader
    writer: Writer
  
  ReaderAt* = concept x
    x.ReadAt(var openArray[byte], int64) is tuple[n: int, err: GoError]
  
  WriterAt* = concept x
    x.WriteAt(openArray[byte], int64) is tuple[n: int, err: GoError]

# Error definitions
var
  EOF* = newException(GoError, "EOF")
  ErrUnexpectedEOF* = newException(GoError, "unexpected EOF")
  ErrShortWrite* = newException(GoError, "short write")
  ErrShortBuffer* = newException(GoError, "short buffer")
  ErrNoProgress* = newException(GoError, "multiple Read calls return no data or error")
  ErrClosedPipe* = newException(GoError, "io: read/write on closed pipe")

# Seek whence values
const
  SeekStart* = 0
  SeekCurrent* = 1
  SeekEnd* = 2

# ByteReader implementation
proc newByteReader*(data: seq[byte]): ByteReader =
  new(result)
  result.data = data
  result.pos = 0

proc Read*(br: ByteReader, p: var openArray[byte]): tuple[n: int, err: GoError] =
  if br.pos >= br.data.len:
    result.err = EOF
    return
  
  let available = br.data.len - br.pos
  let toRead = min(p.len, available)
  
  for i in 0..<toRead:
    p[i] = br.data[br.pos + i]
  
  br.pos += toRead
  result.n = toRead
  result.err = nil

proc ReadByte*(br: ByteReader): tuple[b: byte, err: GoError] =
  if br.pos >= br.data.len:
    result.err = EOF
    return
  
  result.b = br.data[br.pos]
  br.pos.inc
  result.err = nil

# ByteWriter implementation
proc newByteWriter*(): ByteWriter =
  new(result)
  result.data = @[]

proc Write*(bw: ByteWriter, p: openArray[byte]): tuple[n: int, err: GoError] =
  for b in p:
    bw.data.add(b)
  result.n = p.len
  result.err = nil

proc WriteByte*(bw: ByteWriter, b: byte): GoError =
  bw.data.add(b)
  nil

proc Bytes*(bw: ByteWriter): seq[byte] =
  bw.data

# Copy functions
proc Copy*(dst: Writer, src: Reader): tuple[written: int64, err: GoError] =
  var buf: array[32 * 1024, byte]
  var totalWritten = 0'i64
  
  while true:
    let (nr, errRead) = src.Read(buf)
    if nr > 0:
      let (nw, errWrite) = dst.Write(buf[0..<nr])
      totalWritten += nw
      
      if not errWrite.isNil:
        result.err = errWrite
        result.written = totalWritten
        return
      
      if nw != nr:
        result.err = ErrShortWrite
        result.written = totalWritten
        return
    
    if not errRead.isNil:
      if errRead == EOF:
        result.written = totalWritten
        result.err = nil
      else:
        result.err = errRead
        result.written = totalWritten
      return

proc CopyN*(dst: Writer, src: Reader, n: int64): tuple[written: int64, err: GoError] =
  let lr = newLimitedReader(src, n)
  Copy(dst, lr)

proc CopyBuffer*(dst: Writer, src: Reader, buf: var openArray[byte]): tuple[written: int64, err: GoError] =
  var totalWritten = 0'i64
  
  while true:
    let (nr, errRead) = src.Read(buf)
    if nr > 0:
      let (nw, errWrite) = dst.Write(buf[0..<nr])
      totalWritten += nw
      
      if not errWrite.isNil:
        result.err = errWrite
        result.written = totalWritten
        return
      
      if nw != nr:
        result.err = ErrShortWrite
        result.written = totalWritten
        return
    
    if not errRead.isNil:
      if errRead == EOF:
        result.written = totalWritten
        result.err = nil
      else:
        result.err = errRead
        result.written = totalWritten
      return

# LimitedReader implementation
proc newLimitedReader*(r: Reader, n: int64): LimitedReader =
  new(result)
  result.reader = r
  result.limit = n

proc Read*(lr: LimitedReader, p: var openArray[byte]): tuple[n: int, err: GoError] =
  if lr.limit <= 0:
    result.err = EOF
    return
  
  let toRead = min(p.len, int(lr.limit))
  var buf = newSeq[byte](toRead)
  let (n, err) = lr.reader.Read(buf)
  
  for i in 0..<n:
    p[i] = buf[i]
  
  lr.limit -= n
  result.n = n
  result.err = err

# Pipe implementation
proc Pipe*(): tuple[reader: PipeReader, writer: PipeWriter] =
  let p = Pipe(buffer: @[], closed: false)
  
  new(result.reader)
  result.reader.pipe = p
  
  new(result.writer)
  result.writer.pipe = p

proc Read*(pr: PipeReader, p: var openArray[byte]): tuple[n: int, err: GoError] =
  if pr.pipe.closed and pr.pipe.buffer.len == 0:
    result.err = EOF
    return
  
  while pr.pipe.buffer.len == 0 and not pr.pipe.closed:
    sleep(1)
  
  let toRead = min(p.len, pr.pipe.buffer.len)
  for i in 0..<toRead:
    p[i] = pr.pipe.buffer[i]
  
  pr.pipe.buffer.delete(0, toRead - 1)
  result.n = toRead
  result.err = nil

proc Close*(pr: PipeReader): GoError =
  pr.pipe.closed = true
  nil

proc Write*(pw: PipeWriter, p: openArray[byte]): tuple[n: int, err: GoError] =
  if pw.pipe.closed:
    result.err = ErrClosedPipe
    return
  
  for b in p:
    pw.pipe.buffer.add(b)
  
  result.n = p.len
  result.err = nil

proc Close*(pw: PipeWriter): GoError =
  pw.pipe.closed = true
  nil

# MultiReader implementation
proc MultiReader*(readers: varargs[Reader]): MultiReader =
  new(result)
  result.readers = @readers
  result.current = 0

proc Read*(mr: MultiReader, p: var openArray[byte]): tuple[n: int, err: GoError] =
  while mr.current < mr.readers.len:
    let (n, err) = mr.readers[mr.current].Read(p)
    
    if n > 0 or (not err.isNil and err != EOF):
      result.n = n
      result.err = err
      return
    
    mr.current.inc
  
  result.err = EOF

# MultiWriter implementation
proc MultiWriter*(writers: varargs[Writer]): MultiWriter =
  new(result)
  result.writers = @writers

proc Write*(mw: MultiWriter, p: openArray[byte]): tuple[n: int, err: GoError] =
  for w in mw.writers:
    let (n, err) = w.Write(p)
    if not err.isNil:
      result.err = err
      return
    if n != p.len:
      result.err = ErrShortWrite
      return
  
  result.n = p.len
  result.err = nil

# TeeReader implementation
proc TeeReader*(r: Reader, w: Writer): TeeReader =
  new(result)
  result.reader = r
  result.writer = w

proc Read*(tr: TeeReader, p: var openArray[byte]): tuple[n: int, err: GoError] =
  let (n, err) = tr.reader.Read(p)
  if n > 0:
    discard tr.writer.Write(p[0..<n])
  result.n = n
  result.err = err

# Utility functions
proc ReadAll*(r: Reader): tuple[data: seq[byte], err: GoError] =
  var buffer: seq[byte] = @[]
  var chunk: array[512, byte]
  
  while true:
    let (n, err) = r.Read(chunk)
    if n > 0:
      for i in 0..<n:
        buffer.add(chunk[i])
    
    if not err.isNil:
      if err == EOF:
        result.data = buffer
        result.err = nil
      else:
        result.err = err
      return

proc ReadAtLeast*(r: Reader, buf: var openArray[byte], min: int): tuple[n: int, err: GoError] =
  var totalRead = 0
  
  while totalRead < min:
    var tempBuf = newSeq[byte](buf.len - totalRead)
    let (n, err) = r.Read(tempBuf)
    
    for i in 0..<n:
      buf[totalRead + i] = tempBuf[i]
    
    totalRead += n
    
    if not err.isNil:
      if err == EOF and totalRead >= min:
        result.n = totalRead
        result.err = nil
      else:
        result.err = err
      return
  
  result.n = totalRead
  result.err = nil

proc ReadFull*(r: Reader, buf: var openArray[byte]): tuple[n: int, err: GoError] =
  ReadAtLeast(r, buf, buf.len)

proc WriteString*(w: Writer, s: string): tuple[n: int, err: GoError] =
  let bytes = cast[seq[byte]](s)
  w.Write(bytes)
