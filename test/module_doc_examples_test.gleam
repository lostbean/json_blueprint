//// The examples in the module docs, compiled and run. Keep them identical.

import gleam/int
import gleam/json
import gleeunit/should
import json/blueprint
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/parser
import json/blueprint/parser_limits
import json/blueprint/runtime
import json/blueprint/value

// json/blueprint

pub type User {
  User(name: String, age: Int)
}

pub fn user_decoder() -> blueprint.Decoder(User) {
  blueprint.decode2(
    User,
    blueprint.field("name", blueprint.string()),
    blueprint.field("age", blueprint.int()),
  )
}

fn blueprint_example() {
  let assert Ok(User("Ada", 36)) =
    blueprint.decode(
      using: user_decoder(),
      from: "{\"name\":\"Ada\",\"age\":36}",
    )
  blueprint.generate_json_schema(user_decoder()) |> json.to_string
}

pub fn blueprint_module_example_test() {
  let schema = blueprint_example()
  { schema != "" } |> should.be_true
}

// json/blueprint/codec

pub type Task {
  Task(id: Int, title: String)
}

pub fn task_codec() -> codec.Codec(Task) {
  let assert Ok(id) = codec.integer_between(1, 100_000)
  let assert Ok(task) =
    codec.record2(
      codec.required("id", id),
      codec.required("title", codec.string()),
      Task,
      fn(task) { task.id },
      fn(task) { task.title },
    )
  task
}

fn codec_example() -> Result(String, String) {
  case codec.decode_json(task_codec(), "{\"id\":42,\"title\":\"Ship\"}") {
    Error(error) -> Error(codec.render_json_decode_error(error))
    Ok(task) ->
      case codec.encode_json(task_codec(), task) {
        Ok(text) -> Ok(text)
        Error(_) -> Error("cannot encode")
      }
  }
}

pub fn codec_module_example_test() {
  codec_example() |> should.equal(Ok("{\"id\":42,\"title\":\"Ship\"}"))
}

// json/blueprint/codegen

pub fn names_definition() -> codegen.Definition(List(String)) {
  codegen.list(codegen.string())
}

fn codegen_example() {
  let assert Ok(["a", "b"]) =
    codec.decode_json(codegen.runtime(names_definition()), "[\"a\",\"b\"]")
  // In a build task: write `content` to "src/" <> path.
  let assert Ok(codegen.GeneratedModule(path:, content:, fingerprint: _)) =
    codegen.compile("generated/names_codec", "names", names_definition())
  #(path, content)
}

pub fn codegen_module_example_test() {
  let #(path, content) = codegen_example()
  path |> should.equal("generated/names_codec.gleam")
  { content != "" } |> should.be_true
}

// json/blueprint/parser

fn parser_example() {
  let assert Ok(limits) =
    parser_limits.with_max_bytes(parser.default_limits(), 64 * 1024)
  case parser.parse_value_from_string(limits, "{\"tags\": [\"a\"]}") {
    Ok(value.Object(members)) -> Ok(members)
    Ok(_) -> Error("expected an object")
    Error(parser.ParseError(location, _kind)) ->
      Error("invalid JSON at byte " <> int.to_string(location.byte_offset))
  }
}

pub fn parser_module_example_test() {
  parser_example()
  |> should.equal(Ok([#("tags", value.Array([value.String("a")]))]))
}

// json/blueprint/runtime

fn runtime_example() {
  let names = codec.list(codec.string())
  let assert Ok(contract) = runtime.from_codec(names)
  let assert Ok(parsed) =
    parser.parse_value_from_string(parser.default_limits(), "[\"a\"]")
  let assert Ok(validated) = runtime.validate(contract, parsed)
  let assert Ok(["a"]) = runtime.decode(names, validated)
}

pub fn runtime_module_example_test() {
  runtime_example()
}
