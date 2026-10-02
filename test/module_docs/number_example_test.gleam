//// The `json/blueprint/number` module doc example, verbatim.

import gleam/order
import json/blueprint/number

pub fn example() {
  let assert Ok(price) = number.parse("19.90", number.default_limits())
  let assert Ok(same) = number.parse("1.99e1", number.default_limits())
  let assert order.Eq = number.compare(price, same)
  let assert Ok(19.9) = number.to_float(price)
  number.to_string(price)
}

import gleeunit/should

pub fn number_module_example_test() {
  example() |> should.equal("1.99e1")
}
