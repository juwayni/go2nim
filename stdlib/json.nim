## Go encoding/json package implementation in Nim
import std/[json, tables, strutils]
import ../runtime

type
  RawMessage* = seq[byte]
  
  Marshaler* = concept x
    x.MarshalJSON() is tuple[data: seq[byte], err: GoError]
  
  Unmarshaler* = concept x
    x.UnmarshalJSON(seq[byte]) is GoError

# Marshal converts Go value to JSON
proc Marshal*(v: auto): tuple[data: seq[byte], err: GoError] =
  try:
    when v is GoString:
      let j = %($v)
      result.data = cast[seq[byte]]($j)
    elif v is GoSlice:
      var jarr = newJArray()
      for item in v:
        when item is int or item is GoInt:
          jarr.add(%item)
        elif item is string or item is GoString:
          jarr.add(%($item))
        elif item is bool:
          jarr.add(%item)
        elif item is float or item is float64:
          jarr.add(%item)
        else:
          jarr.add(newJNull())
      result.data = cast[seq[byte]]($jarr)
    elif v is GoMap:
      var jobj = newJObject()
      for k, val in v:
        when val is int or val is GoInt:
          jobj[$k] = %val
        elif val is string or val is GoString:
          jobj[$k] = %($val)
        elif val is bool:
          jobj[$k] = %val
        elif val is float or val is float64:
          jobj[$k] = %val
        else:
          jobj[$k] = newJNull()
      result.data = cast[seq[byte]]($jobj)
    elif v is int or v is GoInt:
      result.data = cast[seq[byte]]($v)
    elif v is float or v is float64:
      result.data = cast[seq[byte]]($v)
    elif v is bool:
      result.data = cast[seq[byte]](if v: "true" else: "false")
    elif v is string:
      result.data = cast[seq[byte]]("\"" & v & "\"")
    else:
      result.data = cast[seq[byte]]("null")
    
    result.err = nil
  except:
    result.err = newException(GoError, getCurrentExceptionMsg())

# Unmarshal parses JSON into Go value
proc Unmarshal*(data: seq[byte], v: var auto): GoError =
  try:
    let jsonStr = cast[string](data)
    let node = parseJson(jsonStr)
    
    when v is GoString:
      if node.kind == JString:
        v = newGoString(node.getStr())
    elif v is int or v is GoInt:
      if node.kind == JInt:
        v = node.getInt()
    elif v is float or v is float64:
      if node.kind == JFloat:
        v = node.getFloat()
      elif node.kind == JInt:
        v = float(node.getInt())
    elif v is bool:
      if node.kind == JBool:
        v = node.getBool()
    elif v is GoSlice:
      if node.kind == JArray:
        v = newGoSlice[type(v.data[0])]()
        for item in node:
          when type(v.data[0]) is int or type(v.data[0]) is GoInt:
            v = v.append(item.getInt())
          elif type(v.data[0]) is string or type(v.data[0]) is GoString:
            v = v.append(newGoString(item.getStr()))
          elif type(v.data[0]) is float or type(v.data[0]) is float64:
            v = v.append(item.getFloat())
          elif type(v.data[0]) is bool:
            v = v.append(item.getBool())
    elif v is GoMap:
      if node.kind == JObject:
        for key, val in node:
          when type(v.data.values.toSeq[0]) is int or type(v.data.values.toSeq[0]) is GoInt:
            v[key] = val.getInt()
          elif type(v.data.values.toSeq[0]) is string or type(v.data.values.toSeq[0]) is GoString:
            v[key] = newGoString(val.getStr())
          elif type(v.data.values.toSeq[0]) is float or type(v.data.values.toSeq[0]) is float64:
            v[key] = val.getFloat()
          elif type(v.data.values.toSeq[0]) is bool:
            v[key] = val.getBool()
    
    nil
  except:
    newException(GoError, getCurrentExceptionMsg())

# MarshalIndent produces indented JSON
proc MarshalIndent*(v: auto, prefix: string, indent: string): tuple[data: seq[byte], err: GoError] =
  try:
    let (data, err) = Marshal(v)
    if err != nil:
      return (data, err)
    
    let jsonStr = cast[string](data)
    let node = parseJson(jsonStr)
    let pretty = node.pretty()
    
    result.data = cast[seq[byte]](pretty)
    result.err = nil
  except:
    result.err = newException(GoError, getCurrentExceptionMsg())

# Valid checks if data is valid JSON
proc Valid*(data: seq[byte]): bool =
  try:
    let jsonStr = cast[string](data)
    discard parseJson(jsonStr)
    true
  except:
    false

# Compact removes whitespace from JSON
proc Compact*(dst: var seq[byte], src: seq[byte]): GoError =
  try:
    let jsonStr = cast[string](src)
    let node = parseJson(jsonStr)
    dst = cast[seq[byte]]($node)
    nil
  except:
    newException(GoError, getCurrentExceptionMsg())

# Indent adds indentation to JSON
proc Indent*(dst: var seq[byte], src: seq[byte], prefix: string, indent: string): GoError =
  try:
    let jsonStr = cast[string](src)
    let node = parseJson(jsonStr)
    dst = cast[seq[byte]](node.pretty())
    nil
  except:
    newException(GoError, getCurrentExceptionMsg())

# HTMLEscape escapes special HTML characters
proc HTMLEscape*(dst: var seq[byte], src: seq[byte]) =
  let s = cast[string](src)
  var result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  dst = cast[seq[byte]](result)
