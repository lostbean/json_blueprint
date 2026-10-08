import gleam/io
import json/blueprint/codegen
import json/blueprint/codegen/schema as schema_codegen
import json/blueprint/contract
import json/blueprint/value

@external(erlang, "schema_generate_ffi", "read_file")
@external(javascript, "./schema_generate_ffi.mjs", "read_file")
fn read_file(path: String) -> Result(String, String)

@external(erlang, "schema_generate_ffi", "write_file")
@external(javascript, "./schema_generate_ffi.mjs", "write_file")
fn write_file(path: String, content: String) -> Result(Nil, String)

@external(erlang, "schema_generate_ffi", "output_directory")
@external(javascript, "./schema_generate_ffi.mjs", "output_directory")
fn output_directory() -> String

pub fn main() {
  generate("order", "commerce/order")
  generate("numbers", "projection/numbers")
}

pub fn order_schema() -> contract.Contract {
  let assert Ok(text) = read_file("../schema/order.json")
  let assert Ok(loaded) = contract.parse(text, value.default_limits())
  loaded
}

fn generate(name: String, module_path: String) {
  let assert Ok(text) = read_file("../schema/" <> name <> ".json")
  let assert Ok(loaded) = contract.parse(text, value.default_limits())
  let assert Ok(codegen.GeneratedModule(path, content, _)) =
    schema_codegen.compile(module_path, name, contract.schema(loaded))
  let assert Ok(Nil) = write_file(output_directory() <> "/" <> path, content)
  io.println("Generated " <> path)
}
