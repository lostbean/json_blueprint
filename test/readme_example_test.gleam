//// Every Gleam snippet of the README appears verbatim in a compiled and
//// executed example under `examples/src/examples/`. This test fails when a
//// snippet drifts from its example; the `examples/` package runs the examples
//// themselves on both targets.

import gleam/list
import gleam/string
import gleeunit/should

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

const example_modules = [
  "record", "optional_fields", "unions", "custom_types", "errors",
  "gleam_json_bridge", "larger_inputs", "runtime_schema", "schema_inspection",
]

pub fn readme_snippets_are_in_the_examples_verbatim_test() {
  let assert Ok(readme) = read_file_to_string("README.md")
  let sources =
    list.map(example_modules, fn(name) {
      let assert Ok(source) =
        read_file_to_string("examples/src/examples/" <> name <> ".gleam")
      source
    })
  let snippets = gleam_snippets(string.replace(readme, "\r\n", "\n"), [])
  list.length(snippets) |> should.equal(2)
  snippets
  |> list.filter(fn(snippet) {
    !list.any(sources, fn(source) { string.contains(source, snippet) })
  })
  |> should.equal([])
}

fn gleam_snippets(text: String, found: List(String)) -> List(String) {
  case string.split_once(text, "```gleam\n") {
    Error(Nil) -> list.reverse(found)
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\n```") {
        Error(Nil) -> list.reverse(found)
        Ok(#(snippet, after)) -> gleam_snippets(after, [snippet, ..found])
      }
  }
}
