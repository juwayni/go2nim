## Go sync package implementation in Nim
import std/[locks, atomics, os, times]
import ../runtime

type
  Mutex* = object
    lock: Lock
  
  RWMutex* = object
    lock: Lock
    readerCount: Atomic[int]
    writerWaiting: Atomic[bool]
  
  WaitGroup* = ref object
    counter: Atomic[int]
    lock: Lock
    cond: Cond
  
  Once* = object
    done: Atomic[bool]
    lock: Lock
  
  Pool*[T] = ref object
    new: proc(): T
    items: seq[T]
    lock: Lock
  
  Cond* = ref object
    lock: ptr Lock
    waiters: int
  
  Map*[K, V] = ref object
    data: Table[K, V]
    lock: Lock

# Mutex implementation
proc init*(m: var Mutex) =
  initLock(m.lock)

proc Lock*(m: var Mutex) =
  acquire(m.lock)

proc Unlock*(m: var Mutex) =
  release(m.lock)

proc TryLock*(m: var Mutex): bool =
  tryAcquire(m.lock)

# RWMutex implementation
proc init*(rw: var RWMutex) =
  initLock(rw.lock)
  rw.readerCount.store(0)
  rw.writerWaiting.store(false)

proc RLock*(rw: var RWMutex) =
  acquire(rw.lock)
  rw.readerCount.atomicInc()
  release(rw.lock)

proc RUnlock*(rw: var RWMutex) =
  acquire(rw.lock)
  rw.readerCount.atomicDec()
  release(rw.lock)

proc Lock*(rw: var RWMutex) =
  rw.writerWaiting.store(true)
  acquire(rw.lock)
  
  # Wait for all readers to finish
  while rw.readerCount.load() > 0:
    sleep(1)
  
  rw.writerWaiting.store(false)

proc Unlock*(rw: var RWMutex) =
  release(rw.lock)

proc TryLock*(rw: var RWMutex): bool =
  if tryAcquire(rw.lock):
    if rw.readerCount.load() == 0:
      return true
    release(rw.lock)
  return false

proc TryRLock*(rw: var RWMutex): bool =
  if tryAcquire(rw.lock):
    rw.readerCount.atomicInc()
    release(rw.lock)
    return true
  return false

# WaitGroup implementation
proc newWaitGroup*(): WaitGroup =
  new(result)
  result.counter.store(0)
  initLock(result.lock)
  initCond(result.cond)

proc Add*(wg: WaitGroup, delta: int) =
  acquire(wg.lock)
  let newVal = wg.counter.load() + delta
  wg.counter.store(newVal)
  
  if newVal == 0:
    signal(wg.cond)
  
  release(wg.lock)

proc Done*(wg: WaitGroup) =
  wg.Add(-1)

proc Wait*(wg: WaitGroup) =
  acquire(wg.lock)
  
  while wg.counter.load() > 0:
    wait(wg.cond, wg.lock)
  
  release(wg.lock)

# Once implementation
proc init*(o: var Once) =
  o.done.store(false)
  initLock(o.lock)

proc Do*(o: var Once, f: proc()) =
  if not o.done.load():
    acquire(o.lock)
    if not o.done.load():
      f()
      o.done.store(true)
    release(o.lock)

# Pool implementation
proc newPool*[T](newFunc: proc(): T): Pool[T] =
  new(result)
  result.new = newFunc
  result.items = @[]
  initLock(result.lock)

proc Get*[T](p: Pool[T]): T =
  acquire(p.lock)
  
  if p.items.len > 0:
    result = p.items[^1]
    p.items.setLen(p.items.len - 1)
  else:
    result = p.new()
  
  release(p.lock)

proc Put*[T](p: Pool[T], item: T) =
  acquire(p.lock)
  p.items.add(item)
  release(p.lock)

# Cond implementation
proc NewCond*(lock: ptr Lock): Cond =
  new(result)
  result.lock = lock
  result.waiters = 0

proc Wait*(c: Cond) =
  c.waiters.inc
  release(c.lock[])
  
  # Simplified wait - in real implementation this would use condition variables
  while c.waiters > 0:
    sleep(1)
  
  acquire(c.lock[])

proc Signal*(c: Cond) =
  if c.waiters > 0:
    c.waiters.dec

proc Broadcast*(c: Cond) =
  c.waiters = 0

# Map implementation
proc newSyncMap*[K, V](): Map[K, V] =
  new(result)
  result.data = initTable[K, V]()
  initLock(result.lock)

proc Load*[K, V](m: Map[K, V], key: K): tuple[value: V, ok: bool] =
  acquire(m.lock)
  if m.data.hasKey(key):
    result.value = m.data[key]
    result.ok = true
  else:
    result.ok = false
  release(m.lock)

proc Store*[K, V](m: Map[K, V], key: K, value: V) =
  acquire(m.lock)
  m.data[key] = value
  release(m.lock)

proc LoadOrStore*[K, V](m: Map[K, V], key: K, value: V): tuple[actual: V, loaded: bool] =
  acquire(m.lock)
  if m.data.hasKey(key):
    result.actual = m.data[key]
    result.loaded = true
  else:
    m.data[key] = value
    result.actual = value
    result.loaded = false
  release(m.lock)

proc Delete*[K, V](m: Map[K, V], key: K) =
  acquire(m.lock)
  m.data.del(key)
  release(m.lock)

proc Range*[K, V](m: Map[K, V], f: proc(key: K, value: V): bool) =
  acquire(m.lock)
  for key, value in m.data:
    if not f(key, value):
      break
  release(m.lock)
