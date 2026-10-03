# Round 5: an opaque `Schema` with a stable view

This guide moves code written against the unreleased 2.0 branch (up to
commit `74a9a7d`) to the schema model that 2.0 publishes (commit `06b8e36`). Rendered schemas
do not change: `schema_value`, `schema_document` and `schema_json` give the
same bytes for every existing codec, and the `jsonschema` 4.26.0 oracle
agrees on all 73 earlier cases and 12 new ones.

## Why

`codec.Schema` was a public union, and Relay
(`relay/src/relay/internal/schema.gleam`) and llm_wire
(`llm_wire/src/llm_wire/internal/schema.gleam`) match it exhaustively. The
docs asked for a `_` branch, but the compiler does not enforce one, so any
new schema kind after 2.0 would break both packages. That is why
`codec.value()` had no schema: an "any" variant would have broken Relay.

`Schema` is now opaque. Code that translates schemas reads them through
`codec.view`, whose variants are fixed for 2.x and include an explicit
fallback, `OtherSchema(document)`.

Other shapes were considered:

| Shape                                                   | Why not                                                                                                                                                                                                                        |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Transparent union with a documented `_` branch          | The current rule, already broken by two consumers. Nothing checks it.                                                                                                                                                          |
| A closed `kind(schema) -> Kind` classification only     | Covers Relay's root check, not llm_wire's recursive provider conversion, which needs the children and their properties.                                                                                                        |
| A fold or visitor (a record of callbacks)               | A record that callers build breaks when a callback is added, unless it is an opaque builder with an `otherwise` default. That builder is heavier than one `case`, and recursion through callbacks is awkward to read.            |
| `view` with a fallback variant (chosen)                 | One `case` per node. The compiler checks that each consumer handles every stable kind, and `OtherSchema` is the one branch that absorbs future kinds.                                                                           |

Descriptions are annotations, not kinds. `view` looks through them and
`codec.description` reads them. A future annotation such as a title gets an
accessor of its own instead of a wrapper variant that every consumer would
have to unwrap.

## Evolution policy

- `SchemaView` has these variants for every 2.x release: `StringSchema`,
  `StringEnumSchema`, `IntSchema`, `IntegerRangeSchema`, `NumberSchema`,
  `NumberRangeSchema`, `BoolSchema`, `PairSchema`, `ListSchema`,
  `NullableSchema`, `ObjectSchema`, `UnionSchema`, `AnySchema` and
  `OtherSchema`. A minor release never adds, removes or changes one.
- A schema kind added in a minor release reaches `view` as
  `OtherSchema(document)`, where `document` is that kind's JSON Schema
  object as `schema_value` renders it. A consumer written against 2.0
  keeps compiling. In that branch it decides whether to forward the
  document or refuse the schema. A minor release may also add a function
  that reads the new kind.
- A dedicated variant for a new kind is a breaking change and arrives only
  in a major release. No 2.0 schema produces `OtherSchema`.
- `PropertySchema` and `VariantSchema` may gain fields. Read their fields
  by label.

## Changed items

| Before                                                              | After                                                                                     |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `pub type Schema { DescribedSchema(..) StringSchema .. }`           | `pub opaque type Schema`; `codec.view(Schema) -> SchemaView`                              |
| `DescribedSchema(description, inner)`                               | `codec.description(Schema) -> Option(String)`; `view` returns the kind beneath it         |
| `PropertySchema(name, required, schema: Schema)` in `Schema`        | the same record in `SchemaView.ObjectSchema`; `schema` is an opaque child                 |
| `VariantSchema(tag, payload: Option(Schema))` in `Schema`           | the same record in `SchemaView.UnionSchema`                                               |
| none                                                                | `SchemaView.AnySchema`, `SchemaView.OtherSchema(document: Value)`                         |
| `codec.value()`: `schema` returns `Error(UnknownSchema)`            | `Ok` of the any schema, `{}`; records, lists and unions built from it have a schema       |
| `codec.custom(schema: Some(codec.StringSchema), ..)`                | `codec.custom(schema: option.from_result(codec.schema(codec.string())), ..)`              |
| `contract.from_schema(Schema) -> Result(Contract, DefinitionError)` | `contract.from_schema(Schema) -> Contract`                                                |
| `contract.load` of `{}` or `{"description": ..}`: `MissingKeyword("type")` | the any schema; a nested `true` is the any schema too (it was `ExpectedObject`)    |
| generated `const x_schema_value: codec.Schema = codec.ObjectSchema(..)` | `const x_schema_value: schema_tree.Tree = schema_tree.ObjectSchema(..)`, returned through `generated.schema` |

`schema`, `schema_json`, `schema_value`, `schema_document`, `describe`,
`check`, `SchemaError(UnknownSchema)` and `contract.schema` keep their
signatures and output.

### Matching a schema

```gleam
// before
fn object_root(schema: codec.Schema) -> Bool {
  case schema {
    codec.DescribedSchema(_, inner) -> object_root(inner)
    codec.ObjectSchema(_) | codec.UnionSchema(_) -> True
    _ -> False
  }
}

// after
fn object_root(schema: codec.Schema) -> Bool {
  case codec.view(schema) {
    codec.ObjectSchema(_) | codec.UnionSchema(_) -> True
    _ -> False
  }
}
```

An exhaustive match drops its `DescribedSchema` branch and gains two:

```gleam
// before
case schema {
  codec.DescribedSchema(_, inner) -> walk(inner)
  codec.ListSchema(item) | codec.NullableSchema(item) -> walk(item)
  ..
  codec.PairSchema(_, _) | codec.UnionSchema(_) | codec.NumberRangeSchema(_, _) -> False
}

// after
case codec.view(schema) {
  codec.ListSchema(item) | codec.NullableSchema(item) -> walk(item)
  ..
  codec.PairSchema(_, _) | codec.UnionSchema(_) | codec.NumberRangeSchema(_, _) -> False
  // `value()`: any JSON value, `{}`.
  codec.AnySchema -> ..
  // A kind added in a later 2.x release.
  codec.OtherSchema(_) -> False
}
```

The children (`item`, `property.schema`, `variant.payload`) are still
`codec.Schema`, so a recursive walker keeps its signature.

### Building a schema

A `Schema` comes from a codec (`codec.schema`) or a contract
(`contract.schema`, from a document through `contract.load` or
`contract.parse`). Test code that compared a codec's schema with a literal
compares it with another codec's schema or with the rendered document:

```gleam
// before
codec.schema(city_codec())
|> should.equal(Ok(codec.ObjectSchema([
  codec.PropertySchema("city", True, codec.DescribedSchema("City to look up", codec.StringSchema)),
])))

// after
codec.schema_json(city_codec())
|> should.equal(Ok(
  "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"city\":{\"description\":\"City to look up\",\"type\":\"string\"}},\"required\":[\"city\"],\"additionalProperties\":false}",
))
```

A contract for a schema known only at run time comes from its document:

```gleam
// before
let assert Ok(input) =
  contract.from_schema(
    codec.ObjectSchema([codec.PropertySchema("id", True, codec.IntSchema)]),
  )

// after
let assert Ok(input) =
  contract.parse(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\"}},\"required\":[\"id\"],\"additionalProperties\":false}",
    value.default_limits(),
  )
```

The empty object contract is `contract.from_codec(codec.success(Nil))`.

### `contract.from_schema`

Every `Schema` has already been checked: a codec's `schema` panics on a
definition mistake, and a contract checks its document when it loads. So
`from_schema` cannot fail.

```gleam
// before
case contract.from_schema(schema) {
  Ok(input_contract) -> input_contract
  Error(problem) -> panic as codec.describe_definition_error(problem)
}

// after
contract.from_schema(schema)
```

### `codec.value()` has a schema

`codec.schema(codec.value())` is the any schema, `{}`, and a codec built
from it is described too. For example, `codec.list(codec.value())` is
`{"type":"array","items":{}}`, and a record field of `value()` is `{}`.
Code that relied on `UnknownSchema` to keep a pass-through codec out of a
schema-checked path now gets a schema. Relay, for example, now admits a tool
whose input record has a `value()` field.

### Generated modules

A module generated by an earlier 2.0 build declares
`const <name>_schema_value: codec.Schema = codec.ObjectSchema(..)`, which no
longer compiles. Regenerate it with `json_blueprint_codegen`. The new module
imports `json/blueprint/internal/schema_tree`, declares the constant as a
`schema_tree.Tree` and returns `generated.schema(<name>_schema_value)` from
`<name>_schema()`. The encoders, decoders and wire output are unchanged.

## Dependents

None of these sites were edited. Line numbers are at the dependents' current
heads.

| Package        | Site                                                                       | Uses                                                                                                     | Breaks                                                                                                                                                                                                                                                                                                                                                        |
| -------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| relay          | `src/relay/internal/schema.gleam:38-45` `is_object_schema`                 | `DescribedSchema`, `ObjectSchema`, `UnionSchema` patterns                                                | compile error; match `codec.view(schema)`, drop the `DescribedSchema` branch                                                                                                                                                                                                                                                                                  |
| relay          | `src/relay/internal/schema.gleam:47-63` `schema_type_name`                 | exhaustive match on all 13 variants                                                                      | compile error; match `codec.view(schema)`, drop `DescribedSchema`, add `codec.AnySchema -> "any"` and `codec.OtherSchema(_) -> "other"`                                                                                                                                                                                                                      |
| relay          | `src/relay/tool.gleam:244`, `:256` `admit_input`, `admit_output`           | `codec.schema`, `schema.materialize_schema`                                                              | compiles; a `value()` field now has the schema `{}`, and a `value()` root input fails with `InputSchemaNotObject(name, "any")` instead of `MissingInputSchema(name)`                                                                                                                                                                                       |
| llm_wire       | `src/llm_wire/internal/schema.gleam:30-48` `provider_schema_supported`     | exhaustive match                                                                                          | compile error; match `codec.view`, drop `DescribedSchema`, add `AnySchema` (every current provider accepts `{}` in a tool's parameters) and `OtherSchema(_) -> False`                                                                                                                                                                                       |
| llm_wire       | `src/llm_wire/internal/schema.gleam:70-76` `object_root`                   | `DescribedSchema`, `ObjectSchema` patterns                                                               | compile error; match `codec.view`                                                                                                                                                                                                                                                                                                                             |
| llm_wire       | `src/llm_wire/internal/schema.gleam:83-112` `validate_strict_schema`       | exhaustive match                                                                                          | compile error; match `codec.view`; `AnySchema` and `OtherSchema(_)` join the unsupported branch, because strict mode needs a `type`                                                                                                                                                                                                                           |
| llm_wire       | `src/llm_wire/internal/schema.gleam:128-158` `validate_google_strict_schema` | exhaustive match                                                                                        | compile error; as for `validate_strict_schema`                                                                                                                                                                                                                                                                                                               |
| llm_wire       | `src/llm_wire/tool.gleam:100-109` `new`                                    | `case contract.from_schema(schema) { Ok(..) Error(..) }`                                                 | compile error; `let input_contract = contract.from_schema(schema)`, and the panic goes                                                                                                                                                                                                                                                                       |
| llm_wire       | `src/llm_wire/tool.gleam:205-214` `decode_arguments`                       | `codec.schema(input) \|> result.map(contract.from_schema)`, then `Ok(Ok(input_contract))`              | compile error; match `Ok(input_contract)`                                                                                                                                                                                                                                                                                                                    |
| llm_wire       | `src/llm_wire.gleam:289-297` `with_output`                                 | `case contract.from_schema(schema) { Ok(..) Error(..) }`                                                 | compile error; `Ok(#(schema, contract.from_schema(schema)))`                                                                                                                                                                                                                                                                                                 |
| llm_wire       | `src/llm_wire/provider.gleam:119-141`, `internal/adapter.gleam:83-191`, `internal/call.gleam:23`, `internal/tool_def.gleam:13-37`, `internal/api.gleam:91`, `tool.gleam:189` | `codec.Schema` as a type          | compiles unchanged                                                                                                                                                                                                                                                                                                                                           |
| llm_wire       | `test/llm_wire_api_test.gleam:73-75`, `:101`                               | `contract.from_schema(codec.ObjectSchema(..))`, `contract.from_schema(codec.PairSchema(..))`             | compile error; build the contract with `contract.parse` or `contract.from_codec`                                                                                                                                                                                                                                                                             |
| llm_wire       | `test/llm_wire_api_test.gleam:208-230`                                     | a list of literal schemas                                                                                | compile error; take each schema from a codec (`codec.schema(codec.list(codec.nullable(codec.string())))`, ...)                                                                                                                                                                                                                                              |
| llm_wire       | `test/llm_wire_schema_consistency_test.gleam:16-17`, `:114`, `:138-153`    | literal `ObjectSchema`, `PropertySchema`, `PairSchema`, `NullableSchema`                                 | compile error; take the schemas from codecs                                                                                                                                                                                                                                                                                                                  |
| fabric         | `src/fabric/llm.gleam:85-96` `declaration`                                 | `contract.from_schema(spec.schema) \|> result.map_error(..)` inside `result.try`                        | compile error; `let contract = contract.from_schema(spec.schema)`, and the `ModelError` branch goes                                                                                                                                                                                                                                                         |
| fabric         | `integrations/fabric_mcp/src/fabric_mcp.gleam:77` `placeholder_tool`       | `contract.from_schema(codec.ObjectSchema([]))`                                                           | compile error; `let assert Ok(empty) = contract.from_codec(codec.success(Nil))`                                                                                                                                                                                                                                                                              |
| fabric         | `test/fabric/registry_test.gleam:52-63`                                    | literal `ObjectSchema`, `PropertySchema`, `DescribedSchema`, `StringSchema`                              | compile error; compare `codec.schema_json` documents, or `codec.view` and `codec.description`                                                                                                                                                                                                                                                                |
| fabric         | `src/fabric/tool.gleam:77`, `:155`, `:190`, `:268`, `:390-394`; `src/fabric/model.gleam:49`; `src/fabric/internal/registry.gleam:54`, `:88` | `codec.Schema` and `codec.SchemaError` as types, `codec.schema` | compiles unchanged; a tool whose input has a `value()` field now has a declaration, where it had none                                                                                                                                                                                                                                                       |
| fabric         | `src/fabric/graph/llm.gleam:122`, `integrations/fabric_mcp/src/fabric_mcp.gleam:36`, `:384`, `integrations/fabric_typesafe/src/fabric_typesafe.gleam:106`, `consumers/writing/src/fabric_writing/domain.gleam:65`, `:121`, tests | `codec.custom(schema: None, ..)` | compiles unchanged                                                                                                                                                                                                                                                                                                                                           |
| relay, llm_wire, fabric | `relay/test/relay/tool_test.gleam:94`, `:106`; `llm_wire/test/llm_wire_facade_test.gleam:96`; `fabric/test/fabric/registry_test.gleam:36`, `graph_definition_test.gleam:262`, `graph_operation_test.gleam:66` | `codec.custom(schema: None, ..)` | compiles unchanged                                                                                                                                                                                                                                                                                                                         |
| oversight apps | `apps/tool_hub/src/tool_hub/remote_tools.gleam:114`                        | `codec.value()` as a Fabric tool's output codec                                                          | compiles; the output codec now has the schema `{}` instead of none                                                                                                                                                                                                                                                                                            |
| oversight apps | `apps/extractor/test/extractor_test.gleam:117`, `apps/support_desk/src/support_desk/desk.gleam:220` | `codec.schema_json`                                                                   | compiles; same bytes                                                                                                                                                                                                                                                                                                                                         |

saga, grind, warden, sinal and http_gun use no schema item. No dependent
contains a generated module.
