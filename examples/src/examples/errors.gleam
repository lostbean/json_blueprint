//// Error handling and definition checks.
////
//// `DecodeError` and `EncodeError` are `{path, reason}` records. Branch on
//// the reason, or render the error. The library writes the path and the text
//// of its own reasons, which never contain input values or unknown keys from
//// the input. A `Custom` reason renders the caller's message verbatim, so
//// leave input values out of a message that must not show them. `Reason` may
//// gain variants in minor releases, so match it with a `_` branch.
////
//// A codec written wrongly, such as a field named twice, an enum label
//// repeated or reversed bounds, panics with a message naming the field, label
//// or bounds when that part is first used. For a definition built from
//// runtime data, call `codec.check` to get the mistake as a `DefinitionError`
//// instead.

import examples/record
import gleam/list
import gleam/string
import json/blueprint/codec

pub fn explain(text: String) -> String {
  case codec.decode_json(record.user_codec(), text) {
    Ok(_) -> "ok"
    Error(error) ->
      case codec.is_limit_exceeded(error) {
        True -> "the request is too large"
        False -> codec.describe_decode_error(error)
      }
  }
}

pub fn status_codec(
  labels: List(String),
) -> Result(codec.Codec(String), codec.DefinitionError) {
  codec.string_enum(list.map(labels, fn(label) { #(label, label) }))
  |> codec.check
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  assert explain("{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}") == "ok"
  assert explain("{\"name\":\"Ada\",\"age\":360,\"role\":\"admin\"}")
    == "$[\"age\"]: integer outside range 0 to 150"
  assert explain("[" <> string.repeat(" ", 1_048_576) <> "]")
    == "the request is too large"

  let assert Ok(status) = status_codec(["open", "closed"])
  assert codec.decode_json(status, "\"open\"") == Ok("open")
  assert status_codec(["open", "open"])
    == Error(codec.DuplicateEnumLabel("open"))
  "refused input is explained with its path; a bad definition is a value"
}
