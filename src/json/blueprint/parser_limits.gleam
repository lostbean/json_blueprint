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

/// Admit exact decimal expansions of every finite binary64 value, including
/// the smallest subnormal, while keeping all resource bounds finite.
pub fn default() -> ParserLimits {
  let assert Ok(numbers) = number.number_limits(1024, 800, 1200)
  let assert Ok(limits) = new(10_485_760, 128, numbers)
  limits
}

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
