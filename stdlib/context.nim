## Go context package implementation in Nim
import std/[times, locks, tables]
import ../runtime, ../time

type
  Context* = ref object of RootObj
    deadline: Option[Time]
    done: GoChan[bool]
    err: GoError
    values: Table[string, GoInterface]
    lock: Lock
    cancelled: bool
  
  CancelFunc* = proc() {.gcsafe.}

var
  background {.global.}: Context
  todo {.global.}: Context

# Initialize global contexts
proc initContexts() =
  new(background)
  background.done = newGoChan[bool]()
  background.values = initTable[string, GoInterface]()
  initLock(background.lock)
  
  new(todo)
  todo.done = newGoChan[bool]()
  todo.values = initTable[string, GoInterface]()
  initLock(todo.lock)

initContexts()

# Background returns a non-nil, empty Context
proc Background*(): Context =
  background

# TODO returns a non-nil, empty Context
proc TODO*(): Context =
  todo

# WithCancel returns a copy with cancellation
proc WithCancel*(parent: Context): tuple[ctx: Context, cancel: CancelFunc] =
  var ctx = Context()
  new(ctx)
  ctx.done = newGoChan[bool]()
  ctx.values = initTable[string, GoInterface]()
  initLock(ctx.lock)
  ctx.cancelled = false
  
  # Copy parent values
  withLock(parent.lock):
    for k, v in parent.values:
      ctx.values[k] = v
  
  # Copy deadline if exists
  if parent.deadline.isSome:
    ctx.deadline = parent.deadline
  
  let cancel = proc() {.gcsafe.} =
    withLock(ctx.lock):
      if not ctx.cancelled:
        ctx.cancelled = true
        ctx.err = newException(GoError, "context canceled")
        ctx.done.close()
  
  result.ctx = ctx
  result.cancel = cancel

# WithDeadline returns a copy with deadline
proc WithDeadline*(parent: Context, deadline: Time): tuple[ctx: Context, cancel: CancelFunc] =
  var ctx = Context()
  new(ctx)
  ctx.done = newGoChan[bool]()
  ctx.values = initTable[string, GoInterface]()
  initLock(ctx.lock)
  ctx.cancelled = false
  ctx.deadline = some(deadline)
  
  # Copy parent values
  withLock(parent.lock):
    for k, v in parent.values:
      ctx.values[k] = v
  
  let cancel = proc() {.gcsafe.} =
    withLock(ctx.lock):
      if not ctx.cancelled:
        ctx.cancelled = true
        ctx.err = newException(GoError, "context canceled")
        ctx.done.close()
  
  # Start deadline timer
  proc deadlineTimer() {.gcsafe.} =
    let duration = deadline.Sub(Now())
    if duration > 0.Duration:
      Sleep(duration)
    
    withLock(ctx.lock):
      if not ctx.cancelled:
        ctx.cancelled = true
        ctx.err = newException(GoError, "context deadline exceeded")
        ctx.done.close()
  
  spawn(deadlineTimer)
  
  result.ctx = ctx
  result.cancel = cancel

# WithTimeout returns a copy with timeout
proc WithTimeout*(parent: Context, timeout: Duration): tuple[ctx: Context, cancel: CancelFunc] =
  let deadline = Now().Add(timeout)
  WithDeadline(parent, deadline)

# WithValue returns a copy with key-value pair
proc WithValue*(parent: Context, key: string, value: GoInterface): Context =
  var ctx = Context()
  new(ctx)
  ctx.done = newGoChan[bool]()
  ctx.values = initTable[string, GoInterface]()
  initLock(ctx.lock)
  
  # Copy parent values
  withLock(parent.lock):
    for k, v in parent.values:
      ctx.values[k] = v
  
  # Add new value
  ctx.values[key] = value
  
  # Copy deadline if exists
  if parent.deadline.isSome:
    ctx.deadline = parent.deadline
  
  ctx

# Context methods
proc Deadline*(ctx: Context): tuple[deadline: Time, ok: bool] =
  if ctx.deadline.isSome:
    result.deadline = ctx.deadline.get()
    result.ok = true
  else:
    result.ok = false

proc Done*(ctx: Context): GoChan[bool] =
  ctx.done

proc Err*(ctx: Context): GoError =
  withLock(ctx.lock):
    ctx.err

proc Value*(ctx: Context, key: string): GoInterface =
  withLock(ctx.lock):
    if ctx.values.hasKey(key):
      ctx.values[key]
    else:
      nil

# Error definitions
var
  Canceled* = newException(GoError, "context canceled")
  DeadlineExceeded* = newException(GoError, "context deadline exceeded")
