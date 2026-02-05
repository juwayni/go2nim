## Go fmt package implementation in Nim
import std/[strformat, strutils, macros]
import ../runtime

type
  Formatter* = object
    buf: string
    
  Stringer* = concept x
    $x is string

proc newFormatter*(): Formatter =
  result.buf = ""

proc write*(f: var Formatter, s: string) =
  f.buf.add(s)

proc writeRune*(f: var Formatter, r: Rune) =
  f.buf.add(char(r))

proc writeByte*(f: var Formatter, b: byte) =
  f.buf.add(char(b))

proc toString*(f: Formatter): string =
  f.buf

# Print functions
proc Print*(args: varargs[string, `$`]): tuple[n: int, err: GoError] =
  var output = ""
  for i, arg in args:
    if i > 0:
      output.add(" ")
    output.add(arg)
  stdout.write(output)
  result.n = output.len
  result.err = nil

proc Println*(args: varargs[string, `$`]): tuple[n: int, err: GoError] =
  var output = ""
  for i, arg in args:
    if i > 0:
      output.add(" ")
    output.add(arg)
  stdout.write(output & "\n")
  result.n = output.len + 1
  result.err = nil

proc Printf*(format: string, args: varargs[string, `$`]): tuple[n: int, err: GoError] =
  var output = format
  var argIdx = 0
  var i = 0
  
  while i < output.len:
    if output[i] == '%' and i + 1 < output.len:
      let verb = output[i + 1]
      var replacement = ""
      
      if argIdx < args.len:
        case verb
        of 'd', 'i':  # Integer
          replacement = args[argIdx]
        of 's':  # String
          replacement = args[argIdx]
        of 'v':  # Default format
          replacement = args[argIdx]
        of 'T':  # Type
          replacement = $type(args[argIdx])
        of 'f', 'F':  # Float
          replacement = args[argIdx]
        of 'e', 'E':  # Scientific
          replacement = args[argIdx]
        of 'x', 'X':  # Hexadecimal
          replacement = args[argIdx]
        of 'o':  # Octal
          replacement = args[argIdx]
        of 'b':  # Binary
          replacement = args[argIdx]
        of 'c':  # Character
          replacement = args[argIdx]
        of 'p':  # Pointer
          replacement = args[argIdx]
        of 't':  # Boolean
          replacement = args[argIdx]
        of 'q':  # Quoted
          replacement = "\"" & args[argIdx] & "\""
        of '%':  # Literal %
          replacement = "%"
        else:
          replacement = "%" & $verb
        
        if verb != '%':
          argIdx.inc
      
      output = output[0..<i] & replacement & output[i+2..^1]
      i += replacement.len
    else:
      i.inc
  
  stdout.write(output)
  result.n = output.len
  result.err = nil

proc Fprint*(w: File, args: varargs[string, `$`]): tuple[n: int, err: GoError] =
  var output = ""
  for i, arg in args:
    if i > 0:
      output.add(" ")
    output.add(arg)
  w.write(output)
  result.n = output.len
  result.err = nil

proc Fprintln*(w: File, args: varargs[string, `$`]): tuple[n: int, err: GoError] =
  var output = ""
  for i, arg in args:
    if i > 0:
      output.add(" ")
    output.add(arg)
  w.write(output & "\n")
  result.n = output.len + 1
  result.err = nil

proc Fprintf*(w: File, format: string, args: varargs[string, `$`]): tuple[n: int, err: GoError] =
  let (n, err) = Printf(format, args)
  result.n = n
  result.err = err

proc Sprint*(args: varargs[string, `$`]): string =
  result = ""
  for i, arg in args:
    if i > 0:
      result.add(" ")
    result.add(arg)

proc Sprintln*(args: varargs[string, `$`]): string =
  result = ""
  for i, arg in args:
    if i > 0:
      result.add(" ")
    result.add(arg)
  result.add("\n")

proc Sprintf*(format: string, args: varargs[string, `$`]): string =
  result = format
  var argIdx = 0
  var i = 0
  
  while i < result.len:
    if result[i] == '%' and i + 1 < result.len:
      let verb = result[i + 1]
      var replacement = ""
      
      if argIdx < args.len:
        case verb
        of 'd', 'i', 's', 'v', 'f', 'F', 'e', 'E', 'x', 'X', 'o', 'b', 'c', 'p', 't':
          replacement = args[argIdx]
          argIdx.inc
        of 'q':
          replacement = "\"" & args[argIdx] & "\""
          argIdx.inc
        of '%':
          replacement = "%"
        else:
          replacement = "%" & $verb
      
      result = result[0..<i] & replacement & result[i+2..^1]
      i += replacement.len
    else:
      i.inc

proc Errorf*(format: string, args: varargs[string, `$`]): GoError =
  let msg = Sprintf(format, args)
  result = newException(GoError, msg)

# Scan functions
proc Scan*(args: varargs[ptr string]): tuple[n: int, err: GoError] =
  var input = ""
  try:
    input = stdin.readLine()
  except:
    result.err = newException(GoError, "Failed to read input")
    return
  
  let parts = input.split()
  var scanned = 0
  
  for i in 0..<min(args.len, parts.len):
    args[i][] = parts[i]
    scanned.inc
  
  result.n = scanned
  result.err = nil

proc Scanln*(args: varargs[ptr string]): tuple[n: int, err: GoError] =
  Scan(args)

proc Scanf*(format: string, args: varargs[ptr string]): tuple[n: int, err: GoError] =
  # Simplified scanf
  Scan(args)

proc Fscan*(r: File, args: varargs[ptr string]): tuple[n: int, err: GoError] =
  var input = ""
  try:
    input = r.readLine()
  except:
    result.err = newException(GoError, "Failed to read input")
    return
  
  let parts = input.split()
  var scanned = 0
  
  for i in 0..<min(args.len, parts.len):
    args[i][] = parts[i]
    scanned.inc
  
  result.n = scanned
  result.err = nil

proc Fscanln*(r: File, args: varargs[ptr string]): tuple[n: int, err: GoError] =
  Fscan(r, args)

proc Fscanf*(r: File, format: string, args: varargs[ptr string]): tuple[n: int, err: GoError] =
  Fscan(r, args)

proc Sscan*(str: string, args: varargs[ptr string]): tuple[n: int, err: GoError] =
  let parts = str.split()
  var scanned = 0
  
  for i in 0..<min(args.len, parts.len):
    args[i][] = parts[i]
    scanned.inc
  
  result.n = scanned
  result.err = nil

proc Sscanln*(str: string, args: varargs[ptr string]): tuple[n: int, err: GoError] =
  Sscan(str, args)

proc Sscanf*(str: string, format: string, args: varargs[ptr string]): tuple[n: int, err: GoError] =
  Sscan(str, args)
