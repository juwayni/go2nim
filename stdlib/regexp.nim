## Go regexp package implementation in Nim
import std/[re, strutils, sequtils]
import ../runtime

type
  Regexp* = ref object
    pattern: string
    regex: Regex
  
  MatchResult* = object
    found: bool
    matches: seq[string]
    indices: seq[tuple[start: int, stop: int]]

# Compile regular expression
proc Compile*(expr: string): tuple[re: Regexp, err: GoError] =
  try:
    var r = Regexp()
    new(r)
    r.pattern = expr
    r.regex = re.re(expr)
    result.re = r
    result.err = nil
  except:
    result.err = newException(GoError, getCurrentExceptionMsg())

proc MustCompile*(expr: string): Regexp =
  let (r, err) = Compile(expr)
  if err != nil:
    panic("regexp: " & err.msg)
  r

proc CompilePOSIX*(expr: string): tuple[re: Regexp, err: GoError] =
  Compile(expr)

proc MustCompilePOSIX*(expr: string): Regexp =
  MustCompile(expr)

# Match functions
proc Match*(pattern: string, b: openArray[byte]): tuple[matched: bool, err: GoError] =
  try:
    let s = cast[string](b)
    result.matched = s.contains(re(pattern))
    result.err = nil
  except:
    result.err = newException(GoError, getCurrentExceptionMsg())

proc MatchString*(pattern: string, s: string): tuple[matched: bool, err: GoError] =
  try:
    result.matched = s.contains(re(pattern))
    result.err = nil
  except:
    result.err = newException(GoError, getCurrentExceptionMsg())

proc MatchReader*(pattern: string, r: Reader): tuple[matched: bool, err: GoError] =
  try:
    let (data, readErr) = ReadAll(r)
    if readErr != nil:
      result.err = readErr
      return
    
    let s = cast[string](data)
    result.matched = s.contains(re(pattern))
    result.err = nil
  except:
    result.err = newException(GoError, getCurrentExceptionMsg())

# Regexp methods
proc String*(re: Regexp): GoString =
  newGoString(re.pattern)

proc Match*(re: Regexp, b: openArray[byte]): bool =
  let s = cast[string](b)
  s.contains(re.regex)

proc MatchString*(re: Regexp, s: string): bool =
  s.contains(re.regex)

proc Find*(re: Regexp, b: openArray[byte]): seq[byte] =
  let s = cast[string](b)
  var matches: array[1, string]
  if s.match(re.regex, matches):
    cast[seq[byte]](matches[0])
  else:
    @[]

proc FindString*(re: Regexp, s: string): GoString =
  var matches: array[1, string]
  if s.match(re.regex, matches):
    newGoString(matches[0])
  else:
    newGoString("")

proc FindAll*(re: Regexp, b: openArray[byte], n: int): seq[seq[byte]] =
  let s = cast[string](b)
  var results: seq[seq[byte]] = @[]
  
  for match in s.findAll(re.regex):
    results.add(cast[seq[byte]](match))
    if n > 0 and results.len >= n:
      break
  
  results

proc FindAllString*(re: Regexp, s: string, n: int): seq[GoString] =
  var results: seq[GoString] = @[]
  
  for match in s.findAll(re.regex):
    results.add(newGoString(match))
    if n > 0 and results.len >= n:
      break
  
  results

proc FindIndex*(re: Regexp, b: openArray[byte]): seq[int] =
  let s = cast[string](b)
  var matches: array[1, string]
  let start = s.find(re.regex, matches)
  
  if start >= 0:
    @[start, start + matches[0].len]
  else:
    @[]

proc FindStringIndex*(re: Regexp, s: string): seq[int] =
  var matches: array[1, string]
  let start = s.find(re.regex, matches)
  
  if start >= 0:
    @[start, start + matches[0].len]
  else:
    @[]

proc FindAllIndex*(re: Regexp, b: openArray[byte], n: int): seq[seq[int]] =
  let s = cast[string](b)
  var results: seq[seq[int]] = @[]
  var offset = 0
  
  while offset < s.len:
    var matches: array[1, string]
    let start = s[offset..^1].find(re.regex, matches)
    
    if start < 0:
      break
    
    let absoluteStart = offset + start
    results.add(@[absoluteStart, absoluteStart + matches[0].len])
    offset = absoluteStart + matches[0].len
    
    if n > 0 and results.len >= n:
      break
  
  results

proc FindAllStringIndex*(re: Regexp, s: string, n: int): seq[seq[int]] =
  FindAllIndex(re, cast[seq[byte]](s), n)

# Submatch functions
proc FindSubmatch*(re: Regexp, b: openArray[byte]): seq[seq[byte]] =
  let s = cast[string](b)
  var matches: array[10, string]
  
  if s.match(re.regex, matches):
    var results: seq[seq[byte]] = @[]
    for m in matches:
      if m.len > 0:
        results.add(cast[seq[byte]](m))
    results
  else:
    @[]

proc FindStringSubmatch*(re: Regexp, s: string): seq[GoString] =
  var matches: array[10, string]
  
  if s.match(re.regex, matches):
    var results: seq[GoString] = @[]
    for m in matches:
      if m.len > 0:
        results.add(newGoString(m))
    results
  else:
    @[]

# Replace functions
proc ReplaceAll*(re: Regexp, src: openArray[byte], repl: openArray[byte]): seq[byte] =
  let s = cast[string](src)
  let r = cast[string](repl)
  cast[seq[byte]](s.replace(re.regex, r))

proc ReplaceAllString*(re: Regexp, src: string, repl: string): GoString =
  newGoString(src.replace(re.regex, repl))

proc ReplaceAllLiteral*(re: Regexp, src: openArray[byte], repl: openArray[byte]): seq[byte] =
  ReplaceAll(re, src, repl)

proc ReplaceAllLiteralString*(re: Regexp, src: string, repl: string): GoString =
  ReplaceAllString(re, src, repl)

proc ReplaceAllFunc*(re: Regexp, src: openArray[byte], repl: proc(s: seq[byte]): seq[byte]): seq[byte] =
  let s = cast[string](src)
  var result = s
  
  for match in s.findAll(re.regex):
    let replacement = repl(cast[seq[byte]](match))
    result = result.replace(match, cast[string](replacement))
  
  cast[seq[byte]](result)

proc ReplaceAllStringFunc*(re: Regexp, src: string, repl: proc(s: string): string): GoString =
  var result = src
  
  for match in src.findAll(re.regex):
    let replacement = repl(match)
    result = result.replace(match, replacement)
  
  newGoString(result)

# Split functions
proc Split*(re: Regexp, s: string, n: int): seq[GoString] =
  var parts: seq[string]
  
  if n < 0:
    parts = s.split(re.regex)
  else:
    parts = s.split(re.regex, maxsplit = n - 1)
  
  var results: seq[GoString] = @[]
  for part in parts:
    results.add(newGoString(part))
  
  results

# Quote escapes special characters
proc QuoteMeta*(s: string): GoString =
  var result = ""
  const special = r"\.+*?()|[]{}^$"
  
  for c in s:
    if c in special:
      result.add('\\')
    result.add(c)
  
  newGoString(result)
