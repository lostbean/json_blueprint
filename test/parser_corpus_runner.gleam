//// Byte-preserving parser probe for the independent Python corpus checker.

import gleam/bit_array
import gleam/io
import gleam/json
import gleam/list
import json/blueprint/value

@external(erlang, "parser_corpus_ffi", "read_cases")
@external(javascript, "./parser_corpus_ffi.mjs", "read_cases")
fn read_cases() -> List(#(String, BitArray))

fn rejection(reason: value.ParseReason) -> String {
  case reason {
    value.DuplicateObjectKey -> "duplicate"
    value.InvalidUtf8 -> "utf8"
    value.InvalidUnicodeEscape -> "unicode_escape"
    value.InvalidNumber(_) -> "number"
    value.RuntimeCapacityExceeded -> "capacity"
    _ -> "syntax"
  }
}

pub fn main() -> Nil {
  list.each(read_cases(), fn(item) {
    let #(name, bytes) = item
    let fields = case value.parse_bits(bytes, value.default_limits()) {
      Ok(parsed) -> {
        let assert Ok(text) = bit_array.to_string(bytes)
        let assert Ok(from_text) = value.parse(text, value.default_limits())
        let assert True = from_text == parsed
        let rendered = value.to_string(parsed)
        // Rendering preserves exact values and admitted structure.
        let assert Ok(reparsed) = value.parse(rendered, value.default_limits())
        let assert True = reparsed == parsed
        [#("rendered", json.string(rendered))]
      }
      Error(error) -> [#("rejected", json.string(rejection(error.reason)))]
    }
    json.object([#("name", json.string(name)), ..fields])
    |> json.to_string
    |> io.println
  })
}
