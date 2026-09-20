pub opaque type Number {
  Number(negative: Bool, coefficient: List(Int), exponent10: Int)
}

pub opaque type NumberLimits {
  NumberLimits(
    max_token_bytes: Int,
    max_significand_digits: Int,
    max_abs_exponent: Int,
  )
}

pub type LimitsError {
  TokenLimitMustBePositive
  SignificandLimitMustBePositive
  ExponentLimitMustBeNonnegative
}

pub type NumberError {
  InvalidSyntax
  TokenTooLong
  TooManySignificandDigits
  ExponentOutOfRange
}

pub opaque type IntegerProjectionLimit {
  IntegerProjectionLimit(max_digits: Int)
}

pub type IntegerProjectionLimitError {
  IntegerDigitLimitMustBePositive
}

pub type IntegerProjectionError {
  FractionalInteger
  IntegerDigitLimitExceeded
}

pub type FloatProjectionError {
  FloatOverflow
  FloatUnderflow
  FloatInexact
  InvalidFloatCandidate
}

pub type FloatConstructionError {
  NonFiniteFloat
}

pub type NumberOrder {
  LessThan
  EqualTo
  GreaterThan
}

pub fn number_limits(
  max_token_bytes: Int,
  max_significand_digits: Int,
  max_abs_exponent: Int,
) -> Result(NumberLimits, LimitsError) {
  case max_token_bytes > 0, max_significand_digits > 0, max_abs_exponent >= 0 {
    False, _, _ -> Error(TokenLimitMustBePositive)
    _, False, _ -> Error(SignificandLimitMustBePositive)
    _, _, False -> Error(ExponentLimitMustBeNonnegative)
    True, True, True ->
      Ok(NumberLimits(max_token_bytes, max_significand_digits, max_abs_exponent))
  }
}

pub fn integer_projection_limit(
  max_digits: Int,
) -> Result(IntegerProjectionLimit, IntegerProjectionLimitError) {
  case max_digits > 0 {
    True -> Ok(IntegerProjectionLimit(max_digits))
    False -> Error(IntegerDigitLimitMustBePositive)
  }
}

// ---------------------------------------------------------------------------
// JavaScript target definitions (honest named todos, no throwing FFI)
// ---------------------------------------------------------------------------

@target(javascript)
pub fn parse_number(
  _limits: NumberLimits,
  _token: String,
) -> Result(Number, NumberError) {
  todo as "JavaScript exact number parser not implemented"
}

@target(javascript)
pub fn number_text(_number: Number) -> String {
  todo as "JavaScript canonical number text not implemented"
}

@target(javascript)
pub fn compare(_left: Number, _right: Number) -> NumberOrder {
  todo as "JavaScript number comparison not implemented"
}

@target(javascript)
pub fn to_int_exact(
  _number: Number,
  _limit: IntegerProjectionLimit,
) -> Result(Int, IntegerProjectionError) {
  todo as "JavaScript exact integer projection not implemented"
}

@target(javascript)
pub fn from_int(_value: Int) -> Number {
  todo as "JavaScript exact number from_int not implemented"
}

@target(javascript)
pub fn is_integer(_number: Number) -> Bool {
  todo as "JavaScript exact number is_integer not implemented"
}

@target(javascript)
pub fn from_float_exact(
  _value: Float,
) -> Result(Number, FloatConstructionError) {
  todo as "JavaScript exact number from_float_exact not implemented"
}

@target(javascript)
pub fn to_float_exact(_number: Number) -> Result(Float, FloatProjectionError) {
  todo as "JavaScript exact number to_float_exact not implemented"
}

// ---------------------------------------------------------------------------
// Erlang target implementation (complete exact-number kernel)
// ---------------------------------------------------------------------------

@target(erlang)
type FloatParts {
  FiniteParts(negative: Bool, significand: Int, exponent2: Int)
  NonFiniteParts
}

@target(erlang)
type FloatCandidate {
  CandidateValue(Float)
  CandidateOverflow
  CandidateInvalid
}

@target(erlang)
@external(erlang, "json_number_ffi", "byte_length")
fn native_byte_length(value: String) -> Int

@target(erlang)
@external(erlang, "json_number_ffi", "byte_codes")
fn native_byte_codes(value: String) -> List(Int)

@target(erlang)
@external(erlang, "json_number_ffi", "ascii_string")
fn native_ascii_string(bytes: List(Int)) -> String

@target(erlang)
@external(erlang, "json_number_ffi", "integer_to_string")
fn native_integer_to_string(value: Int) -> String

@target(erlang)
@external(erlang, "json_number_ffi", "integer_divide")
fn native_integer_divide(dividend: Int, divisor: Int) -> Int

@target(erlang)
@external(erlang, "json_number_ffi", "integer_remainder")
fn native_integer_remainder(dividend: Int, divisor: Int) -> Int

@target(erlang)
@external(erlang, "json_number_ffi", "float_parts")
fn native_float_parts(value: Float) -> FloatParts

@target(erlang)
@external(erlang, "json_number_ffi", "parse_float_candidate")
fn native_parse_float_candidate(value: String) -> FloatCandidate

@target(erlang)
type ExponentPart {
  NoExponent
  HasExponent(List(Int))
}

@target(erlang)
type DecimalPart {
  IntegerPart(List(Int))
  FractionalPart(List(Int), List(Int))
}

@target(erlang)
pub fn parse_number(
  limits: NumberLimits,
  token: String,
) -> Result(Number, NumberError) {
  let NumberLimits(max_token_bytes, max_significand_digits, max_abs_exponent) =
    limits
  case native_byte_length(token) > max_token_bytes {
    True -> Error(TokenTooLong)
    False ->
      parse_within_token_limit(max_significand_digits, max_abs_exponent, token)
  }
}

@target(erlang)
fn parse_within_token_limit(
  max_significand_digits: Int,
  max_abs_exponent: Int,
  token: String,
) -> Result(Number, NumberError) {
  let chars = native_byte_codes(token)
  let #(negative, unsigned_chars) = strip_negative_sign(chars)
  case split_exponent(unsigned_chars, []) {
    Error(Nil) -> Error(InvalidSyntax)
    Ok(#(mantissa, exponent_part)) ->
      case split_decimal(mantissa, []) {
        Error(Nil) -> Error(InvalidSyntax)
        Ok(decimal_part) ->
          case validated_significand(decimal_part) {
            Error(Nil) -> Error(InvalidSyntax)
            Ok(#(integer_digits, fraction_digits)) ->
              case valid_exponent_shape(exponent_part) {
                False -> Error(InvalidSyntax)
                True -> {
                  let raw_digit_count =
                    list_length(integer_digits) + list_length(fraction_digits)
                  case raw_digit_count > max_significand_digits {
                    True -> Error(TooManySignificandDigits)
                    False ->
                      normalize_parsed_number(
                        native_byte_length(token),
                        max_abs_exponent,
                        negative,
                        integer_digits,
                        fraction_digits,
                        exponent_part,
                      )
                  }
                }
              }
          }
      }
  }
}

@target(erlang)
fn normalize_parsed_number(
  token_length: Int,
  max_abs_exponent: Int,
  negative: Bool,
  integer_digits: List(Int),
  fraction_digits: List(Int),
  exponent_part: ExponentPart,
) -> Result(Number, NumberError) {
  let significant_digits =
    drop_leading_zeroes(append(integer_digits, fraction_digits))
  let exponent_headroom = max_abs_exponent + token_length
  case parse_written_exponent(exponent_part, exponent_headroom) {
    Error(error) -> Error(error)
    Ok(written_exponent) ->
      case significant_digits {
        [] -> Ok(Number(False, [48], 0))
        _ -> {
          let #(coefficient, removed_zeroes) =
            trim_trailing_zeroes(significant_digits, 0)
          let normalized_exponent =
            written_exponent - list_length(fraction_digits) + removed_zeroes
          case
            normalized_exponent > max_abs_exponent
            || normalized_exponent < -max_abs_exponent
          {
            True -> Error(ExponentOutOfRange)
            False -> Ok(Number(negative, coefficient, normalized_exponent))
          }
        }
      }
  }
}

@target(erlang)
pub fn number_text(number: Number) -> String {
  let Number(negative, coefficient, exponent10) = number
  case coefficient {
    [48] -> "0"
    _ -> {
      let scale = exponent10 + list_length(coefficient) - 1
      let mantissa = match_coefficient_digits(coefficient)
      let sign = case negative {
        True -> "-"
        False -> ""
      }
      case scale {
        0 -> sign <> mantissa
        _ -> sign <> mantissa <> "e" <> native_integer_to_string(scale)
      }
    }
  }
}

@target(erlang)
fn match_coefficient_digits(digits: List(Int)) -> String {
  case digits {
    [] -> ""
    [first] -> native_ascii_string([first])
    [first, ..rest] ->
      native_ascii_string([first]) <> "." <> native_ascii_string(rest)
  }
}

@target(erlang)
pub fn compare(left: Number, right: Number) -> NumberOrder {
  let Number(left_negative, left_digits, left_exponent) = left
  let Number(right_negative, right_digits, right_exponent) = right
  case left_digits == [48], right_digits == [48] {
    True, True -> EqualTo
    True, False ->
      case right_negative {
        True -> GreaterThan
        False -> LessThan
      }
    False, True ->
      case left_negative {
        True -> LessThan
        False -> GreaterThan
      }
    False, False ->
      case left_negative, right_negative {
        True, False -> LessThan
        False, True -> GreaterThan
        True, True ->
          reverse_order(compare_magnitudes(
            left_digits,
            left_exponent,
            right_digits,
            right_exponent,
          ))
        False, False ->
          compare_magnitudes(
            left_digits,
            left_exponent,
            right_digits,
            right_exponent,
          )
      }
  }
}

@target(erlang)
fn compare_magnitudes(
  left_digits: List(Int),
  left_exponent: Int,
  right_digits: List(Int),
  right_exponent: Int,
) -> NumberOrder {
  let left_scale = left_exponent + list_length(left_digits)
  let right_scale = right_exponent + list_length(right_digits)
  case compare_ints(left_scale, right_scale) {
    EqualTo -> compare_padded_digits(left_digits, right_digits)
    order -> order
  }
}

@target(erlang)
fn compare_padded_digits(left: List(Int), right: List(Int)) -> NumberOrder {
  case left, right {
    [], [] -> EqualTo
    [left_digit, ..left_rest], [right_digit, ..right_rest] ->
      case compare_ints(left_digit, right_digit) {
        EqualTo -> compare_padded_digits(left_rest, right_rest)
        order -> order
      }
    [], [right_digit, ..right_rest] ->
      case compare_ints(48, right_digit) {
        EqualTo -> compare_padded_digits([], right_rest)
        order -> order
      }
    [left_digit, ..left_rest], [] ->
      case compare_ints(left_digit, 48) {
        EqualTo -> compare_padded_digits(left_rest, [])
        order -> order
      }
  }
}

@target(erlang)
fn compare_ints(left: Int, right: Int) -> NumberOrder {
  case left {
    _ if left < right -> LessThan
    _ if left > right -> GreaterThan
    _ -> EqualTo
  }
}

@target(erlang)
fn reverse_order(order: NumberOrder) -> NumberOrder {
  case order {
    LessThan -> GreaterThan
    EqualTo -> EqualTo
    GreaterThan -> LessThan
  }
}

@target(erlang)
pub fn to_int_exact(
  number: Number,
  limit: IntegerProjectionLimit,
) -> Result(Int, IntegerProjectionError) {
  let IntegerProjectionLimit(max_digits) = limit
  let Number(negative, coefficient, exponent10) = number
  case coefficient == [48] {
    True -> Ok(0)
    False ->
      case exponent10 < 0 {
        True -> Error(FractionalInteger)
        False -> {
          let output_digits = list_length(coefficient) + exponent10
          case output_digits > max_digits {
            True -> Error(IntegerDigitLimitExceeded)
            False -> {
              let integer_coefficient = decimal_digits_to_int(coefficient)
              let integer_value = integer_coefficient * power(10, exponent10)
              case negative {
                True -> Ok(-integer_value)
                False -> Ok(integer_value)
              }
            }
          }
        }
      }
  }
}

@target(erlang)
pub fn is_integer(number: Number) -> Bool {
  let Number(_, coefficient, exponent10) = number
  coefficient == [48] || exponent10 >= 0
}

@target(erlang)
pub fn from_int(value: Int) -> Number {
  let text = native_integer_to_string(value)
  let chars = native_byte_codes(text)
  let #(negative, digits) = strip_negative_sign(chars)
  let normalized_digits = drop_leading_zeroes(digits)
  case normalized_digits {
    [] -> Number(False, [48], 0)
    _ -> {
      let #(coefficient, exponent10) =
        trim_trailing_zeroes(normalized_digits, 0)
      Number(negative, coefficient, exponent10)
    }
  }
}

@target(erlang)
pub fn from_float_exact(
  value: Float,
) -> Result(Number, FloatConstructionError) {
  case native_float_parts(value) {
    NonFiniteParts -> Error(NonFiniteFloat)
    FiniteParts(_, 0, _) -> Ok(Number(False, [48], 0))
    FiniteParts(negative, significand, exponent2) -> {
      let #(coefficient, exponent10) = case exponent2 {
        exponent2 if exponent2 >= 0 -> #(significand * power(2, exponent2), 0)
        exponent2 -> #(significand * power(5, -exponent2), exponent2)
      }
      let #(normalized_digits, normalized_exponent) =
        trim_trailing_zeroes(
          native_byte_codes(native_integer_to_string(coefficient)),
          exponent10,
        )
      Ok(Number(negative, normalized_digits, normalized_exponent))
    }
  }
}

@target(erlang)
pub fn to_float_exact(number: Number) -> Result(Float, FloatProjectionError) {
  let Number(negative, coefficient, exponent10) = number
  case coefficient == [48] {
    True -> Ok(0.0)
    False ->
      case native_parse_float_candidate(number_text(number)) {
        CandidateOverflow -> Error(FloatOverflow)
        CandidateInvalid -> Error(InvalidFloatCandidate)
        CandidateValue(candidate) ->
          case native_float_parts(candidate) {
            NonFiniteParts -> Error(FloatOverflow)
            FiniteParts(_, 0, _) -> Error(FloatUnderflow)
            FiniteParts(candidate_negative, significand, exponent2) ->
              case
                decimal_equals_binary_float(
                  negative,
                  coefficient,
                  exponent10,
                  candidate_negative,
                  significand,
                  exponent2,
                )
              {
                True -> Ok(candidate)
                False -> Error(FloatInexact)
              }
          }
      }
  }
}

@target(erlang)
fn decimal_equals_binary_float(
  decimal_negative: Bool,
  decimal_digits: List(Int),
  decimal_exponent: Int,
  binary_negative: Bool,
  binary_significand: Int,
  binary_exponent: Int,
) -> Bool {
  case decimal_negative == binary_negative {
    False -> False
    True -> {
      let #(normalized_significand, normalized_binary_exponent) =
        remove_binary_trailing_zeroes(binary_significand, binary_exponent)
      let decimal_significand = decimal_digits_to_int(decimal_digits)
      case decimal_exponent >= 0, normalized_binary_exponent >= 0 {
        True, True ->
          decimal_significand * power(10, decimal_exponent)
          == normalized_significand * power(2, normalized_binary_exponent)
        True, False -> False
        False, True -> False
        False, False -> {
          let decimal_denominator_exponent = -decimal_exponent
          let binary_denominator_exponent = -normalized_binary_exponent
          decimal_significand * power(2, binary_denominator_exponent)
          == normalized_significand
          * power(2, decimal_denominator_exponent)
          * power(5, decimal_denominator_exponent)
        }
      }
    }
  }
}

@target(erlang)
fn remove_binary_trailing_zeroes(
  significand: Int,
  exponent2: Int,
) -> #(Int, Int) {
  case native_integer_remainder(significand, 2) {
    0 ->
      remove_binary_trailing_zeroes(
        native_integer_divide(significand, 2),
        exponent2 + 1,
      )
    _ -> #(significand, exponent2)
  }
}

@target(erlang)
fn trim_trailing_zeroes(digits: List(Int), exponent: Int) -> #(List(Int), Int) {
  remove_trailing_zeroes_reversed(reverse_list(digits), exponent)
}

@target(erlang)
fn remove_trailing_zeroes_reversed(
  reversed_digits: List(Int),
  exponent: Int,
) -> #(List(Int), Int) {
  case reversed_digits {
    [48, ..rest] -> remove_trailing_zeroes_reversed(rest, exponent + 1)
    _ -> #(reverse_list(reversed_digits), exponent)
  }
}

@target(erlang)
fn decimal_digits_to_int(digits: List(Int)) -> Int {
  decimal_digits_to_int_acc(digits, 0)
}

@target(erlang)
fn decimal_digits_to_int_acc(digits: List(Int), current: Int) -> Int {
  case digits {
    [] -> current
    [digit, ..rest] ->
      decimal_digits_to_int_acc(rest, current * 10 + digit_value(digit))
  }
}

@target(erlang)
fn digit_value(digit: Int) -> Int {
  case digit {
    48 -> 0
    49 -> 1
    50 -> 2
    51 -> 3
    52 -> 4
    53 -> 5
    54 -> 6
    55 -> 7
    56 -> 8
    57 -> 9
    _ -> 0
  }
}

@target(erlang)
fn power(base: Int, exponent: Int) -> Int {
  case exponent <= 0 {
    True -> 1
    False ->
      case native_integer_remainder(exponent, 2) {
        0 -> {
          let half = power(base, native_integer_divide(exponent, 2))
          half * half
        }
        _ -> base * power(base, exponent - 1)
      }
  }
}

@target(erlang)
fn strip_negative_sign(chars: List(Int)) -> #(Bool, List(Int)) {
  case chars {
    [45, ..rest] -> #(True, rest)
    _ -> #(False, chars)
  }
}

@target(erlang)
fn split_exponent(
  chars: List(Int),
  before_reversed: List(Int),
) -> Result(#(List(Int), ExponentPart), Nil) {
  case chars {
    [] -> Ok(#(reverse_list(before_reversed), NoExponent))
    [character, ..rest] if character == 101 || character == 69 ->
      case contains_exponent_marker(rest) {
        True -> Error(Nil)
        False -> Ok(#(reverse_list(before_reversed), HasExponent(rest)))
      }
    [character, ..rest] -> split_exponent(rest, [character, ..before_reversed])
  }
}

@target(erlang)
fn contains_exponent_marker(chars: List(Int)) -> Bool {
  case chars {
    [] -> False
    [character, ..rest] ->
      character == 101 || character == 69 || contains_exponent_marker(rest)
  }
}

@target(erlang)
fn split_decimal(
  chars: List(Int),
  before_reversed: List(Int),
) -> Result(DecimalPart, Nil) {
  case chars {
    [] -> Ok(IntegerPart(reverse_list(before_reversed)))
    [46, ..rest] ->
      case contains_decimal_point(rest) {
        True -> Error(Nil)
        False -> Ok(FractionalPart(reverse_list(before_reversed), rest))
      }
    [character, ..rest] -> split_decimal(rest, [character, ..before_reversed])
  }
}

@target(erlang)
fn contains_decimal_point(chars: List(Int)) -> Bool {
  case chars {
    [] -> False
    [46, ..] -> True
    [_, ..rest] -> contains_decimal_point(rest)
  }
}

@target(erlang)
fn validated_significand(
  decimal_part: DecimalPart,
) -> Result(#(List(Int), List(Int)), Nil) {
  case decimal_part {
    IntegerPart(integer_digits) ->
      case valid_integer_digits(integer_digits) {
        True -> Ok(#(integer_digits, []))
        False -> Error(Nil)
      }
    FractionalPart(integer_digits, fraction_digits) ->
      case
        valid_integer_digits(integer_digits),
        fraction_digits != [] && all_digits(fraction_digits)
      {
        True, True -> Ok(#(integer_digits, fraction_digits))
        _, _ -> Error(Nil)
      }
  }
}

@target(erlang)
fn valid_integer_digits(chars: List(Int)) -> Bool {
  case chars {
    [48] -> True
    [first, ..rest] -> nonzero_digit(first) && all_digits(rest)
    [] -> False
  }
}

@target(erlang)
fn nonzero_digit(digit: Int) -> Bool {
  case digit {
    49 -> True
    50 -> True
    51 -> True
    52 -> True
    53 -> True
    54 -> True
    55 -> True
    56 -> True
    57 -> True
    _ -> False
  }
}

@target(erlang)
fn all_digits(chars: List(Int)) -> Bool {
  case chars {
    [] -> True
    [digit, ..rest] -> is_digit(digit) && all_digits(rest)
  }
}

@target(erlang)
fn is_digit(digit: Int) -> Bool {
  nonzero_digit(digit) || digit == 48
}

@target(erlang)
fn parse_written_exponent(
  exponent_part: ExponentPart,
  max_raw_magnitude: Int,
) -> Result(Int, NumberError) {
  case exponent_part {
    NoExponent -> Ok(0)
    HasExponent(raw) -> {
      let #(negative, digits) = strip_exponent_sign(raw)
      case digits {
        [] -> Error(InvalidSyntax)
        _ ->
          case all_digits(digits) {
            False -> Error(InvalidSyntax)
            True ->
              case parse_bounded_digits(digits, max_raw_magnitude, 0) {
                Error(Nil) -> Error(ExponentOutOfRange)
                Ok(magnitude) ->
                  case negative {
                    True -> Ok(-magnitude)
                    False -> Ok(magnitude)
                  }
              }
          }
      }
    }
  }
}

@target(erlang)
fn valid_exponent_shape(exponent_part: ExponentPart) -> Bool {
  case exponent_part {
    NoExponent -> True
    HasExponent(raw) -> {
      let #(_, digits) = strip_exponent_sign(raw)
      digits != [] && all_digits(digits)
    }
  }
}

@target(erlang)
fn strip_exponent_sign(chars: List(Int)) -> #(Bool, List(Int)) {
  case chars {
    [45, ..rest] -> #(True, rest)
    [43, ..rest] -> #(False, rest)
    _ -> #(False, chars)
  }
}

@target(erlang)
fn parse_bounded_digits(
  digits: List(Int),
  max_value: Int,
  current: Int,
) -> Result(Int, Nil) {
  case digits {
    [] -> Ok(current)
    [digit, ..rest] -> {
      let next = current * 10 + digit_value(digit)
      case next > max_value {
        True -> Error(Nil)
        False -> parse_bounded_digits(rest, max_value, next)
      }
    }
  }
}

@target(erlang)
fn drop_leading_zeroes(chars: List(Int)) -> List(Int) {
  case chars {
    [48, ..rest] -> drop_leading_zeroes(rest)
    _ -> chars
  }
}

@target(erlang)
fn reverse_list(items: List(a)) -> List(a) {
  reverse_acc(items, [])
}

@target(erlang)
fn reverse_acc(items: List(a), reversed: List(a)) -> List(a) {
  case items {
    [] -> reversed
    [item, ..rest] -> reverse_acc(rest, [item, ..reversed])
  }
}

@target(erlang)
fn list_length(items: List(a)) -> Int {
  list_length_acc(items, 0)
}

@target(erlang)
fn list_length_acc(items: List(a), length: Int) -> Int {
  case items {
    [] -> length
    [_, ..rest] -> list_length_acc(rest, length + 1)
  }
}

@target(erlang)
fn append(left: List(a), right: List(a)) -> List(a) {
  case left {
    [] -> right
    [item, ..rest] -> [item, ..append(rest, right)]
  }
}
