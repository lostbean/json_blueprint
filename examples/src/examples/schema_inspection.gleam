//// Reading a schema.
////
//// `codec.schema` returns an opaque `Schema`. `schema_value` and
//// `schema_document` render it; code that translates schemas, such as a tool
//// server or an LLM provider adapter, reads it with `codec.view`, which gives
//// the kind at the root, and `codec.description`. A description is not a kind:
//// `view` looks through it and `description` reads it.
////
//// The variants of `SchemaView` are fixed for every 2.x release. A schema
//// kind added in a minor release reaches `view` as `OtherSchema(document)`,
//// with the kind's JSON Schema object, so code written against 2.0 keeps
//// compiling and decides in that branch whether to forward the document or
//// refuse the schema.
////
//// A schema is never built by hand. `codec.map_enum_labels` derives one with
//// other labels in its string enumerations, and `codec.map_descriptions` one
//// with other descriptions; both keep the structure.

import examples/record
import examples/unions
import gleam/int
import gleam/list
import gleam/result
import json/blueprint/codec.{type Codec, type DefinitionError, type Schema}

/// Whether a tool's input schema has an object root, as MCP requires.
pub fn object_root(input: Codec(a)) -> Bool {
  case codec.schema(input) {
    Error(codec.UnknownSchema) -> False
    Ok(schema) ->
      case codec.view(schema) {
        codec.ObjectSchema(_) | codec.UnionSchema(_) -> True
        _ -> False
      }
  }
}

/// The schema of a choice among `ids`, published under labels that do not
/// change between runs: `ticket-1`, `ticket-2` and so on in the order given.
/// `ids` must be distinct and not empty.
pub fn stable_choice(ids: List(String)) -> Result(Schema, DefinitionError) {
  let choice = codec.string_enum(list.map(ids, fn(id) { #(id, id) }))
  use choice <- result.try(codec.check(choice))
  let assert Ok(schema) = codec.schema(choice)
  let stand_ins =
    list.index_map(ids, fn(id, index) {
      #(id, "ticket-" <> int.to_string(index + 1))
    })
  codec.map_enum_labels(schema, fn(id) {
    list.key_find(stand_ins, id) |> result.unwrap(id)
  })
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  assert object_root(record.user_codec())
  assert object_root(unions.shape_codec())
  assert object_root(codec.describe(record.user_codec(), "A user"))
  assert !object_root(codec.list(record.user_codec()))
  assert !object_root(codec.value())
  let assert Ok(stable) = stable_choice(["7f3a", "c210"])
  assert codec.view(stable) == codec.StringEnumSchema(["ticket-1", "ticket-2"])
  // Two labels of one enumeration may not become the same string.
  let assert Ok(schema) =
    codec.schema(codec.string_enum([#("a", 1), #("b", 2)]))
  assert codec.map_enum_labels(schema, fn(_) { "same" })
    == Error(codec.DuplicateEnumLabel("same"))
  "records and unions have an object root; lists and raw values do not"
}
