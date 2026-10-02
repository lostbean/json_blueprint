//// The `json/blueprint/codegen` module doc example, verbatim.

import json/blueprint/codec
import json/blueprint/codegen

pub fn names_definition() -> codegen.Definition(List(String)) {
  codegen.list(codegen.string())
}

pub fn example() {
  let assert Ok(["a", "b"]) =
    codec.decode_json(codegen.runtime(names_definition()), "[\"a\",\"b\"]")
  // In a build task: write `content` to "src/" <> path.
  let assert Ok(codegen.GeneratedModule(path:, content:, fingerprint: _)) =
    codegen.compile("generated/names_codec", "names", names_definition())
  #(path, content)
}

import gleeunit/should

pub fn codegen_module_example_test() {
  let #(path, content) = example()
  path |> should.equal("generated/names_codec.gleam")
  { content != "" } |> should.be_true
}
