import gleam/bit_array
import gleam/list
import gleam/option.{None}
import gleeunit/should
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value

pub fn native_admission_sees_overwritten_and_unused_members_test() {
  let never =
    codec.custom(
      encode: Ok,
      decode: fn(_) { panic as "admission must precede callbacks" },
      schema: None,
      placeholder: value.Null,
    )
  list.each(
    [
      "{\"x\":1,\"\\u0078\":2}",
      "{\"nested\":{\"x\":1,\"\\u0078\":2}}",
      "{\"😀\":1,\"\\ud83d\\ude00\":2}",
      "{\"__proto__\":0,\"\\u005f_proto__\":1}",
      "{\"a\\nb\":1,\"a\\u000ab\":2}",
      "{\"x\":\"\\ud800\",\"x\":1}",
      "{\"ignored\":\"\\udc00\"}",
      "{\"x\":1,\"x\":2} garbage",
    ],
    fn(source) {
      value.parse(source, value.default_limits()) |> should.be_error
      codec.decode_json(never, source) |> should.be_error
    },
  )
}

pub fn native_names_have_per_object_scope_and_no_prototype_special_cases_test() {
  list.each(
    [
      "{\"a\":{\"x\":1},\"b\":{\"x\":2}}",
      "{\"__proto__\":1,\"constructor\":2}",
      "{\"é\":1,\"é\":2}",
      "[\"[{}]\",\"\\\"\",null,true,false]",
    ],
    fn(source) { value.parse(source, value.default_limits()) |> should.be_ok },
  )
  let c = {
    use item <- codec.field("__proto__", codec.int(), get: fn(x) { x })
    codec.success(item)
  }
  codec.decode_json(c, "{\"__proto__\":7}") |> should.equal(Ok(7))
}

pub fn native_numeric_source_survives_rounding_test() {
  list.each(["1.00000000000000001", "-1.00000000000000001"], fn(source) {
    codec.decode_json(codec.int(), source) |> should.be_error
    let assert Ok(expected) = number.from_json_token(source)
    codec.decode_json(codec.number(), source) |> should.equal(Ok(expected))
    codec.decode_json(codec.float(), source) |> should.be_ok
  })
  let custom =
    codec.custom(encode: Ok, decode: Ok, schema: None, placeholder: value.Null)
  let assert Ok(expected) = number.from_json_token("0.10000000000000001")
  codec.decode_json(custom, "0.10000000000000001")
  |> should.equal(Ok(value.Number(expected)))
}

pub fn byte_and_text_entry_points_both_reject_a_leading_bom_test() {
  let source = "\u{feff}null"
  value.parse(source, value.default_limits()) |> should.be_error
  value.parse_bits(bit_array.from_string(source), value.default_limits())
  |> should.equal(
    Error(value.ParseError(value.Location(0, 0, 0), value.NativeSyntax)),
  )
  value.parse_bits(
    bit_array.from_string(source),
    value.default_limits() |> value.with_max_bytes(1),
  )
  |> should.equal(
    Error(value.ParseError(value.Location(0, 1, 1), value.ByteLimitExceeded(1))),
  )
}

@target(javascript)
@external(javascript, "./hybrid_parser_test_ffi.mjs", "callback_range_error_escapes")
fn callback_range_error_escapes() -> Bool

@target(javascript)
pub fn application_range_errors_are_not_parser_capacity_failures_test() {
  callback_range_error_escapes() |> should.be_true
}
