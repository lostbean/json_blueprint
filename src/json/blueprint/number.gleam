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
  UnsupportedNativeInteger
}

pub type FloatProjectionError {
  FloatOverflow
  FloatUnderflow
  FloatInexact
  InvalidFloatCandidate
}

pub type IntegerConstructionError {
  NonFiniteInteger
  NonIntegerValue
  UnsafeNativeInteger
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

pub type FloatCandidate {
  CandidateValue(Float)
  CandidateOverflow
  CandidateInvalid
}

@external(erlang, "json_number_ffi", "byte_length")
@external(javascript, "../../json_number_ffi.mjs", "byte_length")
fn native_byte_length(value: String) -> Int

@external(erlang, "json_number_ffi", "byte_codes")
@external(javascript, "../../json_number_ffi.mjs", "byte_codes")
fn native_byte_codes(value: String) -> List(Int)

@external(erlang, "json_number_ffi", "ascii_string")
@external(javascript, "../../json_number_ffi.mjs", "ascii_string")
fn native_ascii_string(bytes: List(Int)) -> String

@external(erlang, "json_number_ffi", "integer_to_string")
@external(javascript, "../../json_number_ffi.mjs", "integer_to_string")
fn native_integer_to_string(value: Int) -> String

@external(erlang, "json_number_ffi", "validate_native_int")
@external(javascript, "../../json_number_ffi.mjs", "validate_native_int")
fn native_validate_native_int(
  value: Int,
  on_non_finite: IntegerConstructionError,
  on_fractional: IntegerConstructionError,
  on_unsupported: IntegerConstructionError,
) -> Result(String, IntegerConstructionError)

@external(erlang, "json_number_ffi", "float_parts")
@external(javascript, "../../json_number_ffi.mjs", "float_parts")
fn native_float_parts(value: Float) -> Result(#(Bool, Int, Int), Nil)

@external(erlang, "json_number_ffi", "parse_float_candidate")
@external(javascript, "../../json_number_ffi.mjs", "parse_float_candidate")
fn native_parse_float_candidate(
  value: String,
  on_value: fn(Float) -> FloatCandidate,
  on_overflow: FloatCandidate,
  on_invalid: FloatCandidate,
) -> FloatCandidate

@external(erlang, "json_number_ffi", "float_to_decimal")
@external(javascript, "../../json_number_ffi.mjs", "float_to_decimal")
fn native_float_to_decimal(
  significand: Int,
  exponent2: Int,
) -> #(List(Int), Int)

@external(erlang, "json_number_ffi", "decimal_equals_binary")
@external(javascript, "../../json_number_ffi.mjs", "decimal_equals_binary")
fn native_decimal_equals_binary(
  decimal_digits: List(Int),
  decimal_exponent: Int,
  binary_significand: Int,
  binary_exponent: Int,
) -> Bool

@external(erlang, "json_number_ffi", "project_native_int")
@external(javascript, "../../json_number_ffi.mjs", "project_native_int")
fn native_project_native_int(
  negative: Bool,
  digits: List(Int),
  exponent10: Int,
) -> Result(Int, Nil)

type ExponentPart {
  NoExponent
  HasExponent(List(Int))
}

type DecimalPart {
  IntegerPart(List(Int))
  FractionalPart(List(Int), List(Int))
}

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

fn match_coefficient_digits(digits: List(Int)) -> String {
  case digits {
    [] -> ""
    [first] -> native_ascii_string([first])
    [first, ..rest] ->
      native_ascii_string([first]) <> "." <> native_ascii_string(rest)
  }
}

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

fn compare_ints(left: Int, right: Int) -> NumberOrder {
  case left {
    _ if left < right -> LessThan
    _ if left > right -> GreaterThan
    _ -> EqualTo
  }
}

fn reverse_order(order: NumberOrder) -> NumberOrder {
  case order {
    LessThan -> GreaterThan
    EqualTo -> EqualTo
    GreaterThan -> LessThan
  }
}

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
            False ->
              case
                native_project_native_int(negative, coefficient, exponent10)
              {
                Ok(value) -> Ok(value)
                Error(Nil) -> Error(UnsupportedNativeInteger)
              }
          }
        }
      }
  }
}

pub fn is_integer(number: Number) -> Bool {
  let Number(_, coefficient, exponent10) = number
  coefficient == [48] || exponent10 >= 0
}

pub fn from_int(value: Int) -> Result(Number, IntegerConstructionError) {
  case
    native_validate_native_int(
      value,
      NonFiniteInteger,
      NonIntegerValue,
      UnsafeNativeInteger,
    )
  {
    Error(err) -> Error(err)
    Ok(text) -> {
      let chars = native_byte_codes(text)
      let #(negative, digits) = strip_negative_sign(chars)
      let normalized_digits = drop_leading_zeroes(digits)
      case normalized_digits {
        [] -> Ok(Number(False, [48], 0))
        _ -> {
          let #(coefficient, exponent10) =
            trim_trailing_zeroes(normalized_digits, 0)
          Ok(Number(negative, coefficient, exponent10))
        }
      }
    }
  }
}

pub fn from_float_exact(
  value: Float,
) -> Result(Number, FloatConstructionError) {
  case native_float_parts(value) {
    Error(Nil) -> Error(NonFiniteFloat)
    Ok(#(_, 0, _)) -> Ok(Number(False, [48], 0))
    Ok(#(negative, significand, exponent2)) -> {
      let #(digits, exponent10) =
        native_float_to_decimal(significand, exponent2)
      let #(coefficient, normalized_exponent) =
        trim_trailing_zeroes(digits, exponent10)
      Ok(Number(negative, coefficient, normalized_exponent))
    }
  }
}

pub fn to_float_exact(number: Number) -> Result(Float, FloatProjectionError) {
  let Number(negative, coefficient, exponent10) = number
  case coefficient == [48] {
    True -> Ok(0.0)
    False ->
      case
        native_parse_float_candidate(
          number_text(number),
          CandidateValue,
          CandidateOverflow,
          CandidateInvalid,
        )
      {
        CandidateOverflow -> Error(FloatOverflow)
        CandidateInvalid -> Error(InvalidFloatCandidate)
        CandidateValue(candidate) ->
          case native_float_parts(candidate) {
            Error(Nil) -> Error(FloatOverflow)
            Ok(#(_, 0, _)) -> Error(FloatUnderflow)
            Ok(#(candidate_negative, significand, exponent2)) ->
              case
                candidate_negative == negative
                && native_decimal_equals_binary(
                  coefficient,
                  exponent10,
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

fn trim_trailing_zeroes(digits: List(Int), exponent: Int) -> #(List(Int), Int) {
  remove_trailing_zeroes_reversed(reverse_list(digits), exponent)
}

fn remove_trailing_zeroes_reversed(
  reversed_digits: List(Int),
  exponent: Int,
) -> #(List(Int), Int) {
  case reversed_digits {
    [48, ..rest] -> remove_trailing_zeroes_reversed(rest, exponent + 1)
    _ -> #(reverse_list(reversed_digits), exponent)
  }
}

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

fn strip_negative_sign(chars: List(Int)) -> #(Bool, List(Int)) {
  case chars {
    [45, ..rest] -> #(True, rest)
    _ -> #(False, chars)
  }
}

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

fn contains_exponent_marker(chars: List(Int)) -> Bool {
  case chars {
    [] -> False
    [character, ..rest] ->
      character == 101 || character == 69 || contains_exponent_marker(rest)
  }
}

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

fn contains_decimal_point(chars: List(Int)) -> Bool {
  case chars {
    [] -> False
    [46, ..] -> True
    [_, ..rest] -> contains_decimal_point(rest)
  }
}

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

fn valid_integer_digits(chars: List(Int)) -> Bool {
  case chars {
    [48] -> True
    [first, ..rest] -> nonzero_digit(first) && all_digits(rest)
    [] -> False
  }
}

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

fn all_digits(chars: List(Int)) -> Bool {
  case chars {
    [] -> True
    [digit, ..rest] -> is_digit(digit) && all_digits(rest)
  }
}

fn is_digit(digit: Int) -> Bool {
  nonzero_digit(digit) || digit == 48
}

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

fn valid_exponent_shape(exponent_part: ExponentPart) -> Bool {
  case exponent_part {
    NoExponent -> True
    HasExponent(raw) -> {
      let #(_, digits) = strip_exponent_sign(raw)
      digits != [] && all_digits(digits)
    }
  }
}

fn strip_exponent_sign(chars: List(Int)) -> #(Bool, List(Int)) {
  case chars {
    [45, ..rest] -> #(True, rest)
    [43, ..rest] -> #(False, rest)
    _ -> #(False, chars)
  }
}

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

fn drop_leading_zeroes(chars: List(Int)) -> List(Int) {
  case chars {
    [48, ..rest] -> drop_leading_zeroes(rest)
    _ -> chars
  }
}

fn reverse_list(items: List(a)) -> List(a) {
  reverse_acc(items, [])
}

fn reverse_acc(items: List(a), reversed: List(a)) -> List(a) {
  case items {
    [] -> reversed
    [item, ..rest] -> reverse_acc(rest, [item, ..reversed])
  }
}

fn list_length(items: List(a)) -> Int {
  list_length_acc(items, 0)
}

fn list_length_acc(items: List(a), length: Int) -> Int {
  case items {
    [] -> length
    [_, ..rest] -> list_length_acc(rest, length + 1)
  }
}

fn append(left: List(a), right: List(a)) -> List(a) {
  case left {
    [] -> right
    [item, ..rest] -> [item, ..append(rest, right)]
  }
}
