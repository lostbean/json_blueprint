//// Regenerates the checked-in generated codecs under `test/generated`:
////
//// ```sh
//// gleam run -m compiled_codec_runner && gleam format test/generated
//// ```

import gleam/io
import json/blueprint/codegen
import materialize_fixtures
import option_fixtures

@external(erlang, "file_test_ffi", "write_file")
@external(javascript, "./file_test_ffi.mjs", "write_file")
fn write_file(path: String, content: String) -> Result(Nil, String)

pub fn main() {
  case
    write_generated(
      "generated/order_codec",
      "order",
      materialize_fixtures.order_definition(),
    )
  {
    Ok(path) -> io.println("Generated test/" <> path)
    Error(error) -> panic as error
  }
  case
    write_generated(
      "generated/option_codec",
      "option",
      option_fixtures.definition(),
    )
  {
    Ok(path) -> io.println("Generated test/" <> path)
    Error(error) -> panic as error
  }
}

fn write_generated(
  module_path: String,
  name: String,
  definition: codegen.Definition(a),
) -> Result(String, String) {
  case codegen.compile(module_path, name, definition) {
    Error(_) -> Error("Failed to compile fixture codec " <> name)
    Ok(codegen.GeneratedModule(path, content, _)) ->
      case write_file("test/" <> path, content) {
        Ok(Nil) -> Ok(path)
        Error(error) -> Error("Failed to write generated codec: " <> error)
      }
  }
}
