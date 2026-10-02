//// Mapping, explicit limits, integer projection and the internal 1.x
//// dynamic lookups.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/option.{None}
import gleeunit/should
import json/blueprint/codec.{DecodeError, EncodeError, Field}
import json/blueprint/contract
import json/blueprint/internal/dynamic as legacy_dynamic
import json/blueprint/number
import json/blueprint/value

@external(erlang, "number_test_ffi", "float_from_hex")
@external(javascript, "./number_test_ffi.mjs", "float_from_hex")
fn float_from_hex(hex: String) -> Float

@target(javascript)
@external(javascript, "./api_control_test_ffi.mjs", "map_with_undefined")
pub fn map_with_undefined() -> Dynamic

@target(javascript)
@external(javascript, "./api_control_test_ffi.mjs", "weak_map_pair")
pub fn weak_map_pair() -> #(Dynamic, Dynamic)

@target(javascript)
@external(javascript, "./api_control_test_ffi.mjs", "null_proto_object")
pub fn null_proto_object() -> Dynamic

pub fn fallible_mapping_preserves_schema_and_errors_test() {
  let mapped =
    codec.try_map(
      codec.string(),
      decode: fn(text) {
        case text {
          "yes" -> Ok(True)
          _ -> Error("unknown flag")
        }
      },
      encode: fn(flag) {
        case flag {
          True -> Ok("yes")
          False -> Error("false forbidden")
        }
      },
      placeholder: False,
    )
  codec.schema(mapped) |> should.equal(Ok(codec.StringSchema))
  codec.decode(mapped, value.String("yes")) |> should.equal(Ok(True))
  codec.decode(mapped, value.String("no"))
  |> should.equal(Error(DecodeError([], codec.Custom("unknown flag"))))
  codec.decode(mapped, value.Bool(True))
  |> should.equal(Error(DecodeError([], codec.ExpectedString)))
  codec.encode(mapped, False)
  |> should.equal(Error(EncodeError([], codec.Custom("false forbidden"))))
  let nested = {
    use flag <- codec.field("flag", mapped, fn(flag: Bool) { flag })
    codec.success(flag)
  }
  codec.decode(nested, value.Object([#("flag", value.String("no"))]))
  |> should.equal(
    Error(DecodeError([Field("flag")], codec.Custom("unknown flag"))),
  )
  codec.encode(nested, False)
  |> should.equal(
    Error(EncodeError([Field("flag")], codec.Custom("false forbidden"))),
  )
}

pub fn mapped_json_uses_strict_admission_test() {
  let mapped = codec.map(codec.int(), decode: fn(n) { n }, encode: fn(n) { n })
  codec.decode_json(mapped, "1.0000000000000001")
  |> should.equal(Error(DecodeError([], codec.ExpectedInt)))
}

pub fn explicit_limits_and_exact_float_defaults_test() {
  let assert Ok(smallest) =
    number.from_float_exact(float_from_hex("0000000000000001"))
  codec.decode_json(codec.number(), number.to_string(smallest))
  |> should.equal(Ok(smallest))
  let assert Ok(largest) =
    number.from_float_exact(float_from_hex("7fefffffffffffff"))
  codec.decode_json(codec.number(), number.to_string(largest))
  |> should.equal(Ok(largest))

  let assert Ok(num) = number.from_float_exact(0.1)
  let tight_numbers =
    number.limits(
      max_token_bytes: 8,
      max_significant_digits: 4,
      max_exponent: 10,
    )
  let tight =
    value.default_limits()
    |> value.with_max_bytes(8)
    |> value.with_max_depth(2)
    |> value.with_number_limits(tight_numbers)
  let assert Error(error) =
    codec.decode_json_with_limits(codec.number(), number.to_string(num), tight)
  codec.is_limit_exceeded(error) |> should.be_true
  let assert Ok(quarter) = number.parse("0.25", number.default_limits())
  codec.decode_json_with_limits(codec.number(), "0.25", tight)
  |> should.equal(Ok(quarter))

  let short = value.default_limits() |> value.with_max_bytes(4)
  let assert Error(DecodeError(
    [],
    codec.InvalidJson(value.ParseError(_, value.ByteLimitExceeded(4))),
  )) =
    codec.decode_json_with_limits(codec.number(), number.to_string(num), short)

  // A bound below 1 rejects every input.
  let closed = value.default_limits() |> value.with_max_bytes(0)
  let assert Error(error) =
    codec.decode_json_with_limits(codec.number(), "1", closed)
  codec.is_limit_exceeded(error) |> should.be_true
}

pub fn bounded_integer_projection_matches_document_test() {
  let large = 999_999_999_999_999
  let bounded = codec.integer_between(-large, large)
  let assert Ok(raw) = codec.encode(bounded, -large)
  codec.decode(bounded, raw) |> should.equal(Ok(-large))
  let assert Ok(runtime_contract) = contract.from_codec(bounded)
  contract.validate(runtime_contract, raw) |> should.be_ok
  let assert Ok(description) = codec.schema(bounded)
  let assert Ok(loaded) = contract.load(codec.schema_document(description))
  contract.validate(loaded, raw) |> should.be_ok
  contract.same_schema(runtime_contract, loaded) |> should.be_true
}

@target(erlang)
pub fn bounded_25_digit_integer_projection_matches_document_test() {
  let large = 1_234_567_890_123_456_789_012_345
  let bounded = codec.integer_between(0, large)
  let assert Ok(raw) = codec.encode(bounded, large)
  codec.decode(bounded, raw) |> should.equal(Ok(large))
  // `int()` stops at 24 digits; the bounds widen the projection.
  codec.decode(codec.int(), raw)
  |> should.equal(Error(DecodeError([], codec.ExpectedInt)))
  let assert Ok(runtime_contract) = contract.from_codec(bounded)
  contract.validate(runtime_contract, raw) |> should.be_ok
  let assert Ok(description) = codec.schema(bounded)
  let assert Ok(loaded) = contract.load(codec.schema_document(description))
  contract.validate(loaded, raw) |> should.be_ok
  contract.same_schema(runtime_contract, loaded) |> should.be_true
}

@target(javascript)
pub fn legacy_map_lookup_keeps_missing_and_present_undefined_test() {
  let dictionary = dict.from_list([#("name", "Ada")])
  legacy_dynamic.field("name", legacy_dynamic.string)(legacy_dynamic.from(
    dictionary,
  ))
  |> should.equal(Ok("Ada"))
  legacy_dynamic.optional_field("absent", legacy_dynamic.dynamic)(
    legacy_dynamic.from(dictionary),
  )
  |> should.equal(Ok(None))

  let raw = map_with_undefined()
  case legacy_dynamic.optional_field("present", legacy_dynamic.dynamic)(raw) {
    Ok(option.Some(value)) ->
      legacy_dynamic.classify(value) |> should.equal("Nil")
    _ -> should.be_true(False)
  }
  legacy_dynamic.optional_field("absent", legacy_dynamic.dynamic)(raw)
  |> should.equal(Ok(None))

  let #(weak_map, key) = weak_map_pair()
  case legacy_dynamic.optional_field(key, legacy_dynamic.dynamic)(weak_map) {
    Ok(option.Some(value)) ->
      legacy_dynamic.classify(value) |> should.equal("Nil")
    _ -> should.be_true(False)
  }

  let object = null_proto_object()
  case
    legacy_dynamic.optional_field("present", legacy_dynamic.dynamic)(object)
  {
    Ok(option.Some(value)) ->
      legacy_dynamic.classify(value) |> should.equal("Nil")
    _ -> should.be_true(False)
  }
  legacy_dynamic.optional_field("absent", legacy_dynamic.dynamic)(object)
  |> should.equal(Ok(None))
}

@target(erlang)
pub fn legacy_map_lookup_keeps_missing_test() {
  let dictionary = dict.from_list([#("name", "Ada")])
  let raw: Dynamic = legacy_dynamic.from(dictionary)
  legacy_dynamic.field("name", legacy_dynamic.string)(raw)
  |> should.equal(Ok("Ada"))
  legacy_dynamic.optional_field("absent", legacy_dynamic.dynamic)(raw)
  |> should.equal(Ok(None))
}
