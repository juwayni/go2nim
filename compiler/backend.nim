import json, strutils, tables, sets, os, algorithm, strformat

type
  HybridIR = object
    packages: seq[PackageIR]
    main_package: string

  PackageIR = object
    path: string
    name: string
    types: seq[TypeDef]
    functions: seq[FunctionIR]
    globals: seq[GlobalVar]
    constants: seq[ConstDef]
    imports: seq[string]
    cgo_imports: seq[CGOImport]

  CGOImport = object
    cflags: seq[string]
    ldflags: seq[string]
    headers: seq[string]
    pkg_path: string

  TypeDef = object
    name: string
    kind: string
    fields: seq[FieldDef]
    methods: seq[string]
    underlying: string
    signature: FuncSignature
    type_params: seq[TypeParam]

  TypeParam = object
    name: string
    constraint: string

  FieldDef = object
    name: string
    typ: string
    tag: string

  FunctionIR = object
    name: string
    receiver: ReceiverInfo
    signature: FuncSignature
    body: BodyIR
    is_method: bool
    package: string

  ReceiverInfo = object
    name: string
    typ: string
    pointer: bool

  FuncSignature = object
    params: seq[Param]
    results: seq[Param]
    variadic: bool

  Param = object
    name: string
    typ: string

  BodyIR = object
    blocks: seq[BlockIR]
    locals: seq[LocalVar]
    free_vars: seq[string]
    struct_hints: Table[string, HintIR]
    defers: seq[DeferInfo]

  HintIR = object
    kind: string
    lines: seq[int]
    labels: seq[string]

  DeferInfo = object
    block_id: int
    call: string

  BlockIR = object
    id: int
    instructions: seq[Instruction]
    successors: seq[int]
    comment: string

  Instruction = object
    op: string
    args: seq[string]
    typ: string
    result: string
    comment: string
    position: int

  LocalVar = object
    name: string
    typ: string

  GlobalVar = object
    name: string
    typ: string
    value: string

  ConstDef = object
    name: string
    typ: string
    value: string

  NimGenerator = object
    ir: HybridIR
    output: string
    currentPkg: string
    typeMap: Table[string, string]
    imports: HashSet[string]
    indent: int

const INDENT_SIZE = 2

proc sanitizeName(name: string): string =
  result = name
  if result.len == 0:
    return "unnamed"
  
  # Replace special characters
  result = result.replace(".", "_")
  result = result.replace("/", "_")
  result = result.replace("-", "_")
  result = result.replace("*", "ptr_")
  result = result.replace("[", "_arr_")
  result = result.replace("]", "")
  result = result.replace("(", "_")
  result = result.replace(")", "_")
  
  # Handle Nim keywords
  const nimKeywords = ["addr", "and", "as", "asm", "bind", "block", "break",
    "case", "cast", "concept", "const", "continue", "converter", "defer",
    "discard", "distinct", "div", "do", "elif", "else", "end", "enum",
    "except", "export", "finally", "for", "from", "func", "if", "import",
    "in", "include", "interface", "is", "isnot", "iterator", "let", "macro",
    "method", "mixin", "mod", "nil", "not", "notin", "object", "of", "or",
    "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr", "static",
    "template", "try", "tuple", "type", "using", "var", "when", "while",
    "with", "without", "xor", "yield"]
  
  if result in nimKeywords:
    result = result & "_go"

proc getIndent(gen: NimGenerator): string =
  " ".repeat(gen.indent * INDENT_SIZE)

proc emit(gen: var NimGenerator, line: string) =
  gen.output.add(gen.getIndent() & line & "\n")

proc emitRaw(gen: var NimGenerator, text: string) =
  gen.output.add(text)

proc convertType(gen: var NimGenerator, goType: string): string =
  # Handle pointer types
  if goType.startsWith("*"):
    let innerType = goType[1..^1]
    return "ptr " & gen.convertType(innerType)
  
  # Handle slice types
  if goType.startsWith("[]"):
    let elemType = goType[2..^1]
    return &"GoSlice[{gen.convertType(elemType)}]"
  
  # Handle array types
  if goType.startsWith("[") and "]" in goType:
    let parts = goType.split("]")
    if parts.len >= 2:
      let size = parts[0][1..^1]
      let elemType = parts[1]
      return &"array[{size}, {gen.convertType(elemType)}]"
  
  # Handle map types
  if goType.startsWith("map["):
    var depth = 0
    var keyEnd = -1
    for i, c in goType:
      if c == '[': depth.inc
      elif c == ']':
        depth.dec
        if depth == 0:
          keyEnd = i
          break
    if keyEnd > 0:
      let keyType = goType[4..<keyEnd]
      let valType = goType[keyEnd+1..^1]
      return &"GoMap[{gen.convertType(keyType)}, {gen.convertType(valType)}]"
  
  # Handle channel types
  if goType.startsWith("chan "):
    let elemType = goType[5..^1]
    return &"GoChan[{gen.convertType(elemType)}]"
  
  if goType.startsWith("<-chan "):
    let elemType = goType[7..^1]
    return &"GoRecvChan[{gen.convertType(elemType)}]"
  
  if goType.startsWith("chan<- "):
    let elemType = goType[7..^1]
    return &"GoSendChan[{gen.convertType(elemType)}]"
  
  # Handle function types
  if goType.startsWith("func("):
    return "GoFunc"
  
  # Handle interface{}
  if goType == "interface{}" or goType == "interface {}":
    return "GoInterface"
  
  # Handle built-in types
  case goType
  of "bool": return "bool"
  of "int": return "GoInt"
  of "int8": return "int8"
  of "int16": return "int16"
  of "int32": return "int32"
  of "int64": return "int64"
  of "uint": return "GoUint"
  of "uint8", "byte": return "uint8"
  of "uint16": return "uint16"
  of "uint32": return "uint32"
  of "uint64": return "uint64"
  of "uintptr": return "uint"
  of "float32": return "float32"
  of "float64": return "float64"
  of "complex64": return "GoComplex64"
  of "complex128": return "GoComplex128"
  of "string": return "GoString"
  of "rune": return "Rune"
  of "error": return "GoError"
  else:
    # Package-qualified types
    if "." in goType:
      let parts = goType.split(".")
      if parts.len == 2:
        return sanitizeName(parts[0]) & "_" & sanitizeName(parts[1])
    return sanitizeName(goType)

proc generateTypeDefinition(gen: var NimGenerator, typeDef: TypeDef) =
  let typeName = sanitizeName(typeDef.name)

  case typeDef.kind
  of "struct":
    gen.emit(&"type {typeName}* = object")
    gen.indent.inc
    if typeDef.fields.len == 0:
      gen.emit("discard")  # Empty struct, use discard
    else:
      for field in typeDef.fields:
        let fieldName = sanitizeName(field.name)
        # Check for missing type and handle gracefully
        let fieldType = if field.typ.len > 0:
                          gen.convertType(field.typ) 
                        else:
                          echo "Warning: Missing type for field '{fieldName}' in struct '{typeName}', defaulting to 'void'."
                          "void"  # Default to 'void' if no type is found

        gen.emit(&"{fieldName}*: {fieldType}")

    gen.indent.dec
    gen.emit("")

  of "interface":
    gen.emit(&"type {typeName}* = ref object of GoInterface")
    gen.indent.inc
    if typeDef.fields.len == 0:
      gen.emit("discard")
    gen.indent.dec
    gen.emit("")

  of "alias":
    let underlyingType = if typeDef.underlying.len > 0:
                          gen.convertType(typeDef.underlying)
                        else:
                          "void"  # Default to 'void' if underlying type is missing
    gen.emit(&"type {typeName}* = {underlyingType}")
    gen.emit("")

  of "func":
    var paramTypes: seq[string]
    for param in typeDef.signature.params:
      paramTypes.add(gen.convertType(param.typ))

    var resultType = "void"
    if typeDef.signature.results.len == 1:
      resultType = gen.convertType(typeDef.signature.results[0].typ)
    elif typeDef.signature.results.len > 1:
      var resultTypes: seq[string]
      for res in typeDef.signature.results:
        resultTypes.add(gen.convertType(res.typ))
      resultType = &"tuple[{resultTypes.join(\", \")}]"

    let paramList = paramTypes.join(", ")
    gen.emit(&"type {typeName}* = proc({paramList}): {resultType}")
    gen.emit("")

  else:
    echo "Warning: Unsupported type kind: {typeDef.kind} for {typeName}"

proc generateInstruction(gen: var NimGenerator, instr: Instruction) =
  case instr.op
  of "Alloc":
    if instr.result.len > 0:
      let varName = sanitizeName(instr.result)
      let varType = gen.convertType(instr.typ)
      gen.emit(&"var {varName}: {varType}")
  
  of "Store":
    if instr.args.len >= 2:
      let dest = sanitizeName(instr.args[0])
      let src = sanitizeName(instr.args[1])
      gen.emit(&"{dest} = {src}")
  
  of "UnOp":
    if instr.result.len > 0 and instr.args.len > 0:
      let res = sanitizeName(instr.result)
      let arg = sanitizeName(instr.args[0])
      gen.emit(&"let {res} = not {arg}  # {instr.comment}")
  
  of "BinOp":
    if instr.result.len > 0 and instr.args.len >= 2:
      let res = sanitizeName(instr.result)
      let lhs = sanitizeName(instr.args[0])
      let rhs = sanitizeName(instr.args[1])
      gen.emit(&"let {res} = {lhs} + {rhs}  # {instr.comment}")
  
  of "Call", "Go":
    var callStr = ""
    if instr.args.len > 0:
      let fnName = sanitizeName(instr.args[0])
      var args: seq[string]
      for i in 1..<instr.args.len:
        args.add(sanitizeName(instr.args[i]))
      
      if instr.op == "Go":
        callStr = &"spawn {fnName}({args.join(\", \")})"
      else:
        callStr = &"{fnName}({args.join(\", \")})"
      
      if instr.result.len > 0:
        let res = sanitizeName(instr.result)
        gen.emit(&"let {res} = {callStr}")
      else:
        gen.emit(callStr)
  
  of "Return":
    if instr.args.len > 0:
      var rets: seq[string]
      for arg in instr.args:
        rets.add(sanitizeName(arg))
      gen.emit(&"return {rets.join(\", \")}")
    else:
      gen.emit("return")
  
  of "If":
    if instr.args.len > 0:
      let cond = sanitizeName(instr.args[0])
      gen.emit(&"if {cond}:")
      gen.indent.inc
      gen.emit("discard")
      gen.indent.dec
  
  of "Jump":
    gen.emit(&"# jump to block")
  
  of "Defer":
    gen.emit(&"deferStack.add(proc() = {instr.comment})")
  
  of "MakeChan":
    if instr.result.len > 0:
      let res = sanitizeName(instr.result)
      let chanType = gen.convertType(instr.typ)
      gen.emit(&"let {res} = newGoChan[{chanType}]()")
  
  of "Send":
    if instr.args.len >= 2:
      let chan = sanitizeName(instr.args[0])
      let val = sanitizeName(instr.args[1])
      gen.emit(&"{chan}.send({val})")
  
  of "Recv":
    if instr.result.len > 0 and instr.args.len > 0:
      let res = sanitizeName(instr.result)
      let chan = sanitizeName(instr.args[0])
      gen.emit(&"let {res} = {chan}.recv()")
  
  else:
    gen.emit(&"# {instr.op}: {instr.comment}")

proc generateBlocks(gen: var NimGenerator, blocks: seq[BlockIR], hints: Table[string, HintIR]) =
  if blocks.len == 0:
    gen.emit("discard")
    return
  
  # Simple linear generation for now
  for i, blk in blocks:
    if i > 0:
      gen.emit(&"block_{blk.id}:")
      gen.indent.inc
    
    for instr in blk.instructions:
      gen.generateInstruction(instr)
    
    if i > 0:
      gen.indent.dec

proc generateFunctionBody(gen: var NimGenerator, body: BodyIR) =
  # Declare locals
  for local in body.locals:
    let localName = sanitizeName(local.name)
    let localType = gen.convertType(local.typ)
    gen.emit(&"var {localName}: {localType}")
  
  if body.locals.len > 0:
    gen.emit("")
  
  # Handle defer stack
  if body.defers.len > 0:
    gen.emit("var deferStack: seq[proc()]")
    gen.emit("defer:")
    gen.indent.inc
    gen.emit("for i in countdown(deferStack.high, 0):")
    gen.indent.inc
    gen.emit("deferStack[i]()")
    gen.indent.dec
    gen.indent.dec
    gen.emit("")
  
  # Generate basic blocks
  gen.generateBlocks(body.blocks, body.struct_hints)

proc generateFunction(gen: var NimGenerator, fn: FunctionIR) =
  var procName = sanitizeName(fn.name)
  
  # Handle receiver (methods)
  var receiverParam = ""
  if fn.is_method and fn.receiver.name.len > 0:
    let recvType = gen.convertType(fn.receiver.typ)
    let recvName = sanitizeName(fn.receiver.name)
    if fn.receiver.pointer:
      receiverParam = &"self: var {recvType}"
    else:
      receiverParam = &"self: {recvType}"
  
  # Build parameter list
  var params: seq[string]
  if receiverParam.len > 0:
    params.add(receiverParam)
  
  for param in fn.signature.params:
    let paramName = sanitizeName(param.name)
    let paramType = gen.convertType(param.typ)
    params.add(&"{paramName}: {paramType}")
  
  # Build return type
  var returnType = ""
  if fn.signature.results.len == 1:
    returnType = ": " & gen.convertType(fn.signature.results[0].typ)
  elif fn.signature.results.len > 1:
    var resultTypes: seq[string]
    for res in fn.signature.results:
      resultTypes.add(gen.convertType(res.typ))
    returnType = &": tuple[{resultTypes.join(\", \")}]"
  
  # Generate function signature
  let paramList = params.join(", ")
  gen.emit(&"proc {procName}*({paramList}){returnType} =")
  gen.indent.inc
  
  # Generate body
  if fn.body.blocks.len == 0:
    gen.emit("discard")
  else:
    gen.generateFunctionBody(fn.body)
  
  gen.indent.dec
  gen.emit("")

proc generatePackage(gen: var NimGenerator, pkg: PackageIR) =
  gen.currentPkg = pkg.name
  
  gen.emit(&"# Package: {pkg.path}")
  gen.emit("")
  
  # Generate CGO imports
  for cgoImport in pkg.cgo_imports:
    for header in cgoImport.headers:
      gen.emit(&"# CGO: {header}")
    for cflag in cgoImport.cflags:
      gen.emit(&"{{.passC: \"{cflag}\".}}")
    for ldflag in cgoImport.ldflags:
      gen.emit(&"{{.passL: \"{ldflag}\".}}")
    gen.emit("")
  
  # Generate constants
  for constant in pkg.constants:
    let constName = sanitizeName(constant.name)
    let constType = gen.convertType(constant.typ)
    gen.emit(&"const {constName}*: {constType} = {constant.value}")
  
  if pkg.constants.len > 0:
    gen.emit("")
  
  # Generate type definitions
  for typeDef in pkg.types:
    gen.generateTypeDefinition(typeDef)
  
  # Generate globals
  for global in pkg.globals:
    let globalName = sanitizeName(global.name)
    let globalType = gen.convertType(global.typ)
    if global.value.len > 0:
      gen.emit(&"var {globalName}*: {globalType} = {global.value}")
    else:
      gen.emit(&"var {globalName}*: {globalType}")
  
  if pkg.globals.len > 0:
    gen.emit("")
  
  # Generate functions
  for fn in pkg.functions:
    gen.generateFunction(fn)

proc generateRuntime(outputDir: string) =
  # Generate runtime.nim with Go runtime primitives
  let runtimeCode = """
# Go Runtime for Nim
import std/[asyncdispatch, locks, hashes, tables]

type
  GoInt* = int
  GoUint* = uint
  Rune* = int32
  
  GoString* = object
    data*: seq[byte]
    length*: int
  
  GoSlice*[T] = object
    data*: seq[T]
    length*: int
    capacity*: int
  
  GoMap*[K, V] = ref object
    data*: Table[K, V]
  
  GoChan*[T] = ref object
    queue*: seq[T]
    lock*: Lock
    capacity*: int
  
  GoRecvChan*[T] = GoChan[T]
  GoSendChan*[T] = GoChan[T]
  
  GoInterface* = ref object of RootObj
  
  GoError* = ref object of Exception
  
  GoFunc* = proc()
  
  GoComplex64* = object
    real*: float32
    imag*: float32
  
  GoComplex128* = object
    real*: float64
    imag*: float64

proc newGoString*(s: string): GoString =
  result.data = cast[seq[byte]](s)
  result.length = s.len

proc `$`*(s: GoString): string =
  result = newString(s.length)
  for i in 0..<s.length:
    result[i] = char(s.data[i])

proc newGoSlice*[T](cap: int = 0): GoSlice[T] =
  result.data = newSeq[T](cap)
  result.length = 0
  result.capacity = cap

proc append*[T](s: var GoSlice[T], items: varargs[T]) =
  for item in items:
    if s.length >= s.capacity:
      s.capacity = if s.capacity == 0: 1 else: s.capacity * 2
      s.data.setLen(s.capacity)
    s.data[s.length] = item
    s.length.inc

proc `[]`*[T](s: GoSlice[T], i: int): T =
  s.data[i]

proc `[]=`*[T](s: var GoSlice[T], i: int, val: T) =
  s.data[i] = val

proc len*[T](s: GoSlice[T]): int =
  s.length

proc cap*[T](s: GoSlice[T]): int =
  s.capacity

proc newGoMap*[K, V](): GoMap[K, V] =
  new(result)
  result.data = initTable[K, V]()

proc `[]`*[K, V](m: GoMap[K, V], key: K): V =
  m.data[key]

proc `[]=`*[K, V](m: GoMap[K, V], key: K, val: V) =
  m.data[key] = val

proc contains*[K, V](m: GoMap[K, V], key: K): bool =
  m.data.hasKey(key)

proc delete*[K, V](m: GoMap[K, V], key: K) =
  m.data.del(key)

proc newGoChan*[T](capacity: int = 0): GoChan[T] =
  new(result)
  result.queue = newSeq[T]()
  result.capacity = capacity
  initLock(result.lock)

proc send*[T](ch: GoChan[T], val: T) =
  withLock(ch.lock):
    ch.queue.add(val)

proc recv*[T](ch: GoChan[T]): T =
  withLock(ch.lock):
    while ch.queue.len == 0:
      discard
    result = ch.queue[0]
    ch.queue.delete(0)

proc close*[T](ch: GoChan[T]) =
  discard

proc spawn*(fn: proc()) =
  # Simple goroutine simulation using thread
  var thr: Thread[void]
  createThread(thr, fn)

proc panic*(msg: string) =
  raise newException(GoError, msg)

proc recover*(): GoInterface =
  # Simplified recover
  result = nil
"""
  
  writeFile(outputDir / "runtime.nim", runtimeCode)

proc generate*(irPath: string, outputDir: string) =
  let jsonContent = readFile(irPath)
  let ir = to(parseJson(jsonContent), HybridIR)
  
  createDir(outputDir)
  generateRuntime(outputDir)
  
  var gen = NimGenerator(
    ir: ir,
    output: "",
    typeMap: initTable[string, string](),
    imports: initHashSet[string](),
    indent: 0
  )
  
  # Generate main output file
  gen.emit("import runtime")
  gen.emit("")
  
  for pkg in ir.packages:
    gen.generatePackage(pkg)
  
  # Write main output
  writeFile(outputDir / "main.nim", gen.output)
  
  echo &"Generated Nim code in: {outputDir}"

when isMainModule:
  import parseopt
  
  var irPath = ""
  var outputDir = "nim_output"
  
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "i", "input": irPath = p.val
      of "o", "output": outputDir = p.val
    of cmdArgument:
      if irPath.len == 0:
        irPath = p.key
  
  if irPath.len == 0:
    echo "Usage: nim c -r backend.nim -i input.json -o output_dir"
    quit(1)
  
  generate(irPath, outputDir)
