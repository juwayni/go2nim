## Go bytes package implementation in Nim
import std/[strutils]
import ../runtime

type
  Buffer* = ref object
    buf: seq[byte]
    off: int

# Buffer operations
proc NewBuffer*(buf: seq[byte]): Buffer =
  new(result)
  result.buf = buf
  result.off = 0

proc NewBufferString*(s: string): Buffer =
  new(result)
  result.buf = cast[seq[byte]](s)
  result.off = 0

proc Len*(b: Buffer): int =
  b.buf.len - b.off

proc Cap*(b: Buffer): int =
  b.buf.len

proc Bytes*(b: Buffer): seq[byte] =
  b.buf[b.off..^1]

proc String*(b: Buffer): GoString =
  newGoString(cast[string](b.buf[b.off..^1]))

proc Reset*(b: Buffer) =
  b.buf.setLen(0)
  b.off = 0

proc Truncate*(b: Buffer, n: int) =
  if n < 0 or n > b.Len():
    panic("bytes.Buffer: truncation out of range")
  b.buf.setLen(b.off + n)

proc Grow*(b: Buffer, n: int) =
  if n < 0:
    panic("bytes.Buffer.Grow: negative count")
  let newLen = b.buf.len + n
  if newLen > b.buf.len:
    b.buf.setLen(newLen)

proc Write*(b: Buffer, p: openArray[byte]): tuple[n: int, err: GoError] =
  for byte in p:
    b.buf.add(byte)
  result.n = p.len
  result.err = nil

proc WriteString*(b: Buffer, s: string): tuple[n: int, err: GoError] =
  for c in s:
    b.buf.add(byte(c))
  result.n = s.len
  result.err = nil

proc WriteByte*(b: Buffer, c: byte): GoError =
  b.buf.add(c)
  nil

proc WriteRune*(b: Buffer, r: Rune): tuple[n: int, err: GoError] =
  let s = $char(r)
  for c in s:
    b.buf.add(byte(c))
  result.n = s.len
  result.err = nil

proc Read*(b: Buffer, p: var openArray[byte]): tuple[n: int, err: GoError] =
  if b.off >= b.buf.len:
    result.err = newException(GoError, "EOF")
    return
  
  let available = b.buf.len - b.off
  let toRead = min(p.len, available)
  
  for i in 0..<toRead:
    p[i] = b.buf[b.off + i]
  
  b.off += toRead
  result.n = toRead
  result.err = nil

proc ReadByte*(b: Buffer): tuple[c: byte, err: GoError] =
  if b.off >= b.buf.len:
    result.err = newException(GoError, "EOF")
    return
  
  result.c = b.buf[b.off]
  b.off.inc
  result.err = nil

proc ReadBytes*(b: Buffer, delim: byte): tuple[line: seq[byte], err: GoError] =
  var line: seq[byte] = @[]
  
  while b.off < b.buf.len:
    let c = b.buf[b.off]
    b.off.inc
    line.add(c)
    if c == delim:
      break
  
  if line.len == 0:
    result.err = newException(GoError, "EOF")
  else:
    result.line = line
    result.err = nil

proc ReadString*(b: Buffer, delim: byte): tuple[line: string, err: GoError] =
  let (bytes, err) = b.ReadBytes(delim)
  if err != nil:
    result.err = err
  else:
    result.line = cast[string](bytes)
    result.err = nil

# Comparison functions
proc Compare*(a, b: openArray[byte]): int =
  let minLen = min(a.len, b.len)
  for i in 0..<minLen:
    if a[i] < b[i]:
      return -1
    elif a[i] > b[i]:
      return 1
  
  if a.len < b.len:
    return -1
  elif a.len > b.len:
    return 1
  else:
    return 0

proc Equal*(a, b: openArray[byte]): bool =
  if a.len != b.len:
    return false
  
  for i in 0..<a.len:
    if a[i] != b[i]:
      return false
  
  true

# Search functions
proc Contains*(b: openArray[byte], subslice: openArray[byte]): bool =
  Index(b, subslice) != -1

proc Index*(s: openArray[byte], sep: openArray[byte]): int =
  if sep.len == 0:
    return 0
  
  for i in 0..s.len - sep.len:
    var match = true
    for j in 0..<sep.len:
      if s[i + j] != sep[j]:
        match = false
        break
    if match:
      return i
  
  return -1

proc LastIndex*(s: openArray[byte], sep: openArray[byte]): int =
  if sep.len == 0:
    return s.len
  
  for i in countdown(s.len - sep.len, 0):
    var match = true
    for j in 0..<sep.len:
      if s[i + j] != sep[j]:
        match = false
        break
    if match:
      return i
  
  return -1

proc Count*(s: openArray[byte], sep: openArray[byte]): int =
  if sep.len == 0:
    return s.len + 1
  
  var count = 0
  var i = 0
  
  while i <= s.len - sep.len:
    var match = true
    for j in 0..<sep.len:
      if s[i + j] != sep[j]:
        match = false
        break
    
    if match:
      count.inc
      i += sep.len
    else:
      i.inc
  
  count

# Transformation functions
proc ToUpper*(s: openArray[byte]): seq[byte] =
  result = newSeq[byte](s.len)
  for i, b in s:
    if b >= byte('a') and b <= byte('z'):
      result[i] = b - 32
    else:
      result[i] = b

proc ToLower*(s: openArray[byte]): seq[byte] =
  result = newSeq[byte](s.len)
  for i, b in s:
    if b >= byte('A') and b <= byte('Z'):
      result[i] = b + 32
    else:
      result[i] = b

proc Trim*(s: openArray[byte], cutset: string): seq[byte] =
  var start = 0
  var stop = s.len
  
  while start < stop and chr(s[start]) in cutset:
    start.inc
  
  while stop > start and chr(s[stop - 1]) in cutset:
    stop.dec
  
  result = newSeq[byte](stop - start)
  for i in 0..<result.len:
    result[i] = s[start + i]

proc TrimSpace*(s: openArray[byte]): seq[byte] =
  Trim(s, " \t\n\r")

proc Split*(s: openArray[byte], sep: openArray[byte]): seq[seq[byte]] =
  result = @[]
  
  if sep.len == 0:
    for b in s:
      result.add(@[b])
    return
  
  var start = 0
  var i = 0
  
  while i <= s.len - sep.len:
    var match = true
    for j in 0..<sep.len:
      if s[i + j] != sep[j]:
        match = false
        break
    
    if match:
      var part = newSeq[byte](i - start)
      for j in 0..<part.len:
        part[j] = s[start + j]
      result.add(part)
      i += sep.len
      start = i
    else:
      i.inc
  
  var last = newSeq[byte](s.len - start)
  for i in 0..<last.len:
    last[i] = s[start + i]
  result.add(last)

proc Join*(s: seq[seq[byte]], sep: openArray[byte]): seq[byte] =
  if s.len == 0:
    return @[]
  
  result = @[]
  for i, part in s:
    if i > 0:
      for b in sep:
        result.add(b)
    for b in part:
      result.add(b)

proc Repeat*(b: openArray[byte], count: int): seq[byte] =
  result = newSeq[byte](b.len * count)
  var idx = 0
  for i in 0..<count:
    for byte in b:
      result[idx] = byte
      idx.inc

proc Replace*(s: openArray[byte], old: openArray[byte], new: openArray[byte], n: int): seq[byte] =
  result = @[]
  var count = 0
  var i = 0
  
  while i < s.len:
    if n >= 0 and count >= n:
      for j in i..<s.len:
        result.add(s[j])
      break
    
    if i <= s.len - old.len:
      var match = true
      for j in 0..<old.len:
        if s[i + j] != old[j]:
          match = false
          break
      
      if match:
        for b in new:
          result.add(b)
        i += old.len
        count.inc
        continue
    
    result.add(s[i])
    i.inc
