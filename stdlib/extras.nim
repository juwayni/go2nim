## Additional Go stdlib packages

# strings.nim - String manipulation
import std/[strutils, unicode]
import ../runtime

proc Contains*(s, substr: GoString): bool =
  ($s).contains($substr)

proc ContainsAny*(s: GoString, chars: GoString): bool =
  for c in $chars:
    if ($s).contains(c):
      return true
  false

proc Count*(s, substr: GoString): int =
  ($s).count($substr)

proc HasPrefix*(s, prefix: GoString): bool =
  ($s).startsWith($prefix)

proc HasSuffix*(s, suffix: GoString): bool =
  ($s).endsWith($suffix)

proc Index*(s, substr: GoString): int =
  let idx = ($s).find($substr)
  if idx == -1: -1 else: idx

proc Join*(elems: seq[GoString], sep: GoString): GoString =
  var strs: seq[string]
  for e in elems:
    strs.add($e)
  newGoString(strs.join($sep))

proc Split*(s, sep: GoString): seq[GoString] =
  let parts = ($s).split($sep)
  result = @[]
  for p in parts:
    result.add(newGoString(p))

proc ToLower*(s: GoString): GoString =
  newGoString(($s).toLowerAscii())

proc ToUpper*(s: GoString): GoString =
  newGoString(($s).toUpperAscii())

proc Trim*(s: GoString, cutset: GoString): GoString =
  newGoString(($s).strip(chars = {($cutset)[0]}))

proc TrimSpace*(s: GoString): GoString =
  newGoString(($s).strip())

proc Replace*(s, old, new: GoString, n: int): GoString =
  if n < 0:
    newGoString(($s).replace($old, $new))
  else:
    var result = $s
    var count = 0
    while count < n:
      let idx = result.find($old)
      if idx == -1: break
      result = result[0..<idx] & $new & result[idx + ($old).len..^1]
      count.inc
    newGoString(result)

proc Repeat*(s: GoString, count: int): GoString =
  newGoString(($s).repeat(count))

# strconv.nim - String conversion
import std/[parseutils, strutils]
import ../runtime

proc Atoi*(s: GoString): tuple[i: int, err: GoError] =
  try:
    result.i = parseInt($s)
    result.err = nil
  except:
    result.err = newException(GoError, "invalid syntax")

proc Itoa*(i: int): GoString =
  newGoString($i)

proc ParseBool*(str: GoString): tuple[b: bool, err: GoError] =
  let s = ($str).toLowerAscii()
  case s
  of "true", "1", "t", "yes", "y":
    result.b = true
    result.err = nil
  of "false", "0", "f", "no", "n":
    result.b = false
    result.err = nil
  else:
    result.err = newException(GoError, "invalid boolean value")

proc ParseFloat*(s: GoString, bitSize: int): tuple[f: float64, err: GoError] =
  try:
    result.f = parseFloat($s)
    result.err = nil
  except:
    result.err = newException(GoError, "invalid float")

proc ParseInt*(s: GoString, base: int, bitSize: int): tuple[i: int64, err: GoError] =
  try:
    if base == 10:
      result.i = parseInt($s)
    elif base == 16:
      result.i = parseHexInt($s)
    else:
      result.err = newException(GoError, "unsupported base")
      return
    result.err = nil
  except:
    result.err = newException(GoError, "invalid integer")

proc FormatBool*(b: bool): GoString =
  newGoString(if b: "true" else: "false")

proc FormatFloat*(f: float64, fmt: char, prec: int, bitSize: int): GoString =
  newGoString($f)

proc FormatInt*(i: int64, base: int): GoString =
  if base == 10:
    newGoString($i)
  elif base == 16:
    newGoString(toHex(i))
  else:
    newGoString($i)

# errors.nim - Error handling
import ../runtime

proc New*(text: string): GoError =
  newException(GoError, text)

proc Is*(err: GoError, target: GoError): bool =
  if err.isNil or target.isNil:
    return false
  err.msg == target.msg

# os.nim - Operating system interface
import std/[os as nim_os, streams]
import ../runtime

type
  FileInfo* = object
    name: string
    size: int64
    mode: int
    modTime: int64
    isDir: bool

proc Getenv*(key: string): GoString =
  newGoString(nim_os.getEnv(key))

proc Setenv*(key, value: string): GoError =
  try:
    nim_os.putEnv(key, value)
    nil
  except:
    newException(GoError, "failed to set environment variable")

proc Unsetenv*(key: string): GoError =
  try:
    nim_os.delEnv(key)
    nil
  except:
    newException(GoError, "failed to unset environment variable")

proc Getwd*(): tuple[dir: string, err: GoError] =
  try:
    result.dir = nim_os.getCurrentDir()
    result.err = nil
  except:
    result.err = newException(GoError, "failed to get working directory")

proc Chdir*(dir: string): GoError =
  try:
    nim_os.setCurrentDir(dir)
    nil
  except:
    newException(GoError, "failed to change directory")

proc Mkdir*(name: string, perm: int): GoError =
  try:
    nim_os.createDir(name)
    nil
  except:
    newException(GoError, "failed to create directory")

proc MkdirAll*(path: string, perm: int): GoError =
  try:
    nim_os.createDir(path)
    nil
  except:
    newException(GoError, "failed to create directories")

proc Remove*(name: string): GoError =
  try:
    nim_os.removeFile(name)
    nil
  except:
    try:
      nim_os.removeDir(name)
      nil
    except:
      newException(GoError, "failed to remove file or directory")

proc RemoveAll*(path: string): GoError =
  try:
    nim_os.removeDir(path)
    nil
  except:
    newException(GoError, "failed to remove all")

proc Rename*(oldpath, newpath: string): GoError =
  try:
    nim_os.moveFile(oldpath, newpath)
    nil
  except:
    newException(GoError, "failed to rename")

proc Stat*(name: string): tuple[fi: FileInfo, err: GoError] =
  try:
    let info = nim_os.getFileInfo(name)
    result.fi = FileInfo(
      name: name,
      size: info.size,
      isDir: info.kind == pcDir
    )
    result.err = nil
  except:
    result.err = newException(GoError, "failed to stat file")

proc ReadFile*(filename: string): tuple[data: seq[byte], err: GoError] =
  try:
    let content = nim_os.readFile(filename)
    result.data = cast[seq[byte]](content)
    result.err = nil
  except:
    result.err = newException(GoError, "failed to read file")

proc WriteFile*(filename: string, data: seq[byte], perm: int): GoError =
  try:
    let content = cast[string](data)
    nim_os.writeFile(filename, content)
    nil
  except:
    newException(GoError, "failed to write file")
