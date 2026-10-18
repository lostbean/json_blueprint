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

import examples/record
import examples/unions
import json/blueprint/codec.{type Codec}

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

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  assert object_root(record.user_codec())
  assert object_root(unions.shape_codec())
  assert object_root(codec.describe(record.user_codec(), "A user"))
  assert !object_root(codec.list(record.user_codec()))
  assert !object_root(codec.value())
  "records and unions have an object root; lists and raw values do not"
}
