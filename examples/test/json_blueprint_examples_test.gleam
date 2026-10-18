//// Each usage example runs here on both targets; its own `demonstrate`
//// carries the assertions, so API drift fails this module.

import examples/custom_types
import examples/errors
import examples/gleam_json_bridge
import examples/larger_inputs
import examples/optional_fields
import examples/record
import examples/runtime_schema
import examples/schema_inspection
import examples/unions
import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn record_test() {
  let _ = record.demonstrate()
}

pub fn optional_fields_test() {
  let _ = optional_fields.demonstrate()
}

pub fn unions_test() {
  let _ = unions.demonstrate()
}

pub fn custom_types_test() {
  let _ = custom_types.demonstrate()
}

pub fn errors_test() {
  let _ = errors.demonstrate()
}

pub fn gleam_json_bridge_test() {
  let _ = gleam_json_bridge.demonstrate()
}

pub fn larger_inputs_test() {
  let _ = larger_inputs.demonstrate()
}

pub fn runtime_schema_test() {
  let _ = runtime_schema.demonstrate()
}

pub fn schema_inspection_test() {
  let _ = schema_inspection.demonstrate()
}
