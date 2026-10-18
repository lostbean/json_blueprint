//// A record, both ways: one codec encodes a native value, decodes JSON
//// strictly and publishes a Draft 2020-12 schema.
////
//// `codec.field` adds a required field and `codec.optional_field` an optional
//// one; `codec.success` builds the record from the decoded fields. Pass each
//// getter with its `get:` label; it needs no type annotation, because the rest
//// of the block, which ends in `success`, fixes the record type first.
//// Decoding is strict: unknown fields, duplicate keys and wrong types fail,
//// with the path to the failure. These built-in operations are synchronous
//// and keep no process or connection to close.
//// The README quotes the first snippet below verbatim.

import gleam/option.{type Option}
import gleam/result
import json/blueprint/codec.{type Codec}

pub type Role {
  Admin
  Member
}

pub type User {
  User(name: String, age: Int, email: Option(String), role: Role)
}

pub fn user_codec() -> Codec(User) {
  let role = codec.string_enum([#("admin", Admin), #("member", Member)])
  use name <- codec.field("name", codec.string(), get: fn(u) { u.name })
  use age <- codec.field("age", codec.integer_between(0, 150), get: fn(u) {
    u.age
  })
  use email <- codec.optional_field("email", codec.string(), get: fn(u) {
    u.email
  })
  use role <- codec.field("role", role, get: fn(u) { u.role })
  codec.success(User(name:, age:, email:, role:))
}

pub fn round_trip() -> Result(User, String) {
  let text = "{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}"
  use user <- result.try(
    codec.decode_json(user_codec(), text)
    |> result.map_error(codec.describe_decode_error),
  )
  let assert Ok(_text) = codec.encode_json(user_codec(), user)
  let assert Ok(_schema) = codec.schema_json(user_codec())
  Ok(user)
}

/// Decodes a user whose age is out of range, so the failure names its path.
pub fn out_of_range_age() -> String {
  let text = "{\"name\":\"Ada\",\"age\":360,\"role\":\"admin\"}"
  let assert Error(error) = codec.decode_json(user_codec(), text)
  codec.describe_decode_error(error)
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  let assert Ok(user) = round_trip()
  assert user == User("Ada", 36, option.None, Admin)
  let assert Ok(text) = codec.encode_json(user_codec(), user)
  let assert Ok(schema) = codec.schema_json(user_codec())
  assert out_of_range_age() == "$[\"age\"]: integer outside range 0 to 150"
  "encoded: " <> text <> "\nschema: " <> schema
}
