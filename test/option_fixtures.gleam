import gleam/option.{type Option}
import json/blueprint/codegen

/// An object whose only property is optional and nullable: absent, `null`
/// and a string are `None`, `Some(None)` and `Some(Some(text))`.
pub fn definition() -> codegen.Definition(Option(Option(String))) {
  codegen.object(codegen.optional("note", codegen.nullable(codegen.string())))
}
