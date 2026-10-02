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
