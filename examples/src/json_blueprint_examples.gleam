//// Runs every usage example and prints what each one shows.
////
//// `gleam run` in this directory is the quickest tour; `gleam test` checks
//// each example's assertions on both targets.

import examples/custom_types
import examples/errors
import examples/gleam_json_bridge
import examples/larger_inputs
import examples/optional_fields
import examples/record
import examples/runtime_schema
import examples/schema_inspection
import examples/unions
import gleam/io

pub fn main() -> Nil {
  [
    #("record", record.demonstrate()),
    #("optional_fields", optional_fields.demonstrate()),
    #("unions", unions.demonstrate()),
    #("custom_types", custom_types.demonstrate()),
    #("errors", errors.demonstrate()),
    #("gleam_json_bridge", gleam_json_bridge.demonstrate()),
    #("larger_inputs", larger_inputs.demonstrate()),
    #("runtime_schema", runtime_schema.demonstrate()),
    #("schema_inspection", schema_inspection.demonstrate()),
  ]
  |> list_each
}

fn list_each(examples: List(#(String, String))) -> Nil {
  case examples {
    [] -> Nil
    [#(name, shown), ..rest] -> {
      io.println("== " <> name <> "\n" <> shown <> "\n")
      list_each(rest)
    }
  }
}
