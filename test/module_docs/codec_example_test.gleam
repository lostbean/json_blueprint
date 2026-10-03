//// The `json/blueprint/codec` module doc example, verbatim.

import gleam/option.{type Option}
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

pub fn example() -> Result(String, String) {
  let text = "{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}"
  case codec.decode_json(user_codec(), text) {
    Error(error) -> Error(codec.describe_decode_error(error))
    Ok(user) -> {
      let assert Ok(text) = codec.encode_json(user_codec(), user)
      Ok(text)
    }
  }
}

import gleeunit/should

pub fn codec_module_example_test() {
  example()
  |> should.equal(Ok("{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}"))
}

// The schema translation example.

import gleam/list

/// Whether a provider that takes strings, integers, booleans, lists and
/// closed objects of them can take `schema`.
pub fn supported(schema: codec.Schema) -> Bool {
  case codec.view(schema) {
    codec.StringSchema
    | codec.StringEnumSchema(_)
    | codec.IntSchema
    | codec.IntegerRangeSchema(_, _)
    | codec.BoolSchema -> True
    codec.ListSchema(items) -> supported(items)
    codec.ObjectSchema(properties) ->
      list.all(properties, fn(property) { supported(property.schema) })
    codec.NumberSchema
    | codec.NumberRangeSchema(_, _)
    | codec.PairSchema(_, _)
    | codec.NullableSchema(_)
    | codec.UnionSchema(_)
    | codec.AnySchema -> False
    // A kind added in a later 2.x release: reject what is not known.
    codec.OtherSchema(_) -> False
  }
}

pub fn codec_module_schema_view_example_test() {
  let assert Ok(user) = codec.schema(user_codec())
  supported(user) |> should.be_true
  let assert Ok(scores) = codec.schema(codec.list(codec.float()))
  supported(scores) |> should.be_false
  let assert Ok(anything) = codec.schema(codec.value())
  supported(anything) |> should.be_false
}
