import gleam/dynamic/decode
import gleam/json
import gleeunit/should
import json/blueprint/codec
import json/blueprint/migration
import json/blueprint/number
import json/blueprint/value
import materialize_fixtures

pub fn runtime_nested_codec_json_matches_value_renderer_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let order = sample_order()
  let assert Ok(encoded_value) = codec.encode(runtime, order)
  let expected_json = migration.value_to_json_string(encoded_value)

  codec.encode_json(runtime, order)
  |> should.equal(Ok(expected_json))
  codec.decode_json(runtime, expected_json)
  |> should.equal(Ok(order))
}

pub fn runtime_json_operations_preserve_arbitrary_numbers_test() {
  let assert Ok(limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(arbitrary) =
    number.parse_number(limits, "9007199254740993.123456789e20")
  let number_codec = codec.number()
  let assert Ok(encoded_value) = codec.encode(number_codec, arbitrary)

  codec.encode_json(number_codec, arbitrary)
  |> should.equal(Ok(migration.value_to_json_string(encoded_value)))
  codec.decode_json(number_codec, migration.value_to_json_string(encoded_value))
  |> should.equal(Ok(arbitrary))
}

pub fn runtime_json_decode_preserves_parser_and_codec_errors_test() {
  codec.decode_json(codec.string(), "{")
  |> should.equal(
    Error(
      codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
        codec.BlueprintJsonLocation(1, 1, 2),
        codec.BlueprintUnexpectedEndOfInput,
      )),
    ),
  )

  case codec.decode_json(codec.string(), "1") {
    Error(codec.TypedCodecFailure(codec.CannotDecode(codec.DecodeExpectedString))) ->
      True
    _ -> False
  }
  |> should.be_true

  codec.decode_json(
    materialize_fixtures.build_order_codec(),
    "{\"order_id\":1,\"order_id\":2}",
  )
  |> should.equal(
    Error(
      codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
        codec.BlueprintJsonLocation(14, 1, 15),
        codec.BlueprintDuplicateObjectKey("order_id"),
      )),
    ),
  )
}

pub fn runtime_json_decode_preserves_number_parser_limits_test() {
  codec.decode_json(codec.number(), "1e1001")
  |> should.equal(
    Error(
      codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
        codec.BlueprintJsonLocation(0, 1, 1),
        codec.BlueprintInvalidNumberToken(number.ExponentOutOfRange),
      )),
    ),
  )
}

pub fn native_json_backend_is_interchangeable_without_value_conversion_test() {
  let native =
    codec.from_json_parts(
      native_value_encode,
      native_value_decode,
      native_json_encode,
      native_json_decode,
      codec.StringSchema,
    )

  codec.encode_json(native, "Gleam")
  |> should.equal(Ok("{\"native\":\"Gleam\"}"))
  codec.decode_json(native, "{\"native\":\"Gleam\"}")
  |> should.equal(Ok("Gleam"))

  codec.encode(native, "Gleam")
  |> should.equal(Ok(value.String("value:Gleam")))
  codec.decode(native, value.String("wire"))
  |> should.equal(Ok("value-decoded:wire"))
  codec.schema(native)
  |> should.equal(Ok(codec.StringSchema))

  case codec.decode_json(native, "{}") {
    Error(codec.NativeJsonFailure(_)) -> True
    _ -> False
  }
  |> should.be_true
}

pub fn from_parts_creates_runtime_json_operations_test() {
  let runtime =
    codec.from_parts(
      fn(item: String) { Ok(value.String(item)) },
      fn(raw: value.Value) {
        case raw {
          value.String(item) -> Ok(item)
          _ -> Error(codec.CannotDecode(codec.DecodeExpectedString))
        }
      },
      codec.StringSchema,
    )

  codec.encode_json(runtime, "parts")
  |> should.equal(Ok("\"parts\""))
  codec.decode_json(runtime, "\"parts\"")
  |> should.equal(Ok("parts"))
}

fn native_value_encode(item: String) -> Result(value.Value, codec.EncodeError) {
  Ok(value.String("value:" <> item))
}

fn native_value_decode(raw: value.Value) -> Result(String, codec.DecodeError) {
  case raw {
    value.String(item) -> Ok("value-decoded:" <> item)
    _ -> Error(codec.CannotDecode(codec.DecodeExpectedString))
  }
}

fn native_json_encode(item: String) -> Result(String, codec.EncodeError) {
  Ok(json.object([#("native", json.string(item))]) |> json.to_string)
}

fn native_json_decode(source: String) -> Result(String, codec.JsonDecodeError) {
  let decoder = {
    use item <- decode.field("native", decode.string)
    decode.success(item)
  }
  case json.parse(from: source, using: decoder) {
    Ok(item) -> Ok(item)
    Error(error) -> Error(codec.NativeJsonFailure(error))
  }
}

fn sample_order() -> materialize_fixtures.Order {
  materialize_fixtures.Order(
    42,
    [#("widget", 2), #("雪 🚀", 7)],
    codec.Present(codec.NonNull("leave at door")),
    True,
    materialize_fixtures.ShippedQuoted,
  )
}
