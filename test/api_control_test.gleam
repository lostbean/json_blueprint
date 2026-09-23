import generated/option_codec
import generated/order_codec
import generated_source_normalize
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/document
import json/blueprint/dynamic as legacy_dynamic
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/parser_limits
import json/blueprint/runtime
import json/blueprint/value
import option_fixtures

@external(erlang, "number_test_ffi", "float_from_hex")
@external(javascript, "./number_test_ffi.mjs", "float_from_hex")
fn float_from_hex(hex: String) -> Float

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

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
    codec.try_imap(
      codec.string(),
      fn(text) {
        case text {
          "yes" -> Ok(True)
          _ ->
            Error(codec.CannotDecode(codec.CustomDecodeReason("unknown flag")))
        }
      },
      fn(flag) {
        case flag {
          True -> Ok("yes")
          False ->
            Error(
              codec.CannotEncode(codec.CustomEncodeReason("false forbidden")),
            )
        }
      },
    )
  codec.schema(mapped) |> should.equal(Ok(codec.StringSchema))
  codec.decode(mapped, value.String("no"))
  |> should.equal(
    Error(codec.CannotDecode(codec.CustomDecodeReason("unknown flag"))),
  )
  codec.encode(mapped, False)
  |> should.equal(
    Error(codec.CannotEncode(codec.CustomEncodeReason("false forbidden"))),
  )
  let nested = codec.object(codec.required("flag", mapped))
  codec.decode(nested, value.Object([#("flag", value.String("no"))]))
  |> should.equal(
    Error(codec.DecodeAtField(
      "flag",
      codec.CannotDecode(codec.CustomDecodeReason("unknown flag")),
    )),
  )
  codec.encode(nested, False)
  |> should.equal(
    Error(codec.EncodeAtField(
      "flag",
      codec.CannotEncode(codec.CustomEncodeReason("false forbidden")),
    )),
  )
}

pub fn option_property_keeps_missing_null_and_value_test() {
  let properties = codec.optional_option("note", codec.nullable(codec.string()))
  let c = codec.object(properties)
  codec.decode(c, value.Object([])) |> should.equal(Ok(None))
  codec.decode(c, value.Object([#("note", value.Null)]))
  |> should.equal(Ok(Some(codec.Null)))
  codec.decode(c, value.Object([#("note", value.String("hi"))]))
  |> should.equal(Ok(Some(codec.NonNull("hi"))))
  codec.encode(c, Some(codec.Null))
  |> should.equal(Ok(value.Object([#("note", value.Null)])))
  codec.encode(c, None) |> should.equal(Ok(value.Object([])))
}

pub fn generated_option_property_matches_runtime_test() {
  let runtime = codegen.runtime(option_fixtures.definition())
  let generated = option_codec.option_codec()
  let cases = [
    #(value.Object([]), None),
    #(value.Object([#("note", value.Null)]), Some(codec.Null)),
    #(value.Object([#("note", value.String("hi"))]), Some(codec.NonNull("hi"))),
  ]
  list.all(cases, fn(pair) {
    codec.decode(runtime, pair.0) == Ok(pair.1)
    && codec.decode(generated, pair.0) == Ok(pair.1)
    && codec.encode(generated, pair.1) == Ok(pair.0)
  })
  |> should.be_true
  option_codec.decode_option_json("{\"note\":null}")
  |> should.equal(Ok(Some(codec.Null)))
  let assert Ok(compiled) =
    codegen.compile(
      "generated/option_codec",
      "option",
      option_fixtures.definition(),
    )
  let codegen.GeneratedModule(_, content, fingerprint) = compiled
  fingerprint |> should.equal(option_codec.generated_fingerprint)
  let assert Ok(file) = read_file_to_string("test/generated/option_codec.gleam")
  generated_source_normalize.normalize(file)
  |> should.equal(generated_source_normalize.normalize(content))
}

pub fn generated_and_mapped_json_use_strict_admission_test() {
  let generated = order_codec.order_codec()
  let duplicate =
    "{\"order_id\":1,\"order_id\":2,\"items_\\\"list\\\"\":[],\"type\":true,\"status\":\"pending\"}"
  codec.decode_json(generated, duplicate) |> should.be_error
  let mapped = codec.imap(codec.int(), fn(n) { n }, fn(n) { n })
  codec.decode_json(mapped, "1.0000000000000001") |> should.be_error
}

pub fn explicit_limits_and_exact_float_defaults_test() {
  let assert Ok(smallest) =
    number.from_float_exact(float_from_hex("0000000000000001"))
  codec.decode_json(codec.number(), number.number_text(smallest))
  |> should.equal(Ok(smallest))
  let assert Ok(largest) =
    number.from_float_exact(float_from_hex("7fefffffffffffff"))
  codec.decode_json(codec.number(), number.number_text(largest))
  |> should.equal(Ok(largest))
  let assert Ok(num) = number.from_float_exact(0.1)
  let assert Ok(tight_numbers) = number.number_limits(8, 4, 10)
  let assert Ok(tight) = parser.parser_limits(8, 2, tight_numbers)
  codec.decode_json_with_limits(codec.number(), tight, number.number_text(num))
  |> should.be_error
  let assert Ok(short) =
    parser_limits.with_max_bytes(parser.default_limits(), 4)
  codec.decode_json_with_limits(codec.number(), short, number.number_text(num))
  |> should.be_error
  parser_limits.with_max_bytes(parser.default_limits(), 0)
  |> should.equal(Error(parser_limits.MaxBytesMustBePositive))
}

@target(erlang)
pub fn bounded_25_digit_integer_projection_matches_document_test() {
  let large = 1_234_567_890_123_456_789_012_345
  let assert Ok(bounded) = codec.integer_between(0, large)
  let assert Ok(raw) = codec.encode(bounded, large)
  codec.decode(bounded, raw) |> should.equal(Ok(large))
  let assert Ok(contract) = runtime.from_codec(bounded)
  runtime.validate(contract, raw) |> should.be_ok
  let assert Ok(description) = codec.schema(bounded)
  let assert Ok(loaded) = document.load(codec.schema_document(description))
  runtime.validate(loaded, raw) |> should.be_ok
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
    Ok(Some(value)) -> legacy_dynamic.classify(value) |> should.equal("Nil")
    _ -> should.be_true(False)
  }
  legacy_dynamic.optional_field("absent", legacy_dynamic.dynamic)(raw)
  |> should.equal(Ok(None))

  let #(weak_map, key) = weak_map_pair()
  case legacy_dynamic.optional_field(key, legacy_dynamic.dynamic)(weak_map) {
    Ok(Some(value)) -> legacy_dynamic.classify(value) |> should.equal("Nil")
    _ -> should.be_true(False)
  }

  let object = null_proto_object()
  case
    legacy_dynamic.optional_field("present", legacy_dynamic.dynamic)(object)
  {
    Ok(Some(value)) -> legacy_dynamic.classify(value) |> should.equal("Nil")
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
