//// gleam/json and other libraries.
////
//// `codec.to_json` returns a `json.Json` and `codec.decoder` a
//// `decode.Decoder`, so the same codec serves libraries that speak
//// `gleam/json`. `to_json` is exact: a number without an exact `gleam/json`
//// form, such as `1e400` in a `codec.number()`, fails with
//// `UnrepresentableNumber`. With `decoder`, the parser that produced the data
//// owns duplicate keys, number precision and size limits.

import examples/record.{type User, Member, User, user_codec}
import gleam/json
import gleam/option
import json/blueprint/codec

pub fn with_gleam_json(user: User) -> Result(User, json.DecodeError) {
  let assert Ok(encoded) = codec.to_json(user_codec(), user)
  json.parse(json.to_string(encoded), codec.decoder(user_codec()))
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  let user = User("Ada", 36, option.Some("ada@example.com"), Member)
  assert with_gleam_json(user) == Ok(user)
  "the same codec round-trips through gleam/json"
}
