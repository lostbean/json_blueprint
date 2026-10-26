import json/blueprint/codegen

pub const wire_name = "quote\"\u{301} slash\\\u{301} control\u{0}"

pub fn definition() -> codegen.Definition(String) {
  codegen.object(codegen.required(wire_name, codegen.string()))
  |> codegen.describe(wire_name)
}
