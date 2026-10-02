//// The `json/blueprint/contract` module doc example, verbatim.

import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/value

pub fn example() {
  let names = codec.list(codec.string())
  let schema_text =
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
    <> "\"type\":\"array\",\"items\":{\"type\":\"string\"}}"
  let assert Ok(remote) = contract.parse(schema_text, value.default_limits())
  let assert Ok(parsed) = value.parse("[\"a\"]", value.default_limits())
  let assert Ok(validated) = contract.validate(remote, parsed)
  let assert Ok(["a"]) = contract.decode(names, validated)
}

pub fn contract_module_example_test() {
  example()
}
