//// The `json/blueprint` module doc example, verbatim.

import gleam/json
import json/blueprint

pub type User {
  User(name: String, age: Int)
}

pub fn user_decoder() -> blueprint.Decoder(User) {
  blueprint.decode2(
    User,
    blueprint.field("name", blueprint.string()),
    blueprint.field("age", blueprint.int()),
  )
}

pub fn example() {
  let assert Ok(User("Ada", 36)) =
    blueprint.decode(
      using: user_decoder(),
      from: "{\"name\":\"Ada\",\"age\":36}",
    )
  blueprint.generate_json_schema(user_decoder()) |> json.to_string
}

import gleeunit/should

pub fn blueprint_module_example_test() {
  let schema = example()
  { schema != "" } |> should.be_true
}
