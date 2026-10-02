//// Exact JSON numbers and their checked conversions to `Int` and `Float`.
////
//// A `Number` keeps the decimal value of a JSON number token exactly, with no
//// rounding, so `1.10` equals `1.1` and `1e2` equals `100`. `parse` reads a
//// token within `Limits` on token bytes, significant digits and exponent
//// size; `default_limits()` is 1,024 bytes, 800 digits and exponent 1,200,
//// which admits the exact decimal expansion of every finite binary64 value.
////
//// `to_int` and `to_float_exact` return a native value only when it is
//// exactly equal; `to_float` rounds to the nearest binary64. `from_int`,
//// `from_float` (the shortest decimal that reads back as the same float) and
//// `from_float_exact` (the float's exact binary expansion) convert back. On
//// JavaScript, integers outside the safe range (±9,007,199,254,740,991) are
//// refused instead of rounded.
////
//// `value.Number` holds this type, and `codec.number()` decodes it.
////
//// ```gleam
//// import gleam/order
//// import json/blueprint/number
////
//// pub fn example() {
////   let assert Ok(price) = number.parse("19.90", number.default_limits())
////   let assert Ok(same) = number.parse("1.99e1", number.default_limits())
////   let assert order.Eq = number.compare(price, same)
////   let assert Ok(19.9) = number.to_float(price)
////   number.to_string(price)
//// }
//// ```

import gleam/float
import gleam/order.{type Order}

/// An exact JSON number.
///
/// The representation is canonical, so two `Number` values are equal exactly
/// when they denote the same mathematical value.
pub opaque type Number {
  /// An integer whose magnitude has at most `small_integer_digits` digits,
  /// stored as a native integer. Such values are exact on every target.
  SmallInteger(value: Int)
  /// Every other value: the sign, the coefficient's ASCII digits without
  /// leading or trailing zeros, and the power of ten that scales them.
  Decimal(negative: Bool, digits: String, exponent10: Int)
}

/// Integers up to 15 digits are exact both as BEAM small integers and as
/// JavaScript doubles.
const small_integer_digits = 15

/// Bounds for `parse`: token bytes, significant digits and the magnitude of
/// the decimal exponent.
pub opaque type Limits {
  Limits(
    max_token_bytes: Int,
    max_significand_digits: Int,
    max_abs_exponent: Int,
  )
}

/// Why `parse` refused a token. `InvalidSyntax` is not a JSON number; the other
/// variants exceed a bound of `Limits`.
pub type NumberError {
  InvalidSyntax
  TokenTooLong
  TooManySignificandDigits
  ExponentOutOfRange
}

/// Why `to_int` refused a number.
pub type IntegerProjectionError {
  FractionalInteger
  IntegerDigitLimitExceeded
  UnsupportedNativeInteger
}

/// Why `to_float` or `to_float_exact` refused a number.
pub type FloatProjectionError {
  FloatOverflow
  FloatUnderflow
  FloatInexact
  InvalidFloatCandidate
}

/// Why `from_int` refused an `Int`. Only JavaScript produces these: a
/// non-finite or fractional number, or one outside the safe integer range.
pub type IntegerConstructionError {
  NonFiniteInteger
  NonIntegerValue
  UnsafeNativeInteger
}

/// Why `from_float` or `from_float_exact` refused a `Float`: on JavaScript,
/// an infinity or NaN.
pub type FloatConstructionError {
  NonFiniteFloat
}

/// Build number limits. A token longer than `max_token_bytes`, with more than
/// `max_significant_digits` digits as written, or whose normalized decimal
/// exponent exceeds `max_exponent` in magnitude is refused. A token bound
/// or digit bound below 1 refuses every token; a negative exponent bound
/// refuses every number except zero.
pub fn limits(
  max_token_bytes max_token_bytes: Int,
  max_significant_digits max_significant_digits: Int,
  max_exponent max_exponent: Int,
) -> Limits {
  Limits(max_token_bytes, max_significant_digits, max_exponent)
}

/// 1,024 token bytes, 800 significant digits and exponent magnitude 1,200.
/// These admit the exact decimal expansion of every finite binary64 value,
/// including the smallest subnormal.
pub fn default_limits() -> Limits {
  Limits(1024, 800, 1200)
}

type FloatCandidate {
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

/// Parse a JSON number token, such as `-12.5e3`, exactly. Leading or trailing
/// whitespace, a leading `+`, leading zeros and a bare `.` are invalid, as in
/// JSON.
pub fn parse(token: String, limits: Limits) -> Result(Number, NumberError) {
  let Limits(max_token_bytes, max_significand_digits, max_abs_exponent) = limits
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
        [] -> Ok(zero)
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
            False -> Ok(make(negative, coefficient, normalized_exponent))
          }
        }
      }
  }
}

/// The number as JSON number text: a plain integer when its normalized
/// exponent is zero, otherwise one leading digit and an exponent, such as
/// `1.25e1` for 12.5 or `1e3` for 1000.
pub fn to_string(number: Number) -> String {
  let #(negative, coefficient, exponent10) = parts(number)
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

/// Compare two numbers by mathematical value.
pub fn compare(left: Number, right: Number) -> Order {
  case left, right {
    SmallInteger(left), SmallInteger(right) -> compare_ints(left, right)
    _, _ -> compare_parts(parts(left), parts(right))
  }
}

fn compare_parts(
  left: #(Bool, List(Int), Int),
  right: #(Bool, List(Int), Int),
) -> Order {
  let #(left_negative, left_digits, left_exponent) = left
  let #(right_negative, right_digits, right_exponent) = right
  case left_digits == [48], right_digits == [48] {
    True, True -> order.Eq
    True, False ->
      case right_negative {
        True -> order.Gt
        False -> order.Lt
      }
    False, True ->
      case left_negative {
        True -> order.Lt
        False -> order.Gt
      }
    False, False ->
      case left_negative, right_negative {
        True, False -> order.Lt
        False, True -> order.Gt
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
) -> Order {
  let left_scale = left_exponent + list_length(left_digits)
  let right_scale = right_exponent + list_length(right_digits)
  case compare_ints(left_scale, right_scale) {
    order.Eq -> compare_padded_digits(left_digits, right_digits)
    order -> order
  }
}

fn compare_padded_digits(left: List(Int), right: List(Int)) -> Order {
  case left, right {
    [], [] -> order.Eq
    [left_digit, ..left_rest], [right_digit, ..right_rest] ->
      case compare_ints(left_digit, right_digit) {
        order.Eq -> compare_padded_digits(left_rest, right_rest)
        order -> order
      }
    [], [right_digit, ..right_rest] ->
      case compare_ints(48, right_digit) {
        order.Eq -> compare_padded_digits([], right_rest)
        order -> order
      }
    [left_digit, ..left_rest], [] ->
      case compare_ints(left_digit, 48) {
        order.Eq -> compare_padded_digits(left_rest, [])
        order -> order
      }
  }
}

fn compare_ints(left: Int, right: Int) -> Order {
  case left {
    _ if left < right -> order.Lt
    _ if left > right -> order.Gt
    _ -> order.Eq
  }
}

fn reverse_order(order: Order) -> Order {
  case order {
    order.Lt -> order.Gt
    order.Eq -> order.Eq
    order.Gt -> order.Lt
  }
}

/// The number as an `Int` when it is an integer of at most `max_digits`
/// decimal digits. `max_digits` bounds the work and memory of the conversion;
/// on JavaScript the integer must also be within the safe range.
pub fn to_int(
  number: Number,
  max_digits: Int,
) -> Result(Int, IntegerProjectionError) {
  case number {
    SmallInteger(value) ->
      case decimal_digit_count(absolute(value), 1) > max_digits {
        True -> Error(IntegerDigitLimitExceeded)
        False -> Ok(value)
      }
    Decimal(..) -> decimal_to_int_exact(parts(number), max_digits)
  }
}

fn decimal_to_int_exact(
  parts: #(Bool, List(Int), Int),
  max_digits: Int,
) -> Result(Int, IntegerProjectionError) {
  let #(negative, coefficient, exponent10) = parts
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

/// Whether the number has no fractional part.
pub fn is_integer(number: Number) -> Bool {
  case number {
    SmallInteger(_) -> True
    Decimal(exponent10:, ..) -> exponent10 >= 0
  }
}

/// The exact number of an `Int`. Fails only on JavaScript, for a value that is
/// not a safe integer.
pub fn from_int(value: Int) -> Result(Number, IntegerConstructionError) {
  case value > -small_integer_bound && value < small_integer_bound {
    // Fewer than 16 digits: exact on every target. On JavaScript, a fraction
    // fails the remainder test and takes the checked path below.
    True if value % 1 == 0 -> Ok(SmallInteger(value))
    _ -> from_checked_int(value)
  }
}

const small_integer_bound = 1_000_000_000_000_000

fn from_checked_int(value: Int) -> Result(Number, IntegerConstructionError) {
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
        [] -> Ok(zero)
        _ -> {
          let #(coefficient, exponent10) =
            trim_trailing_zeroes(normalized_digits, 0)
          Ok(make(negative, coefficient, exponent10))
        }
      }
    }
  }
}

/// The shortest decimal that reads back as the same float, such as `0.1` for
/// `0.1`. This is the number a JSON reader sees in the float's usual printed
/// form.
pub fn from_float(value: Float) -> Result(Number, FloatConstructionError) {
  case native_float_parts(value) {
    Error(Nil) -> Error(NonFiniteFloat)
    Ok(_) -> {
      let assert Ok(parsed) = parse(float.to_string(value), float_text_limits)
      Ok(parsed)
    }
  }
}

/// Enough for the shortest form of any finite binary64 value.
const float_text_limits = Limits(64, 64, 400)

/// The exact decimal value of the float's binary representation, such as
/// `0.1000000000000000055511151231257827021181583404541015625` for `0.1`.
pub fn from_float_exact(
  value: Float,
) -> Result(Number, FloatConstructionError) {
  case native_float_parts(value) {
    Error(Nil) -> Error(NonFiniteFloat)
    Ok(#(_, 0, _)) -> Ok(zero)
    Ok(#(negative, significand, exponent2)) -> {
      let #(digits, exponent10) =
        native_float_to_decimal(significand, exponent2)
      let #(coefficient, normalized_exponent) =
        trim_trailing_zeroes(digits, exponent10)
      Ok(make(negative, coefficient, normalized_exponent))
    }
  }
}

/// The nearest binary64 float. Fails with `FloatOverflow` when the magnitude
/// is beyond the largest finite float; a magnitude below the smallest
/// subnormal rounds to zero.
pub fn to_float(number: Number) -> Result(Float, FloatProjectionError) {
  case is_zero(number) {
    True -> Ok(0.0)
    False ->
      case
        native_parse_float_candidate(
          to_string(number),
          CandidateValue,
          CandidateOverflow,
          CandidateInvalid,
        )
      {
        CandidateValue(candidate) -> Ok(candidate)
        CandidateOverflow -> Error(FloatOverflow)
        CandidateInvalid -> Error(InvalidFloatCandidate)
      }
  }
}

fn is_zero(number: Number) -> Bool {
  case number {
    SmallInteger(0) -> True
    _ -> False
  }
}

/// The float exactly equal to the number. Fails when the nearest float
/// differs (`FloatInexact`), or the number is beyond the float range.
pub fn to_float_exact(number: Number) -> Result(Float, FloatProjectionError) {
  let #(negative, coefficient, exponent10) = parts(number)
  case coefficient == [48] {
    True -> Ok(0.0)
    False ->
      case
        native_parse_float_candidate(
          to_string(number),
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

const zero = SmallInteger(0)

/// Build the canonical representation from a sign, coefficient digit codes
/// without leading or trailing zeros (or `[48]` for zero), and a power of ten.
fn make(negative: Bool, coefficient: List(Int), exponent10: Int) -> Number {
  case coefficient {
    [48] -> zero
    _ ->
      case
        exponent10 >= 0
        && list_length(coefficient) + exponent10 <= small_integer_digits
      {
        True -> {
          let magnitude = scale_by_ten(digits_value(coefficient, 0), exponent10)
          case negative {
            True -> SmallInteger(0 - magnitude)
            False -> SmallInteger(magnitude)
          }
        }
        False -> Decimal(negative, native_ascii_string(coefficient), exponent10)
      }
  }
}

/// Expand a number into its sign, coefficient digit codes and power of ten.
fn parts(number: Number) -> #(Bool, List(Int), Int) {
  case number {
    SmallInteger(0) -> #(False, [48], 0)
    SmallInteger(value) -> {
      let digits = native_byte_codes(native_integer_to_string(absolute(value)))
      let #(coefficient, exponent10) = trim_trailing_zeroes(digits, 0)
      #(value < 0, coefficient, exponent10)
    }
    Decimal(negative, digits, exponent10) -> #(
      negative,
      native_byte_codes(digits),
      exponent10,
    )
  }
}

fn digits_value(digits: List(Int), accumulator: Int) -> Int {
  case digits {
    [] -> accumulator
    [digit, ..rest] -> digits_value(rest, accumulator * 10 + digit_value(digit))
  }
}

fn scale_by_ten(value: Int, exponent10: Int) -> Int {
  case exponent10 <= 0 {
    True -> value
    False -> scale_by_ten(value * 10, exponent10 - 1)
  }
}

fn absolute(value: Int) -> Int {
  case value < 0 {
    True -> 0 - value
    False -> value
  }
}

fn decimal_digit_count(magnitude: Int, count: Int) -> Int {
  case magnitude < 10 {
    True -> count
    False -> decimal_digit_count(magnitude / 10, count + 1)
  }
}
