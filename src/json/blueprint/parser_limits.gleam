//// Bounds for the strict JSON parser: input bytes, nesting depth and number
//// size.
////
//// Start from `default()` (1 MiB, depth 64, numbers of up to 1,024 bytes,
//// 800 significant digits and exponent 1,200) and change one bound with
//// `with_max_bytes`, `with_max_depth` or `with_number_limits`. Pass the result
//// to `codec.decode_json_with_limits` or to the `json/blueprint/parser`
//// functions. `parser.ParserLimits` is an alias of `ParserLimits`.

import json/blueprint/number.{type NumberLimits}

/// Validated bounds for strict JSON admission.
pub opaque type ParserLimits {
  ParserLimits(max_bytes: Int, max_depth: Int, number_limits: NumberLimits)
}

pub type LimitsError {
  MaxBytesMustBePositive
  MaxDepthMustBePositive
}

pub fn new(
  max_bytes: Int,
  max_depth: Int,
  number_limits: NumberLimits,
) -> Result(ParserLimits, LimitsError) {
  case max_bytes > 0, max_depth > 0 {
    False, _ -> Error(MaxBytesMustBePositive)
    _, False -> Error(MaxDepthMustBePositive)
    True, True -> Ok(ParserLimits(max_bytes, max_depth, number_limits))
  }
}

/// The default limits: 1 MiB (1,048,576 bytes) of JSON text, nesting depth
/// 64, and number tokens of at most 1,024 bytes, 800 significant digits and
/// a decimal exponent magnitude of 1,200.
///
/// The number bounds admit the exact decimal expansion of every finite
/// binary64 value, including the smallest subnormal. Change the byte or
/// depth bound with `with_max_bytes` or `with_max_depth`. The 1.x
/// `json/blueprint.decode` and `codec.decode_json_native` apply the same byte
/// bound before parsing.
///
/// Parsed values take more memory than their text. An array of one-digit
/// integers, the densest input, peaks at about 70 bytes of process heap per
/// input byte on Erlang/OTP 28 (69 MB for 1 MiB) and about 170 on Node.js.
pub fn default() -> ParserLimits {
  let assert Ok(numbers) = number.number_limits(1024, 800, 1200)
  let assert Ok(limits) = new(default_max_bytes, default_max_depth, numbers)
  limits
}

const default_max_bytes = 1_048_576

const default_max_depth = 64

/// Change only the JSON text byte bound, preserving depth and number policy.
pub fn with_max_bytes(
  limits: ParserLimits,
  max_bytes: Int,
) -> Result(ParserLimits, LimitsError) {
  new(max_bytes, limits.max_depth, limits.number_limits)
}

/// Change only the nesting bound, preserving byte and number policy.
pub fn with_max_depth(
  limits: ParserLimits,
  max_depth: Int,
) -> Result(ParserLimits, LimitsError) {
  new(limits.max_bytes, max_depth, limits.number_limits)
}

/// Replace the independently validated number policy.
pub fn with_number_limits(
  limits: ParserLimits,
  number_limits: NumberLimits,
) -> ParserLimits {
  ParserLimits(limits.max_bytes, limits.max_depth, number_limits)
}

pub fn max_bytes(limits: ParserLimits) -> Int {
  limits.max_bytes
}

pub fn max_depth(limits: ParserLimits) -> Int {
  limits.max_depth
}

pub fn number_limits(limits: ParserLimits) -> NumberLimits {
  limits.number_limits
}
