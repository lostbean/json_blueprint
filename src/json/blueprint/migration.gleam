import json/blueprint as legacy
import json/blueprint/codec
import json/blueprint/json_text
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
  json_text.render_value(val)
}
