## Go math package implementation in Nim
import std/[math as nimmath]
import ../runtime

# Mathematical constants
const
  E* = 2.71828182845904523536028747135266249775724709369995957496696763
  Pi* = 3.14159265358979323846264338327950288419716939937510582097494459
  Phi* = 1.61803398874989484820458683436563811772030917980576286213544862
  Sqrt2* = 1.41421356237309504880168872420969807856967187537694807317667974
  SqrtE* = 1.64872127070012814684865078781416357165377610071014801157507931
  SqrtPi* = 1.77245385090551602729816748334114518279754945612238712821380779
  SqrtPhi* = 1.27201964951406896425242246173749149171560804184009624861664038
  Ln2* = 0.693147180559945309417232121458176568075500134360255254120680009
  Log2E* = 1.0 / Ln2
  Ln10* = 2.30258509299404568401799145468436420760110148862877297603332790
  Log10E* = 1.0 / Ln10
  
  MaxFloat64* = 1.7976931348623157e+308
  SmallestNonzeroFloat64* = 4.9406564584124654e-324
  MaxFloat32* = 3.40282346638528859811704183484516925440e+38
  SmallestNonzeroFloat32* = 1.401298464324817070923729583289916131280e-45
  
  MaxInt* = int.high
  MinInt* = int.low
  MaxInt64* = int64.high
  MinInt64* = int64.low
  MaxUint64* = uint64.high

# Basic functions
proc Abs*(x: float64): float64 =
  nimmath.abs(x)

proc Ceil*(x: float64): float64 =
  nimmath.ceil(x)

proc Floor*(x: float64): float64 =
  nimmath.floor(x)

proc Round*(x: float64): float64 =
  nimmath.round(x)

proc Trunc*(x: float64): float64 =
  nimmath.trunc(x)

proc Max*(x, y: float64): float64 =
  nimmath.max(x, y)

proc Min*(x, y: float64): float64 =
  nimmath.min(x, y)

proc Mod*(x, y: float64): float64 =
  nimmath.`mod`(x, y)

proc Remainder*(x, y: float64): float64 =
  x - y * Round(x / y)

# Power and logarithm functions
proc Pow*(x, y: float64): float64 =
  nimmath.pow(x, y)

proc Sqrt*(x: float64): float64 =
  nimmath.sqrt(x)

proc Cbrt*(x: float64): float64 =
  nimmath.cbrt(x)

proc Exp*(x: float64): float64 =
  nimmath.exp(x)

proc Exp2*(x: float64): float64 =
  nimmath.pow(2.0, x)

proc Expm1*(x: float64): float64 =
  nimmath.exp(x) - 1.0

proc Log*(x: float64): float64 =
  nimmath.ln(x)

proc Log10*(x: float64): float64 =
  nimmath.log10(x)

proc Log2*(x: float64): float64 =
  nimmath.log2(x)

proc Log1p*(x: float64): float64 =
  nimmath.ln(1.0 + x)

proc Hypot*(x, y: float64): float64 =
  nimmath.hypot(x, y)

# Trigonometric functions
proc Sin*(x: float64): float64 =
  nimmath.sin(x)

proc Cos*(x: float64): float64 =
  nimmath.cos(x)

proc Tan*(x: float64): float64 =
  nimmath.tan(x)

proc Asin*(x: float64): float64 =
  nimmath.arcsin(x)

proc Acos*(x: float64): float64 =
  nimmath.arccos(x)

proc Atan*(x: float64): float64 =
  nimmath.arctan(x)

proc Atan2*(y, x: float64): float64 =
  nimmath.arctan2(y, x)

# Hyperbolic functions
proc Sinh*(x: float64): float64 =
  nimmath.sinh(x)

proc Cosh*(x: float64): float64 =
  nimmath.cosh(x)

proc Tanh*(x: float64): float64 =
  nimmath.tanh(x)

proc Asinh*(x: float64): float64 =
  nimmath.arcsinh(x)

proc Acosh*(x: float64): float64 =
  nimmath.arccosh(x)

proc Atanh*(x: float64): float64 =
  nimmath.arctanh(x)

# Special functions
proc Gamma*(x: float64): float64 =
  nimmath.gamma(x)

proc Lgamma*(x: float64): tuple[lgamma: float64, sign: int] =
  result.lgamma = nimmath.lgamma(x)
  result.sign = if x < 0: -1 else: 1

proc Erf*(x: float64): float64 =
  nimmath.erf(x)

proc Erfc*(x: float64): float64 =
  nimmath.erfc(x)

# Bit manipulation
proc Copysign*(x, y: float64): float64 =
  nimmath.copySign(x, y)

proc Signbit*(x: float64): bool =
  x < 0.0

proc Dim*(x, y: float64): float64 =
  max(x - y, 0.0)

# Float utilities
proc IsNaN*(x: float64): bool =
  nimmath.isNaN(x)

proc IsInf*(x: float64, sign: int): bool =
  if sign > 0:
    x == Inf
  elif sign < 0:
    x == -Inf
  else:
    x == Inf or x == -Inf

proc Inf*(sign: int): float64 =
  if sign >= 0:
    nimmath.Inf
  else:
    -nimmath.Inf

proc NaN*(): float64 =
  nimmath.NaN

proc Float64bits*(f: float64): uint64 =
  cast[uint64](f)

proc Float64frombits*(b: uint64): float64 =
  cast[float64](b)

proc Float32bits*(f: float32): uint32 =
  cast[uint32](f)

proc Float32frombits*(b: uint32): float32 =
  cast[float32](b)

# Decomposition
proc Frexp*(f: float64): tuple[frac: float64, exp: int] =
  nimmath.frexp(f)

proc Ldexp*(frac: float64, exp: int): float64 =
  nimmath.ldexp(frac, exp)

proc Modf*(f: float64): tuple[intpart: float64, fracpart: float64] =
  result.intpart = nimmath.trunc(f)
  result.fracpart = f - result.intpart

# Angle conversion
proc Degrees*(radians: float64): float64 =
  radians * 180.0 / Pi

proc Radians*(degrees: float64): float64 =
  degrees * Pi / 180.0

# Integer functions
proc Abs*(x: int): int =
  if x < 0: -x else: x

proc Abs*(x: int64): int64 =
  if x < 0: -x else: x

proc Min*(x, y: int): int =
  if x < y: x else: y

proc Max*(x, y: int): int =
  if x > y: x else: y

# Random-related (moved to math/rand, but basic impl here)
proc Nextafter*(x, y: float64): float64 =
  if x == y:
    return x
  
  var bits = Float64bits(x)
  if (y > x and x >= 0) or (y < x and x < 0):
    bits.inc
  else:
    bits.dec
  
  Float64frombits(bits)

# Comparison with tolerance
proc ApproxEqual*(a, b: float64, tolerance: float64 = 1e-9): bool =
  abs(a - b) < tolerance

# Clamp value between min and max
proc Clamp*(x, minVal, maxVal: float64): float64 =
  max(minVal, min(maxVal, x))

proc Clamp*(x, minVal, maxVal: int): int =
  max(minVal, min(maxVal, x))

# Lerp - linear interpolation
proc Lerp*(a, b, t: float64): float64 =
  a + (b - a) * t
