import gleam/int
import gleam/json
import gleam/list
import gleam/string
import json/blueprint as legacy
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value.{type Value}

pub fn adapt(
  decoder: legacy.Decoder(a),
  encode: fn(a) -> Result(Value, codec.EncodeError),
) -> codec.Codec(a) {
  codec.new(encode, fn(raw: Value) {
    let json_string = value_to_json_string(raw)
    case legacy.decode(using: decoder, from: json_string) {
      Ok(decoded) -> Ok(decoded)
      Error(_) ->
        Error(
          codec.CannotDecode(codec.CustomDecodeReason(
            "json_blueprint 1.7.1 rejected the Value",
          )),
        )
    }
  })
}

pub fn value_to_json_string(val: Value) -> String {
  case val {
    value.Null -> "null"
    value.Bool(True) -> "true"
    value.Bool(False) -> "false"
    value.String(s) -> json.to_string(json.string(s))
    value.Number(n) -> {
      let assert Ok(limit) = number.integer_projection_limit(50)
      case number.to_int_exact(n, limit) {
        Ok(i) -> int.to_string(i)
        Error(_) -> number.number_text(n)
      }
    }
    value.Array(items) ->
      "[" <> string.join(list.map(items, value_to_json_string), ",") <> "]"
    value.Object(pairs) ->
      "{"
      <> string.join(
        list.map(pairs, fn(p) {
          json.to_string(json.string(p.0)) <> ":" <> value_to_json_string(p.1)
        }),
        ",",
      )
      <> "}"
  }
}
