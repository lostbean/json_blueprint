import gleam/io
import json/blueprint/codegen
import materialize_fixtures
import option_fixtures

@external(erlang, "file_test_ffi", "write_file")
@external(javascript, "./file_test_ffi.mjs", "write_file")
fn write_file(path: String, content: String) -> Result(Nil, String)

pub fn main() {
  case generate() {
    Ok(path) -> {
      io.println("Generated test/" <> path)
      case
        write_generated(
          "generated/option_codec",
          "option",
          option_fixtures.definition(),
        )
      {
        Ok(option_path) -> io.println("Generated test/" <> option_path)
        Error(error) -> panic as error
      }
    }
    Error(error) -> panic as error
  }
}

fn write_generated(
  module_path: String,
  name: String,
  definition: codegen.Definition(a),
) -> Result(String, String) {
  case codegen.compile(module_path, name, definition) {
    Error(_) -> Error("Failed to compile fixture codec")
    Ok(generated) -> {
      let codegen.GeneratedModule(path, content, _) = generated
      case write_file("test/" <> path, content) {
        Ok(Nil) -> Ok(path)
        Error(error) -> Error("Failed to write generated codec: " <> error)
      }
    }
  }
}

fn generate() -> Result(String, String) {
  write_generated(
    "generated/order_codec",
    "order",
    materialize_fixtures.order_definition(),
  )
}
