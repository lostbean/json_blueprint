@target(erlang)
import gleeunit/should
@target(erlang)
import json/blueprint/codec
@target(erlang)
import json/blueprint/document
@target(erlang)
import json/blueprint/number
@target(erlang)
import json/blueprint/runtime
@target(erlang)
import json/blueprint/value

@target(erlang)
const draft_2020_12 = "https://json-schema.org/draft/2020-12/schema"

@target(erlang)
pub fn document_dialect_validation_test() {
  // Missing $schema
  document.load(value.Object([#("type", value.String("string"))]))
  |> should.equal(
    Error(document.MalformedDocument(
      [document.Property("$schema")],
      document.MissingField("$schema"),
    )),
  )

  // Non-string $schema
  document.load(
    value.Object([
      #("$schema", value.Number(number.from_int(2020))),
      #("type", value.String("string")),
    ]),
  )
  |> should.equal(
    Error(document.MalformedDocument(
      [document.Property("$schema")],
      document.ExpectedText,
    )),
  )

  // Unsupported dialect
  document.load(
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft-07/schema#")),
      #("type", value.String("string")),
    ]),
  )
  |> should.equal(
    Error(document.UnsupportedDialect(
      [document.Property("$schema")],
      "https://json-schema.org/draft-07/schema#",
    )),
  )

  // Non-object root document
  document.load(value.String("not-an-object"))
  |> should.equal(
    Error(document.MalformedDocument([], document.ExpectedObject)),
  )
}

@target(erlang)
pub fn document_unsupported_keywords_test() {
  // Unknown keyword at root
  document.load(
    value.Object([
      #("$schema", value.String(draft_2020_12)),
      #("type", value.String("string")),
      #("pattern", value.String("^[a-z]+$")),
    ]),
  )
  |> should.equal(
    Error(document.UnsupportedDocument(
      [document.Property("pattern")],
      document.UnsupportedKeyword("pattern"),
    )),
  )

  // Open object (additionalProperties: true)
  document.load(
    value.Object([
      #("$schema", value.String(draft_2020_12)),
      #("type", value.String("object")),
      #("properties", value.Object([])),
      #("required", value.Array([])),
      #("additionalProperties", value.Bool(True)),
    ]),
  )
  |> should.equal(
    Error(document.UnsupportedDocument(
      [document.Property("additionalProperties")],
      document.OpenObject,
    )),
  )
}

@target(erlang)
pub fn document_schema_invariants_test() {
  // Reversed integer range in document
  document.load(
    value.Object([
      #("$schema", value.String(draft_2020_12)),
      #("type", value.String("integer")),
      #("minimum", value.Number(number.from_int(10))),
      #("maximum", value.Number(number.from_int(5))),
    ]),
  )
  |> should.equal(
    Error(document.SchemaInvariant(
      [document.Property("minimum")],
      runtime.ReversedIntegerRange(10, 5),
    )),
  )
}

@target(erlang)
pub fn document_load_roundtrips_test() {
  // String
  let str_doc = codec.schema_document(codec.StringSchema)
  let assert Ok(str_contract) = document.load(str_doc)
  let assert Ok(expected_str_contract) = runtime.from_schema(codec.StringSchema)
  runtime.same_schema(str_contract, expected_str_contract)
  |> should.equal(True)

  // Integer range
  let int_range_doc = codec.schema_document(codec.IntegerRangeSchema(-10, 10))
  let assert Ok(int_range_contract) = document.load(int_range_doc)
  let assert Ok(expected_range_contract) =
    runtime.from_schema(codec.IntegerRangeSchema(-10, 10))
  runtime.same_schema(int_range_contract, expected_range_contract)
  |> should.equal(True)

  // Object with optional and required fields
  let assert Ok(props) =
    codec.combine(
      codec.required("id", codec.int()),
      codec.optional("name", codec.string()),
    )
  let obj_codec = codec.object(props)
  let assert Ok(obj_schema) = codec.schema(obj_codec)
  let obj_doc = codec.schema_document(obj_schema)

  let assert Ok(loaded_contract) = document.load(obj_doc)
  let assert Ok(expected_contract) = runtime.from_codec(obj_codec)
  runtime.same_schema(loaded_contract, expected_contract)
  |> should.equal(True)

  // Tagged union
  let assert Ok(tagged_codec) =
    codec.tagged("ok", codec.int(), "err", codec.string())
  let assert Ok(tagged_schema) = codec.schema(tagged_codec)
  let tagged_doc = codec.schema_document(tagged_schema)

  let assert Ok(loaded_tagged_contract) = document.load(tagged_doc)
  let assert Ok(expected_tagged_contract) = runtime.from_codec(tagged_codec)
  runtime.same_schema(loaded_tagged_contract, expected_tagged_contract)
  |> should.equal(True)
}
