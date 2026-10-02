//// Module docs are part of the API: every public module has a `////` doc,
//// and every example in one is compiled and run, verbatim, by a test in
//// `test/module_docs/`.

import gleam/list
import gleam/string
import gleeunit/should

@external(erlang, "module_docs_test_ffi", "public_sources")
@external(javascript, "./module_docs_test_ffi.mjs", "public_sources")
fn public_sources() -> List(#(String, String))

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

pub fn every_public_module_starts_with_a_module_doc_test() {
  let sources = public_sources()
  sources
  |> list.map(fn(source) { source.0 })
  |> should.equal([
    "src/json/blueprint.gleam",
    "src/json/blueprint/codec.gleam",
    "src/json/blueprint/codegen.gleam",
    "src/json/blueprint/contract.gleam",
    "src/json/blueprint/number.gleam",
    "src/json/blueprint/schema.gleam",
    "src/json/blueprint/value.gleam",
  ])
  sources
  |> list.filter(fn(source) { !string.starts_with(source.1, "//// ") })
  |> list.map(fn(source) { source.0 })
  |> should.equal([])
}

pub fn module_doc_examples_are_tested_verbatim_test() {
  // Every public module except the 1.x schema types has an example.
  public_sources()
  |> list.count(fn(source) { doc_examples(source.1) != [] })
  |> should.equal(list.length(public_sources()) - 1)
  public_sources()
  |> list.filter(fn(source) {
    case doc_examples(source.1) {
      [] -> False
      examples -> {
        let assert Ok(tests) = read_file_to_string(example_test_path(source.0))
        list.any(examples, fn(example) { !string.contains(tests, example) })
      }
    }
  })
  |> list.map(fn(source) { source.0 })
  |> should.equal([])
}

/// `src/json/blueprint/codec.gleam` is tested by
/// `test/module_docs/codec_example_test.gleam`.
fn example_test_path(module_path: String) -> String {
  let name = case string.split(module_path, "/") |> list.last {
    Ok("blueprint.gleam") | Error(Nil) -> "blueprint"
    Ok(file) -> string.replace(file, ".gleam", "")
  }
  "test/module_docs/" <> name <> "_example_test.gleam"
}

/// The Gleam code blocks of a module doc, without the `//// ` prefix.
fn doc_examples(source: String) -> List(String) {
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
  blocks(doc, [])
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
