//// Emits the retained 62-case Erlang numeric corpus through the public API.

import gleam/int
import gleam/io
import gleam/list
import gleam/order
import gleam/string
import json/blueprint/number
import json/blueprint/value.{type Value, Bool, Null, Object, String}

@external(erlang, "number_test_ffi", "float_from_hex")
@external(javascript, "./number_test_ffi.mjs", "float_from_hex")
fn float_from_hex(hex: String) -> Float

@external(erlang, "number_test_ffi", "float_to_bits_hex")
@external(javascript, "./number_test_ffi.mjs", "float_to_bits_hex")
fn float_to_bits_hex(value: Float) -> String

pub fn main() {
  emit([
    #("kind", String("limits")),
    #("parse_max_token_bytes", String("64")),
    #("parse_max_significand_digits", String("32")),
    #("parse_max_abs_exponent", String("1200")),
    #("int_projection_max_digits", String("24")),
  ])
  list.each(parse_tokens(), parse_row)
  list.each(comparison_pairs(), fn(pair) {
    let comparison = case number.compare(parse(pair.0), parse(pair.1)) {
      order.Lt -> "less"
      order.Eq -> "equal"
      order.Gt -> "greater"
    }
    emit([
      #("kind", String("compare")),
      #("left", String(pair.0)),
      #("right", String(pair.1)),
      #("order", String(comparison)),
    ])
  })
  list.each(
    [
      "0000000000000000",
      "8000000000000000",
      "3fe0000000000000",
      "3fb999999999999a",
      "0000000000000001",
      "7fefffffffffffff",
      "bfb999999999999a",
    ],
    fn(bits) {
      let assert Ok(parsed) = number.from_float_exact(float_from_hex(bits))
      let assert Ok(roundtrip) = number.to_float_exact(parsed)
      emit([
        #("kind", String("from_float")),
        #("input_hex", String(bits)),
        #("status", String("accepted")),
        #("canonical", String(number.to_string(parsed))),
        #("roundtrip_bits_hex", String(float_to_bits_hex(roundtrip))),
      ])
    },
  )
  list.each(["0", "12", "120", "-120", "9007199254740993"], fn(text) {
    let assert Ok(native) = int.parse(text)
    let assert Ok(parsed) = number.from_int(native)
    let #(status, result) = integer_projection(parsed)
    emit([
      #("kind", String("from_int")),
      #("input", String(text)),
      #("canonical", String(number.to_string(parsed))),
      #("int_status", String(status)),
      #("int_value", result),
    ])
  })
}

fn emit(fields: List(#(String, Value))) {
  Object(fields) |> value.to_string |> io.println
}

fn parse(token: String) -> number.Number {
  let assert Ok(parsed) = number.parse(token, number.limits(64, 32, 1200))
  parsed
}

fn integer_projection(parsed: number.Number) -> #(String, Value) {
  case number.to_int(parsed, 24) {
    Ok(native) -> #("exact", String(int.to_string(native)))
    Error(number.FractionalInteger) -> #("fractional", Null)
    Error(number.IntegerDigitLimitExceeded) -> #("digit_limit", Null)
    Error(number.UnsupportedNativeInteger) -> #(
      "unsupported_native_integer",
      Null,
    )
  }
}

fn float_projection(parsed: number.Number) -> #(String, Value, Value) {
  case number.to_float_exact(parsed) {
    Ok(native) -> {
      let assert Ok(exact) = number.from_float_exact(native)
      #(
        "exact",
        String(float_to_bits_hex(native)),
        String(number.to_string(exact)),
      )
    }
    Error(number.FloatOverflow) -> #("overflow", Null, Null)
    Error(number.FloatUnderflow) -> #("underflow", Null, Null)
    Error(number.FloatInexact) -> #("inexact", Null, Null)
    Error(number.InvalidFloatCandidate) -> #("invalid_candidate", Null, Null)
  }
}

fn parse_row(token: String) {
  let fields = case number.parse(token, number.limits(64, 32, 1200)) {
    Error(error) -> {
      let status = case error {
        number.InvalidSyntax -> "invalid_syntax"
        number.TokenTooLong -> "token_too_long"
        number.TooManySignificandDigits -> "significand_too_long"
        number.ExponentOutOfRange -> "exponent_out_of_range"
      }
      [
        #("status", String(status)),
        #("canonical", Null),
        #("integer", Null),
        #("int_status", String("not_applicable")),
        #("int_value", Null),
        #("float_status", String("not_applicable")),
        #("float_bits_hex", Null),
        #("float_exact_decimal", Null),
      ]
    }
    Ok(parsed) -> {
      let #(integer_status, integer_value) = integer_projection(parsed)
      let #(float_status, bits, decimal) = float_projection(parsed)
      [
        #("status", String("accepted")),
        #("canonical", String(number.to_string(parsed))),
        #("integer", Bool(number.is_integer(parsed))),
        #("int_status", String(integer_status)),
        #("int_value", integer_value),
        #("float_status", String(float_status)),
        #("float_bits_hex", bits),
        #("float_exact_decimal", decimal),
      ]
    }
  }
  emit([#("kind", String("parse")), #("token", String(token)), ..fields])
}

fn parse_tokens() -> List(String) {
  [
    "+1",
    "01",
    "1.",
    ".1",
    "1e",
    "1e+",
    "--1",
    "1.2.3",
    string.repeat("9", 33) <> "e+",
    string.repeat("9", 33) <> "e1",
    "-0",
    "0",
    "1",
    "1.0",
    "10e-1",
    "100e-2",
    "123.45",
    "1.2300e2",
    "123.45e1201",
    "100e-1202",
    "0.5",
    "0.1",
    "0.125",
    "9007199254740992",
    "9007199254740993",
    "123456789012345678901234567890",
    "1e400",
    "1e-400",
    "1e-324",
    "1.7976931348623157e308",
    "1.7976931348623159e308",
    "-0.5",
    "-123.45",
    "١",
    " 1",
    "1e1201",
    "0e1266",
    string.repeat("9", 33),
    string.repeat("9", 65),
  ]
}

fn comparison_pairs() -> List(#(String, String)) {
  [
    #("1", "1.0"),
    #("-0", "0"),
    #("9007199254740993", "9007199254740992"),
    #("-2", "-10"),
    #("-1.01", "-1.001"),
    #("-1", "1"),
    #("1", "0.99"),
    #("1.20", "12e-1"),
    #("1.01", "1.001"),
    #("1e3", "9.99e2"),
    #("0.001", "0.01"),
  ]
}
