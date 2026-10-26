// The runtime and generated definitions refer to the same named callbacks.
import json/blueprint/codegen

@external(erlang, "generated_mapping_ffi", "reset")
@external(javascript, "./generated_mapping_ffi.mjs", "reset")
pub fn reset() -> Nil

@external(erlang, "generated_mapping_ffi", "trace")
@external(javascript, "./generated_mapping_ffi.mjs", "trace")
pub fn trace() -> String

@external(erlang, "generated_mapping_ffi", "mark")
@external(javascript, "./generated_mapping_ffi.mjs", "mark")
fn mark(label: String) -> Nil

pub fn inner_from(value: Int) -> Int {
  mark("inner_from")
  value
}

pub fn inner_to(value: Int) -> Int {
  mark("inner_to")
  value
}

pub fn outer_from(value: Int) -> Int {
  mark("outer_from")
  value
}

pub fn outer_to(value: Int) -> Int {
  mark("outer_to")
  value
}

pub fn definition() -> codegen.Definition(Int) {
  let assert Ok(inner) =
    codegen.named_mapping(
      inner_from,
      "generated_mapping_fixtures.inner_from",
      inner_to,
      "generated_mapping_fixtures.inner_to",
    )
  let assert Ok(outer) =
    codegen.named_mapping(
      outer_from,
      "generated_mapping_fixtures.outer_from",
      outer_to,
      "generated_mapping_fixtures.outer_to",
    )
  let assert Ok(first) =
    codegen.imap(codegen.integer_between(1, 10), "Int", inner)
  let assert Ok(second) = codegen.imap(first, "Int", outer)
  second
}
