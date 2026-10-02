//// The module doc example and the README example are compiled and run,
//// verbatim, by `module_docs/codegen_example_test`.

import gleam/list
import gleam/string
import gleeunit/should

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

pub fn module_doc_and_readme_examples_are_tested_verbatim_test() {
  let assert Ok(tests) =
    read_file_to_string("test/module_docs/codegen_example_test.gleam")
  let assert Ok(source) =
    read_file_to_string("src/json/blueprint/codegen.gleam")
  let assert Ok(readme) = read_file_to_string("README.md")
  let doc =
    string.split(source, "\n")
    |> list.take_while(fn(line) { string.starts_with(line, "////") })
    |> list.map(fn(line) {
      case line {
        "//// " <> rest -> rest
        _ -> ""
      }
    })
    |> string.join("\n")
  let examples = list.append(blocks(doc, []), blocks(readme, []))
  list.length(examples) |> should.equal(2)
  examples
  |> list.filter(fn(example) { !string.contains(tests, example) })
  |> should.equal([])
}

fn blocks(text: String, found: List(String)) -> List(String) {
  case string.split_once(text, "```gleam\n") {
    Error(Nil) -> list.reverse(found)
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\n```") {
        Error(Nil) -> list.reverse(found)
        Ok(#(block, after)) -> blocks(after, [block, ..found])
      }
  }
}
