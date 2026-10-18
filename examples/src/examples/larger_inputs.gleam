//// Larger inputs.
////
//// The defaults admit 1 MiB of text, nesting depth 64 and 262,144 values.
//// Raise a limit for a known-large document with the `value.with_*` setters;
//// raising the byte limit does not raise the value limit.

import examples/record.{Admin, User, user_codec}
import gleam/option
import json/blueprint/codec
import json/blueprint/value

pub fn decode_many(
  text: String,
) -> Result(List(record.User), codec.DecodeError) {
  let limits =
    value.default_limits()
    |> value.with_max_bytes(8 * 1024 * 1024)
    |> value.with_max_elements(2_000_000)
  codec.decode_json_with_limits(codec.list(user_codec()), text, limits)
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  let users = [User("Ada", 36, option.None, Admin)]
  let assert Ok(text) = codec.encode_json(codec.list(user_codec()), users)
  assert decode_many(text) == Ok(users)
  "a list of users decodes under explicit limits"
}
