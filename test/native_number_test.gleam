import gleam/list
import gleam/string
import gleeunit/should
import json/blueprint/internal/native
import json/blueprint/number

pub fn unrestricted_token_construction_retains_explicit_parse_bounds_test() {
  let token = string.repeat("1", 1100)
  number.parse(token, number.default_limits())
  |> should.equal(Error(number.TokenTooLong))
  let assert Ok(exact) = number.from_json_token(token)
  number.from_json_token(number.to_string(exact)) |> should.equal(Ok(exact))
  number.parse("1e1201", number.default_limits())
  |> should.equal(Error(number.ExponentOutOfRange))
  let assert Ok(large) = number.from_json_token("1e1201")
  number.to_float(large) |> should.equal(Error(number.FloatOverflow))
}

pub fn unrestricted_zero_avoids_unnecessary_exponent_conversion_test() {
  let assert Ok(zero) = number.from_int(0)
  number.from_json_token("-0.000e" <> string.repeat("9", 1100))
  |> should.equal(Ok(zero))
  number.from_json_token("0e-" <> string.repeat("9", 1100))
  |> should.equal(Ok(zero))
}

pub fn unrestricted_constructor_still_checks_json_number_grammar_test() {
  list.each(["", "+1", "01", "1.", ".1", "1e", "1e+", "NaN", "0x10"], fn(token) {
    number.from_json_token(token) |> should.equal(Error(number.InvalidSyntax))
  })
}

@target(erlang)
pub fn huge_exponent_remains_exact_on_erlang_test() {
  list.each(["1e9007199254740993", "1e-9007199254740993"], fn(token) {
    let assert Ok(exact) = number.from_json_token(token)
    number.to_string(exact) |> should.equal(token)
    let assert Ok(raw) = native.parse(token, 1024)
    native.number(raw) |> should.equal(Ok(exact))
    native.int(raw) |> should.equal(Error(native.Unrepresentable))
  })
}

@target(javascript)
pub fn unsafe_exponent_remains_a_javascript_representation_failure_test() {
  number.from_json_token("1e9007199254740993")
  |> should.equal(Error(number.ExponentOutOfRange))
  native.supported() |> should.be_true
  native.parse("1e9007199254740993", 1024)
  |> should.equal(Error(native.NumberRepresentation))
}

@target(erlang)
pub fn native_number_projection_has_no_global_token_or_digit_limit_test() {
  list.each(
    [string.repeat("1", 1100), "0." <> string.repeat("1", 1100)],
    fn(token) {
      let assert Ok(expected) = number.from_json_token(token)
      let assert Ok(raw) = native.parse(token, 2048)
      native.kind(raw) |> should.equal(native.Number)
      native.number(raw) |> should.equal(Ok(expected))
    },
  )
}

@target(erlang)
pub fn native_integer_projection_preserves_fraction_and_size_checks_test() {
  list.each(["1.00000000000000001", "-1.00000000000000001", "1e24"], fn(token) {
    let assert Ok(raw) = native.parse(token, 1024)
    native.int(raw) |> should.equal(Error(native.Unrepresentable))
  })
  list.each(["1.0", "1e0", "1e" <> string.repeat("0", 1100)], fn(token) {
    let assert Ok(raw) = native.parse(token, 2048)
    native.int(raw) |> should.equal(Ok(1))
  })
  let assert Ok(raw) = native.parse("999999999999999999999999", 1024)
  native.int(raw) |> should.equal(Ok(999_999_999_999_999_999_999_999))
  let assert Ok(raw) = native.parse("1000000000000000000000000", 1024)
  native.int(raw) |> should.equal(Error(native.Unrepresentable))
}

@target(erlang)
pub fn native_float_projection_matches_exact_kernel_zero_and_underflow_test() {
  list.each(
    [
      "-0.0",
      "-0.000e99999",
      "-1e-400",
      "-0.0001e-400",
      "1.7976931348623157e308",
      "4.9406564584124654e-324",
    ],
    fn(token) {
      let assert Ok(exact) = number.from_json_token(token)
      let assert Ok(raw) = native.parse(token, 1024)
      native.float(raw)
      |> should.equal(number.to_float(exact) |> map_float_error)
    },
  )
  let assert Ok(raw) = native.parse("1e400", 1024)
  native.float(raw) |> should.equal(Error(native.Unrepresentable))
}

@target(erlang)
fn map_float_error(
  result: Result(Float, number.FloatProjectionError),
) -> Result(Float, native.NumericError) {
  case result {
    Ok(x) -> Ok(x)
    Error(_) -> Error(native.Unrepresentable)
  }
}

@target(erlang)
pub fn native_duplicate_admission_survives_float_callbacks_test() {
  list.each(
    ["{\"a\":0.1,\"a\":2}", "[0.1,{\"a\":1,\"\\u0061\":2}]"],
    fn(source) {
      native.parse(source, 1024)
      |> should.equal(Error(native.DuplicateKey("a")))
    },
  )
  let assert Error(native.Syntax(_)) =
    native.parse("[{\"a\":1,\"a\":2},?]", 1024)
  native.parse("null", 3) |> should.equal(Error(native.ByteLimitExceeded))
}
