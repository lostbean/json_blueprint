import gleam/option.{type Option}
import json/blueprint/codec
import json/blueprint/codegen

pub fn definition() -> codegen.Definition(Option(codec.Nullable(String))) {
  codegen.object(codegen.optional_option(
    "note",
    codegen.nullable(codegen.string()),
  ))
}
