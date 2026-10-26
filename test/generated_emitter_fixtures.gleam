// Adversarial source names and types must survive specialization untouched.
import gleam/dynamic
import gleam/dynamic/decode
import gleam/option.{type Option}
import json/blueprint/codegen

pub fn from_native_decode(item: Int) -> Int {
  item
}

pub fn to_native_decode(item: Int) -> Int {
  item
}

pub fn from_dynamic(item: Int) -> dynamic.Dynamic {
  dynamic.int(item)
}

pub fn to_dynamic(item: dynamic.Dynamic) -> Int {
  let assert Ok(item) = decode.run(item, decode.int)
  item
}

pub fn optional_definition() -> codegen.Definition(Option(String)) {
  codegen.object(codegen.optional("x_native_decode(\"\\", codegen.string()))
}

pub fn named_definition() -> codegen.Definition(Int) {
  let assert Ok(mapping) =
    codegen.named_mapping(
      from_native_decode,
      "generated_emitter_fixtures.from_native_decode",
      to_native_decode,
      "generated_emitter_fixtures.to_native_decode",
    )
  let assert Ok(definition) = codegen.imap(codegen.int(), "Int", mapping)
  definition
}

pub fn dynamic_definition() -> codegen.Definition(dynamic.Dynamic) {
  let assert Ok(mapping) =
    codegen.named_mapping(
      from_dynamic,
      "generated_emitter_fixtures.from_dynamic",
      to_dynamic,
      "generated_emitter_fixtures.to_dynamic",
    )
  let assert Ok(definition) =
    codegen.imap(codegen.int(), "dynamic.Dynamic", mapping)
  definition
}

pub fn mapped_field_definition() -> codegen.Definition(Int) {
  codegen.object(codegen.required("value", named_definition()))
}
