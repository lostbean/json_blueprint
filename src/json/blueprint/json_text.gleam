//// Rendering of a `Value` as compact JSON text.
////
//// `render_value` writes no whitespace and keeps object members in order.
//// An integer that fits a native `Int` (up to 50 digits, and on JavaScript
//// within ±9,007,199,254,740,991) is written in plain decimal; other numbers
//// use `number.number_text`, which writes scientific notation such as
//// `1.25e1`. `codec.encode_json` uses this renderer for runtime codecs.

import gleam/int
import gleam/json
import gleam/list
import gleam/string
import json/blueprint/number
import json/blueprint/value.{type Value}

pub fn render_value(value: Value) -> String {
  case value {
    value.Null -> "null"
    value.Bool(True) -> "true"
    value.Bool(False) -> "false"
    value.String(item) -> json.to_string(json.string(item))
    value.Number(item) -> {
      let assert Ok(limit) = number.integer_projection_limit(50)
      case number.to_int_exact(item, limit) {
        Ok(integer) -> int.to_string(integer)
        Error(_) -> number.number_text(item)
      }
    }
    value.Array(items) ->
      "[" <> string.join(list.map(items, render_value), ",") <> "]"
    value.Object(pairs) ->
      "{"
      <> string.join(
        list.map(pairs, fn(pair) {
          json.to_string(json.string(pair.0)) <> ":" <> render_value(pair.1)
        }),
        ",",
      )
      <> "}"
  }
}
