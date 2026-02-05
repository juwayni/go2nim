# Enhanced Go Runtime for Nim
import std/[locks, atomics, deques, hashes, tables, times, os, macros]

# ===========================
# Core Types
# ===========================

type
  GoInt* = int
  GoUint* = uint
  Rune* = int32
  
  GoString* = ref object
    data: string
  
  GoSlice*[T] = ref object
    data: seq[T]
    length: int
    capacity: int
  
  GoMap*[K, V] = ref object
    data: Table[K, V]
    lock: Lock
  
  GoChan*[T] = ref object
    queue: Deque[T]
    lock: Lock
    cond: Cond
    capacity: int
    closed: bool
  
  GoRecvChan*[T] = GoChan[T]
  GoSendChan*[T] = GoChan[T]
  
  GoInterface* = ref object of RootObj
  
  GoError* = ref object of CatchableError
  
  GoFunc* = proc() {.gcsafe.}
  
  GoComplex64* = object
    real*: float32
    imag*: float32
  
  GoComplex128* = object
    real*: float64
    imag*: float64
  
  Goroutine = ref object
    id: int
    fn: GoFunc
    thread: Thread[GoFunc]

# ===========================
# GoString Implementation
# ===========================

proc newGoString*(s: string): GoString =
  new(result)
  result.data = s

proc newGoString*(bytes: seq[byte]): GoString =
  new(result)
  result.data = newString(bytes.len)
  for i, b in bytes:
    result.data[i] = char(b)

proc `$`*(s: GoString): string =
  if s.isNil: "" else: s.data

proc len*(s: GoString): int =
  if s.isNil: 0 else: s.data.len

proc `[]`*(s: GoString, i: int): byte =
  byte(s.data[i])

proc `[]`*(s: GoString, slice: HSlice[int, int]): GoString =
  newGoString(s.data[slice])

proc `&`*(s1, s2: GoString): GoString =
  newGoString(s1.data & s2.data)

proc `==`*(s1, s2: GoString): bool =
  if s1.isNil and s2.isNil: return true
  if s1.isNil or s2.isNil: return false
  s1.data == s2.data

# ===========================
# GoSlice Implementation
# ===========================

proc newGoSlice*[T](cap: int = 0): GoSlice[T] =
  new(result)
  result.data = newSeq[T](cap)
  result.length = 0
  result.capacity = cap

proc newGoSliceFromSeq*[T](data: seq[T]): GoSlice[T] =
  new(result)
  result.data = data
  result.length = data.len
  result.capacity = data.len

proc append*[T](s: GoSlice[T], items: varargs[T]): GoSlice[T] =
  result = s
  for item in items:
    if result.length >= result.capacity:
      # Grow capacity
      let newCap = if result.capacity == 0: 1 else: result.capacity * 2
      result.data.setLen(newCap)
      result.capacity = newCap
    result.data[result.length] = item
    result.length.inc

proc `[]`*[T](s: GoSlice[T], i: int): T =
  if i < 0 or i >= s.length:
    raise newException(IndexDefect, "slice index out of range")
  s.data[i]

proc `[]=`*[T](s: GoSlice[T], i: int, val: T) =
  if i < 0 or i >= s.length:
    raise newException(IndexDefect, "slice index out of range")
  s.data[i] = val

proc `[]`*[T](s: GoSlice[T], slice: HSlice[int, int]): GoSlice[T] =
  let start = if slice.a < 0: 0 else: slice.a
  let stop = if slice.b >= s.length: s.length else: slice.b + 1
  
  result = newGoSlice[T]()
  result.length = stop - start
  result.capacity = result.length
  result.data = s.data[start..<stop]

proc len*[T](s: GoSlice[T]): int =
  s.length

proc cap*[T](s: GoSlice[T]): int =
  s.capacity

proc high*[T](s: GoSlice[T]): int =
  s.length - 1

iterator items*[T](s: GoSlice[T]): T =
  for i in 0..<s.length:
    yield s.data[i]

iterator pairs*[T](s: GoSlice[T]): (int, T) =
  for i in 0..<s.length:
    yield (i, s.data[i])

# ===========================
# GoMap Implementation
# ===========================

proc newGoMap*[K, V](): GoMap[K, V] =
  new(result)
  result.data = initTable[K, V]()
  initLock(result.lock)

proc `[]`*[K, V](m: GoMap[K, V], key: K): V =
  withLock(m.lock):
    if not m.data.hasKey(key):
      raise newException(KeyError, "key not found")
    m.data[key]

proc `[]=`*[K, V](m: GoMap[K, V], key: K, val: V) =
  withLock(m.lock):
    m.data[key] = val

proc getOrDefault*[K, V](m: GoMap[K, V], key: K, default: V): V =
  withLock(m.lock):
    if m.data.hasKey(key):
      m.data[key]
    else:
      default

proc contains*[K, V](m: GoMap[K, V], key: K): bool =
  withLock(m.lock):
    m.data.hasKey(key)

proc delete*[K, V](m: GoMap[K, V], key: K) =
  withLock(m.lock):
    if m.data.hasKey(key):
      m.data.del(key)

proc len*[K, V](m: GoMap[K, V]): int =
  withLock(m.lock):
    m.data.len

iterator pairs*[K, V](m: GoMap[K, V]): (K, V) =
  # Note: This creates a copy to avoid holding lock during iteration
  var items: seq[(K, V)]
  withLock(m.lock):
    for k, v in m.data:
      items.add((k, v))
  
  for item in items:
    yield item

# ===========================
# GoChan Implementation
# ===========================

proc newGoChan*[T](capacity: int = 0): GoChan[T] =
  new(result)
  result.queue = initDeque[T]()
  initLock(result.lock)
  initCond(result.cond)
  result.capacity = capacity
  result.closed = false

proc send*[T](ch: GoChan[T], val: T) =
  withLock(ch.lock):
    if ch.closed:
      raise newException(ValueError, "send on closed channel")
    
    # Block if channel is full
    while ch.capacity > 0 and ch.queue.len >= ch.capacity:
      wait(ch.cond, ch.lock)
      if ch.closed:
        raise newException(ValueError, "send on closed channel")
    
    ch.queue.addLast(val)
    signal(ch.cond)

proc recv*[T](ch: GoChan[T]): T =
  withLock(ch.lock):
    # Block until data available
    while ch.queue.len == 0 and not ch.closed:
      wait(ch.cond, ch.lock)
    
    if ch.queue.len == 0 and ch.closed:
      # Return zero value
      result = default(T)
    else:
      result = ch.queue.popFirst()
      signal(ch.cond)

proc tryRecv*[T](ch: GoChan[T]): tuple[val: T, ok: bool] =
  withLock(ch.lock):
    if ch.queue.len > 0:
      result.val = ch.queue.popFirst()
      result.ok = true
      signal(ch.cond)
    else:
      result.val = default(T)
      result.ok = false

proc close*[T](ch: GoChan[T]) =
  withLock(ch.lock):
    if ch.closed:
      raise newException(ValueError, "close of closed channel")
    ch.closed = true
    broadcast(ch.cond)

proc isClosed*[T](ch: GoChan[T]): bool =
  withLock(ch.lock):
    ch.closed

# ===========================
# Goroutine Implementation
# ===========================

var goroutineCounter {.global.}: Atomic[int]
var goroutines {.global.}: Table[int, Goroutine]
var goroutinesLock {.global.}: Lock

proc initGoroutineSystem*() =
  goroutineCounter.store(0)
  initLock(goroutinesLock)

proc spawn*(fn: GoFunc) =
  var gr: Goroutine
  new(gr)
  gr.id = goroutineCounter.fetchAdd(1) + 1
  gr.fn = fn
  
  proc threadProc(fn: GoFunc) {.thread.} =
    try:
      fn()
    except:
      stderr.writeLine("Panic in goroutine: " & getCurrentExceptionMsg())
  
  createThread(gr.thread, threadProc, fn)
  
  withLock(goroutinesLock):
    goroutines[gr.id] = gr

# ===========================
# Panic and Recover
# ===========================

type
  PanicException = ref object of CatchableError
    value: GoInterface

proc panic*(msg: string) =
  var exc = PanicException(msg: msg)
  exc.value = nil
  raise exc

proc panic*(value: GoInterface) =
  var exc = PanicException(msg: "panic")
  exc.value = value
  raise exc

proc recover*(): GoInterface =
  let exc = getCurrentException()
  if exc of PanicException:
    result = PanicException(exc).value
  else:
    result = nil

# ===========================
# Complex Number Operations
# ===========================

proc complex64*(real, imag: float32): GoComplex64 =
  GoComplex64(real: real, imag: imag)

proc complex128*(real, imag: float64): GoComplex128 =
  GoComplex128(real: real, imag: imag)

proc real*(c: GoComplex64): float32 = c.real
proc imag*(c: GoComplex64): float32 = c.imag
proc real*(c: GoComplex128): float64 = c.real
proc imag*(c: GoComplex128): float64 = c.imag

proc `+`*(a, b: GoComplex64): GoComplex64 =
  GoComplex64(real: a.real + b.real, imag: a.imag + b.imag)

proc `+`*(a, b: GoComplex128): GoComplex128 =
  GoComplex128(real: a.real + b.real, imag: a.imag + b.imag)

proc `-`*(a, b: GoComplex64): GoComplex64 =
  GoComplex64(real: a.real - b.real, imag: a.imag - b.imag)

proc `-`*(a, b: GoComplex128): GoComplex128 =
  GoComplex128(real: a.real - b.real, imag: a.imag - b.imag)

# ===========================
# Make and New
# ===========================

proc make*[T](typ: typedesc[GoSlice[T]], len: int, cap: int = 0): GoSlice[T] =
  let actualCap = if cap == 0: len else: cap
  result = newGoSlice[T](actualCap)
  result.length = len
  for i in 0..<len:
    result.data[i] = default(T)

proc make*[K, V](typ: typedesc[GoMap[K, V]]): GoMap[K, V] =
  newGoMap[K, V]()

proc make*[T](typ: typedesc[GoChan[T]], capacity: int = 0): GoChan[T] =
  newGoChan[T](capacity)

proc new*[T](typ: typedesc[T]): ptr T =
  result = create(T)
  result[] = default(T)

# ===========================
# Initialization
# ===========================

initGoroutineSystem()
