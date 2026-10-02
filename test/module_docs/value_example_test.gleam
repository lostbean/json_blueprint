//// The `json/blueprint/value` module doc example, verbatim.

import json/blueprint/value

pub fn example() {
  let limits = value.default_limits() |> value.with_max_bytes(64 * 1024)
  case value.parse("{\"tags\": [\"a\"]}", limits) {
    Ok(value.Object(members)) -> Ok(members)
    Ok(_) -> Error("expected an object")
    Error(error) -> Error(value.describe_parse_error(error))
  }
}

import gleeunit/should

pub fn value_module_example_test() {
  example()
  |> should.equal(Ok([#("tags", value.Array([value.String("a")]))]))
}
