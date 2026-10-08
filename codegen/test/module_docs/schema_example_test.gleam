import json/blueprint/codegen/schema
import json/blueprint/contract
import json/blueprint/value

pub fn generate_order() {
  let assert Ok(contract) =
    contract.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"orderId\":{\"type\":\"string\"}},\"required\":[\"orderId\"],\"additionalProperties\":false}",
      value.default_limits(),
    )
  schema.compile("generated/order", "order", contract.schema(contract))
}

import gleeunit/should

pub fn schema_module_example_test() {
  let assert Ok(module) = generate_order()
  module.path |> should.equal("generated/order.gleam")
}
