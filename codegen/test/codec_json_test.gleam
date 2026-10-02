import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec.{DecodeError, EncodeError, Field}
import json/blueprint/number
import json/blueprint/value
import materialize_fixtures

pub fn runtime_nested_codec_json_matches_value_renderer_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let order = sample_order()
  let assert Ok(encoded_value) = codec.encode(runtime, order)
  let expected_json = value.to_string(encoded_value)

  codec.encode_json(runtime, order)
  |> should.equal(Ok(expected_json))
  codec.decode_json(runtime, expected_json)
  |> should.equal(Ok(order))
}

pub fn runtime_json_operations_preserve_arbitrary_numbers_test() {
  let limits =
    number.limits(
      max_token_bytes: 1024,
      max_significant_digits: 100,
      max_exponent: 1000,
    )
  let assert Ok(arbitrary) =
    number.parse("9007199254740993.123456789e20", limits)
  let number_codec = codec.number()
  let assert Ok(encoded_value) = codec.encode(number_codec, arbitrary)

  codec.encode_json(number_codec, arbitrary)
  |> should.equal(Ok(value.to_string(encoded_value)))
  codec.decode_json(number_codec, value.to_string(encoded_value))
  |> should.equal(Ok(arbitrary))
}

pub fn runtime_json_decode_preserves_parser_and_codec_errors_test() {
  codec.decode_json(codec.string(), "{")
  |> should.equal(
    Error(DecodeError(
      [],
      codec.InvalidJson(value.ParseError(
        value.Location(1, 1, 2),
        value.UnexpectedEndOfInput,
      )),
    )),
  )

  codec.decode_json(codec.string(), "1")
  |> should.equal(Error(DecodeError([], codec.ExpectedString)))

  codec.decode_json(
    materialize_fixtures.build_order_codec(),
    "{\"order_id\":1,\"order_id\":2}",
  )
  |> should.equal(
    Error(DecodeError(
      [],
      codec.InvalidJson(value.ParseError(
        value.Location(14, 1, 15),
        value.DuplicateObjectKey,
      )),
    )),
  )
}

pub fn runtime_json_decode_preserves_number_parser_limits_test() {
  let assert Error(error) = codec.decode_json(codec.number(), "1e1201")
  error
  |> should.equal(DecodeError(
    [],
    codec.InvalidJson(value.ParseError(
      value.Location(0, 1, 1),
      value.InvalidNumber(number.ExponentOutOfRange),
    )),
  ))
  codec.is_limit_exceeded(error) |> should.be_true
}

pub fn custom_codec_json_operations_use_its_value_functions_test() {
  // Without separate JSON parts, a custom codec's text operations route
  // through its `Value` functions and the strict parser.
  let custom =
    codec.custom(
      encode: prefixed_encode,
      decode: prefixed_decode,
      schema: Some(codec.StringSchema),
      placeholder: "",
    )

  codec.encode(custom, "Gleam")
  |> should.equal(Ok(value.String("value:Gleam")))
  codec.decode(custom, value.String("wire"))
  |> should.equal(Ok("value-decoded:wire"))
  codec.encode_json(custom, "Gleam")
  |> should.equal(Ok("\"value:Gleam\""))
  codec.decode_json(custom, "\"wire\"")
  |> should.equal(Ok("value-decoded:wire"))
  codec.decode_json(custom, "{\"native\":\"Gleam\"}")
  |> should.equal(Error(DecodeError([], codec.ExpectedString)))
  codec.schema(custom)
  |> should.equal(Ok(codec.StringSchema))
  codec.schema_json(custom)
  |> should.equal(Ok(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"string\"}",
  ))
}

pub fn gleam_json_bridges_use_the_value_functions_test() {
  let custom =
    codec.custom(
      encode: prefixed_encode,
      decode: prefixed_decode,
      schema: Some(codec.StringSchema),
      placeholder: "",
    )

  let assert Ok(encoded) = codec.to_json(custom, "Gleam")
  json.to_string(encoded) |> should.equal("\"value:Gleam\"")
  json.parse("\"wire\"", codec.decoder(custom))
  |> should.equal(Ok("value-decoded:wire"))

  // gleam/json owns parsing; the codec owns the failure text.
  let assert Error(json.UnableToDecode([decode.DecodeError(expected:, ..)])) =
    json.parse("{\"native\":\"Gleam\"}", codec.decoder(custom))
  expected
  |> should.equal(
    codec.describe_decode_error(DecodeError([], codec.ExpectedString)),
  )

  // A codec nested in a record keeps its failures at the field's path.
  let nested = {
    use name <- codec.field("name", custom, fn(name: String) { name })
    codec.success(name)
  }
  let assert Error(json.UnableToDecode([decode.DecodeError(expected:, ..)])) =
    json.parse("{\"name\":1}", codec.decoder(nested))
  expected
  |> should.equal(
    codec.describe_decode_error(DecodeError(
      [Field("name")],
      codec.ExpectedString,
    )),
  )
}

pub fn to_json_rejects_numbers_without_an_exact_gleam_json_form_test() {
  let assert Ok(huge) = number.parse("1e400", number.default_limits())
  let numbers = codec.list(codec.number())
  let assert Ok(one) = number.from_int(1)

  codec.encode_json(numbers, [one, huge]) |> should.equal(Ok("[1,1e400]"))
  case codec.to_json(numbers, [one, huge]) {
    Error(EncodeError([codec.Index(1)], codec.UnrepresentableNumber(found))) ->
      found |> should.equal(huge)
    _ -> should.fail()
  }
}

pub fn custom_codec_creates_runtime_json_operations_test() {
  let runtime =
    codec.custom(
      encode: fn(item: String) { Ok(value.String(item)) },
      decode: fn(raw: value.Value) {
        case raw {
          value.String(item) -> Ok(item)
          _ -> Error(DecodeError([], codec.ExpectedString))
        }
      },
      schema: Some(codec.StringSchema),
      placeholder: "",
    )

  codec.encode_json(runtime, "parts")
  |> should.equal(Ok("\"parts\""))
  codec.decode_json(runtime, "\"parts\"")
  |> should.equal(Ok("parts"))
  codec.decode_json(runtime, "[\"parts\"]")
  |> should.equal(Error(DecodeError([], codec.ExpectedString)))
}

pub fn custom_codec_failure_helpers_build_custom_reasons_test() {
  let refusing =
    codec.custom(
      encode: fn(_: String) { Error(codec.encode_failure("never encodes")) },
      decode: fn(_) { Error(codec.decode_failure("never decodes")) },
      schema: None,
      placeholder: "",
    )
  let wrapped = {
    use text <- codec.field("text", refusing, fn(text: String) { text })
    codec.success(text)
  }

  codec.encode(wrapped, "x")
  |> should.equal(
    Error(EncodeError([Field("text")], codec.Custom("never encodes"))),
  )
  codec.decode_json(wrapped, "{\"text\":\"x\"}")
  |> should.equal(
    Error(DecodeError([Field("text")], codec.Custom("never decodes"))),
  )
  // The rendered text is the library's path and the caller's message.
  let assert Error(error) = codec.decode_json(wrapped, "{\"text\":\"x\"}")
  codec.describe_decode_error(error)
  |> should.equal("$[\"text\"]: never decodes")
}

fn prefixed_encode(item: String) -> Result(value.Value, codec.EncodeError) {
  Ok(value.String("value:" <> item))
}

fn prefixed_decode(raw: value.Value) -> Result(String, codec.DecodeError) {
  case raw {
    value.String(item) -> Ok("value-decoded:" <> item)
    _ -> Error(DecodeError([], codec.ExpectedString))
  }
}

fn sample_order() -> materialize_fixtures.Order {
  materialize_fixtures.Order(
    42,
    [#("widget", 2), #("雪 🚀", 7)],
    Some(Some("leave at door")),
    True,
    materialize_fixtures.ShippedQuoted,
  )
}
