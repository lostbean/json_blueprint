//// Contracts loaded from Draft 2020-12 schema documents: `contract.load`,
//// `contract.parse`, document errors and their descriptions.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec.{type Codec, Field, Index}
import json/blueprint/contract
import json/blueprint/internal/schema_tree as tree
import json/blueprint/number
import json/blueprint/value.{type Value}

fn schema_of(c: Codec(a)) -> codec.Schema {
  let assert Ok(schema) = codec.schema(c)
  schema
}

const draft_2020_12 = "https://json-schema.org/draft/2020-12/schema"

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

fn int_value(n: Int) -> Value {
  value.Number(int_num(n))
}

/// Parse a document written as JSON text, with `$schema` prepended.
fn doc(members: String) -> Value {
  let text = case members {
    "" -> "{\"$schema\":\"" <> draft_2020_12 <> "\"}"
    _ -> "{\"$schema\":\"" <> draft_2020_12 <> "\"," <> members <> "}"
  }
  let assert Ok(parsed) = value.parse(text, value.default_limits())
  parsed
}

fn contract_of(c: Codec(a)) -> contract.Contract {
  let assert Ok(found) = contract.from_codec(c)
  found
}

// --- dialect and keywords ----------------------------------------------------

pub fn document_dialect_validation_test() {
  // Missing $schema
  contract.load(value.Object([#("type", value.String("string"))]))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("$schema")],
      contract.MissingKeyword("$schema"),
    )),
  )

  // Non-string $schema
  contract.load(
    value.Object([
      #("$schema", int_value(2020)),
      #("type", value.String("string")),
    ]),
  )
  |> should.equal(
    Error(contract.MalformedDocument([Field("$schema")], contract.ExpectedText)),
  )

  // Unsupported dialect
  contract.load(
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft-07/schema#")),
      #("type", value.String("string")),
    ]),
  )
  |> should.equal(
    Error(contract.UnsupportedDialect(
      [Field("$schema")],
      "https://json-schema.org/draft-07/schema#",
    )),
  )

  // Non-object root document
  contract.load(value.String("not-an-object"))
  |> should.equal(
    Error(contract.MalformedDocument([], contract.ExpectedObject)),
  )

  // Missing type: a constraint without a type. `{}` alone is the any
  // schema; see `document_any_schema_test`.
  contract.load(doc("\"minimum\":1"))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("type")],
      contract.MissingKeyword("type"),
    )),
  )
}

pub fn document_any_schema_test() {
  let any = schema_of(codec.value())
  // `{}`, `{"description": ...}` and the boolean schema `true` accept any
  // value, like `codec.value()`.
  let assert Ok(bare) = contract.load(doc(""))
  codec.view(contract.schema(bare)) |> should.equal(codec.AnySchema)
  contract.same_schema(bare, contract.from_schema(any)) |> should.equal(True)
  let assert Ok(described) = contract.load(doc("\"description\":\"anything\""))
  codec.description(contract.schema(described))
  |> should.equal(Some("anything"))
  contract.same_schema(described, bare) |> should.equal(True)
  let assert Ok(items) = contract.load(doc("\"type\":\"array\",\"items\":true"))
  let assert Ok(list_of_values) = contract.from_codec(codec.list(codec.value()))
  contract.same_schema(items, list_of_values) |> should.equal(True)
  // A loaded `true` renders as `{}`, as codecs write it.
  codec.schema_value(contract.schema(items))
  |> value.to_string
  |> should.equal("{\"type\":\"array\",\"items\":{}}")

  // Every value validates, and a field of any schema decodes with `value()`.
  list.each(
    [
      value.Null,
      value.Bool(True),
      int_value(1),
      value.String("x"),
      value.Array([value.Null]),
      value.Object([#("a", value.Null)]),
    ],
    fn(item) {
      let assert Ok(validated) = contract.validate(bare, item)
      contract.decode(codec.value(), validated) |> should.equal(Ok(item))
    },
  )
  let assert Ok(envelope) =
    contract.load(doc(
      "\"type\":\"object\",\"properties\":{\"body\":{}},"
      <> "\"required\":[\"body\"],\"additionalProperties\":false",
    ))
  let body = {
    use body <- codec.field("body", codec.value(), get: fn(b) { b })
    codec.success(body)
  }
  let raw = value.Object([#("body", value.Array([int_value(2)]))])
  let assert Ok(validated) = contract.validate(envelope, raw)
  contract.decode(body, validated)
  |> should.equal(Ok(value.Array([int_value(2)])))
  contract.validate(envelope, value.Object([]))
  |> should.equal(
    Error(contract.ValidationError([Field("body")], codec.MissingField)),
  )

  // `false` stays outside the profile.
  contract.load(doc("\"type\":\"array\",\"items\":false"))
  |> should.equal(
    Error(contract.MalformedDocument([Field("items")], contract.ExpectedObject)),
  )
  // A nested `$schema` is still refused inside an otherwise empty schema.
  contract.load(doc(
    "\"type\":\"array\",\"items\":{\"$schema\":\"" <> draft_2020_12 <> "\"}",
  ))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [Field("items"), Field("$schema")],
      contract.NestedDialect,
    )),
  )
}

pub fn document_unsupported_keywords_test() {
  // Unknown keyword at root
  contract.load(doc("\"type\":\"string\",\"pattern\":\"^[a-z]+$\""))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [Field("pattern")],
      contract.UnsupportedKeyword("pattern"),
    )),
  )

  // Unknown keyword in a nested property
  contract.load(doc(
    "\"type\":\"object\",\"properties\":{\"age\":{\"type\":\"integer\",\"format\":\"int32\"}},"
    <> "\"required\":[],\"additionalProperties\":false",
  ))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [Field("properties"), Field("age"), Field("format")],
      contract.UnsupportedKeyword("format"),
    )),
  )

  // Open object (additionalProperties: true)
  contract.load(doc(
    "\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":true",
  ))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [Field("additionalProperties")],
      contract.OpenObject,
    )),
  )

  // Untagged unions and unbounded arrays
  contract.load(doc("\"anyOf\":[{\"type\":\"string\"},{\"type\":\"integer\"}]"))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [Field("anyOf")],
      contract.ArbitraryUnion,
    )),
  )
  contract.load(doc("\"type\":\"array\""))
  |> should.equal(
    Error(contract.UnsupportedDocument([], contract.UnboundedArray)),
  )
}

pub fn document_description_must_be_text_test() {
  contract.load(doc("\"description\":true,\"type\":\"string\""))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("description")],
      contract.ExpectedText,
    )),
  )
}

pub fn document_duplicate_keys_test() {
  // A document value built by hand may repeat a key; `load` refuses it
  contract.load(
    value.Object([
      #("$schema", value.String(draft_2020_12)),
      #("type", value.String("object")),
      #(
        "properties",
        value.Object([
          #("a", value.Object([#("type", value.String("string"))])),
          #("a", value.Object([#("type", value.String("integer"))])),
        ]),
      ),
      #("required", value.Array([])),
      #("additionalProperties", value.Bool(False)),
    ]),
  )
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("properties"), Field("a")],
      contract.DuplicateKey("a"),
    )),
  )
}

// --- definition mistakes -----------------------------------------------------

pub fn document_invalid_definition_paths_test() {
  // Reversed integer range at the root
  contract.load(doc("\"type\":\"integer\",\"minimum\":10,\"maximum\":5"))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [Field("minimum")],
      codec.ReversedIntegerBounds(10, 5),
    )),
  )

  // Reversed number range
  let assert Ok(high) = number.parse("2.5", number.default_limits())
  let assert Ok(low) = number.parse("1.5", number.default_limits())
  contract.load(doc("\"type\":\"number\",\"minimum\":2.5,\"maximum\":1.5"))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [Field("minimum")],
      codec.ReversedNumberBounds(high, low),
    )),
  )

  // Nested in a property
  contract.load(doc(
    "\"type\":\"object\",\"properties\":{\"limit\":{\"type\":\"integer\",\"minimum\":10,\"maximum\":5}},"
    <> "\"required\":[\"limit\"],\"additionalProperties\":false",
  ))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [Field("properties"), Field("limit"), Field("minimum")],
      codec.ReversedIntegerBounds(10, 5),
    )),
  )

  // Empty enum, inside a nullable
  contract.load(doc(
    "\"anyOf\":[{\"type\":\"null\"},{\"type\":\"string\",\"enum\":[]}]",
  ))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [Field("anyOf"), Index(1), Field("enum")],
      codec.EmptyEnum,
    )),
  )

  // Repeated enum label, inside list items: the path names the repeat
  contract.load(doc(
    "\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"a\",\"b\",\"a\"]}",
  ))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [Field("items"), Field("enum"), Index(2)],
      codec.DuplicateEnumLabel("a"),
    )),
  )

  // Repeated union tag: the path names the second variant's tag
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":["
    <> unit_variant("same")
    <> ","
    <> payload_variant("same", "{\"type\":\"string\"}")
    <> "]",
  ))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [
        Field("oneOf"),
        Index(1),
        Field("properties"),
        Field("tag"),
        Field("const"),
      ],
      codec.DuplicateTag("same"),
    )),
  )

  // Nested in a union payload
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":["
    <> payload_variant(
      "count",
      "{\"type\":\"integer\",\"minimum\":3,\"maximum\":1}",
    )
    <> "]",
  ))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [
        Field("oneOf"),
        Index(0),
        Field("properties"),
        Field("value"),
        Field("minimum"),
      ],
      codec.ReversedIntegerBounds(3, 1),
    )),
  )

  // Nested in a pair
  contract.load(doc(
    "\"type\":\"array\",\"prefixItems\":[{\"type\":\"string\"},{\"type\":\"string\",\"enum\":[]}],"
    <> "\"minItems\":2,\"maxItems\":2",
  ))
  |> should.equal(
    Error(contract.InvalidDefinition(
      [Field("prefixItems"), Index(1), Field("enum")],
      codec.EmptyEnum,
    )),
  )
}

// --- round trips -------------------------------------------------------------

pub type Shape {
  Circle(radius: Int)
  Square(side: Int)
  Label(text: Option(String))
  Empty
  Unknown
}

fn shape_codec() -> Codec(Shape) {
  codec.union({
    use circle <- codec.variant("circle", codec.int(), Circle)
    use square <- codec.variant("square", codec.integer_between(1, 10), Square)
    use label <- codec.variant("label", codec.nullable(codec.string()), Label)
    use empty <- codec.unit_variant("empty", Empty)
    use unknown <- codec.unit_variant("unknown", Unknown)
    codec.match(fn(shape) {
      case shape {
        Circle(radius) -> circle(radius)
        Square(side) -> square(side)
        Label(text) -> label(text)
        Empty -> empty
        Unknown -> unknown
      }
    })
  })
}

fn record_codec() -> Codec(#(Int, Option(String))) {
  use id <- codec.field("id", codec.int(), get: fn(r) { r.0 })
  use name <- codec.optional_field("name", codec.string(), get: fn(r) { r.1 })
  codec.success(#(id, name))
}

fn assert_round_trip(c: Codec(a)) -> Nil {
  let assert Ok(schema) = codec.schema(c)
  let assert Ok(loaded) = contract.load(codec.schema_document(schema))
  contract.same_schema(loaded, contract_of(c)) |> should.equal(True)
  contract.schema(loaded) |> should.equal(contract.schema(contract_of(c)))
  // The normalized schema loads back to itself
  let assert Ok(again) =
    contract.load(codec.schema_document(contract.schema(loaded)))
  contract.schema(again) |> should.equal(contract.schema(loaded))
}

pub fn document_load_roundtrips_test() {
  // String
  let assert Ok(str_schema) = codec.schema(codec.string())
  let str_doc = codec.schema_document(str_schema)
  let assert Ok(str_contract) = contract.load(str_doc)
  let expected_str_contract = contract.from_schema(str_schema)
  contract.same_schema(str_contract, expected_str_contract)
  |> should.equal(True)

  // Integer range
  let assert Ok(range_schema) = codec.schema(codec.integer_between(-10, 10))
  let int_range_doc = codec.schema_document(range_schema)
  let assert Ok(int_range_contract) = contract.load(int_range_doc)
  let expected_range_contract = contract.from_schema(range_schema)
  contract.same_schema(int_range_contract, expected_range_contract)
  |> should.equal(True)

  // Object with optional and required fields
  assert_round_trip(record_codec())

  // N-ary union with payload and unit variants
  assert_round_trip(shape_codec())

  // Every other shape of the profile
  assert_round_trip(codec.pair(codec.bool(), codec.number()))
  assert_round_trip(codec.list(codec.nullable(codec.float())))
  assert_round_trip(codec.number_between(int_num(-1), int_num(1)))
  assert_round_trip(codec.string_enum([#("b", 2), #("a", 1)]))
  assert_round_trip(codec.success(Nil))
  assert_round_trip(codec.describe(codec.list(shape_codec()), "Shapes"))
}

pub fn document_load_unit_variants_test() {
  // A hand-written union: two unit variants and one with a payload
  let assert Ok(loaded) =
    contract.load(doc(
      "\"type\":\"object\",\"oneOf\":["
      <> unit_variant("on")
      <> ","
      <> payload_variant(
        "level",
        "{\"type\":\"integer\",\"minimum\":0,\"maximum\":9}",
      )
      <> ","
      <> unit_variant("off")
      <> "]",
    ))
  codec.to_tree(contract.schema(loaded))
  |> should.equal(
    tree.UnionSchema([
      tree.VariantSchema("level", Some(tree.IntegerRangeSchema(0, 9))),
      tree.VariantSchema("off", None),
      tree.VariantSchema("on", None),
    ]),
  )

  let accepted = [
    "{\"tag\":\"on\"}",
    "{\"tag\":\"off\"}",
    "{\"tag\":\"level\",\"value\":9}",
  ]
  list.each(accepted, fn(text) {
    let assert Ok(raw) = value.parse(text, value.default_limits())
    contract.validate(loaded, raw) |> should.be_ok
  })

  let rejected = [
    #("{\"tag\":\"on\",\"value\":1}", [Field("value")], codec.UnknownField),
    #("{\"tag\":\"level\"}", [Field("value")], codec.MissingField),
    #(
      "{\"tag\":\"level\",\"value\":10}",
      [Field("value")],
      codec.IntegerOutsideRange(0, 9),
    ),
    #("{\"tag\":\"dim\"}", [Field("tag")], codec.UnknownTag),
    #("{\"value\":1}", [Field("tag")], codec.MissingField),
    #("{\"tag\":null}", [Field("tag")], codec.ExpectedString),
  ]
  list.each(rejected, fn(item) {
    let #(text, path, reason) = item
    let assert Ok(raw) = value.parse(text, value.default_limits())
    contract.validate(loaded, raw)
    |> should.equal(Error(contract.ValidationError(path, reason)))
  })

  // A codec with the same variants decodes the validated values
  let switch =
    codec.union({
      use level <- codec.variant("level", codec.integer_between(0, 9), fn(n) {
        Some(n)
      })
      use on <- codec.unit_variant("on", Some(-1))
      use off <- codec.unit_variant("off", None)
      codec.match(fn(state) {
        case state {
          Some(-1) -> on
          Some(n) -> level(n)
          None -> off
        }
      })
    })
  contract.same_schema(loaded, contract_of(switch)) |> should.equal(True)
  let assert Ok(raw) = value.parse("{\"tag\":\"on\"}", value.default_limits())
  let assert Ok(validated) = contract.validate(loaded, raw)
  contract.decode(switch, validated) |> should.equal(Ok(Some(-1)))
}

pub fn document_union_shape_errors_test() {
  // No alternatives
  contract.load(doc("\"type\":\"object\",\"oneOf\":[]"))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("oneOf")],
      contract.InvalidTaggedAlternatives,
    )),
  )

  // oneOf that is not an array
  contract.load(doc("\"type\":\"object\",\"oneOf\":{}"))
  |> should.equal(
    Error(contract.MalformedDocument([Field("oneOf")], contract.ExpectedArray)),
  )

  // A unit variant must require its tag
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"a\"}},"
    <> "\"required\":[],\"additionalProperties\":false}]",
  ))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("oneOf"), Index(0), Field("required")],
      contract.InvalidTaggedAlternatives,
    )),
  )

  // A payload variant must require tag and value
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"a\"},"
    <> "\"value\":{\"type\":\"string\"}},\"required\":[\"tag\"],\"additionalProperties\":false}]",
  ))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("oneOf"), Index(0), Field("required")],
      contract.InvalidTaggedAlternatives,
    )),
  )

  // A variant without a tag
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"}},"
    <> "\"required\":[\"value\"],\"additionalProperties\":false}]",
  ))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("oneOf"), Index(0), Field("properties")],
      contract.ExpectedClosedTag,
    )),
  )

  // A variant with a property other than tag and value
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"a\"},"
    <> "\"extra\":{\"type\":\"string\"}},\"required\":[\"tag\"],\"additionalProperties\":false}]",
  ))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [Field("oneOf"), Index(0)],
      contract.UnsupportedTaggedShape,
    )),
  )

  // A tag that is not a const string
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"type\":\"string\"}},"
    <> "\"required\":[\"tag\"],\"additionalProperties\":false}]",
  ))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [
        Field("oneOf"),
        Index(0),
        Field("properties"),
        Field("tag"),
        Field("type"),
      ],
      contract.UnsupportedKeyword("type"),
    )),
  )
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":1}},"
    <> "\"required\":[\"tag\"],\"additionalProperties\":false}]",
  ))
  |> should.equal(
    Error(contract.MalformedDocument(
      [
        Field("oneOf"),
        Index(0),
        Field("properties"),
        Field("tag"),
        Field("const"),
      ],
      contract.ExpectedText,
    )),
  )

  // A variant that is not an object schema
  contract.load(doc("\"type\":\"object\",\"oneOf\":[{\"type\":\"string\"}]"))
  |> should.equal(
    Error(contract.MalformedDocument(
      [Field("oneOf"), Index(0), Field("type")],
      contract.ExpectedObjectSchema,
    )),
  )

  // An open variant
  contract.load(doc(
    "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"a\"}},"
    <> "\"required\":[\"tag\"],\"additionalProperties\":true}]",
  ))
  |> should.equal(
    Error(contract.UnsupportedDocument(
      [Field("oneOf"), Index(0), Field("additionalProperties")],
      contract.OpenObject,
    )),
  )
}

fn unit_variant(tag: String) -> String {
  "{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\""
  <> tag
  <> "\"}},\"required\":[\"tag\"],\"additionalProperties\":false}"
}

fn payload_variant(tag: String, payload: String) -> String {
  "{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\""
  <> tag
  <> "\"},\"value\":"
  <> payload
  <> "},\"required\":[\"tag\",\"value\"],\"additionalProperties\":false}"
}

// --- parse -------------------------------------------------------------------

pub fn parse_schema_text_test() {
  let text =
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
    <> "\"type\":\"array\",\"items\":{\"type\":\"string\"}}"
  let assert Ok(remote) = contract.parse(text, value.default_limits())
  codec.view(contract.schema(remote))
  |> should.equal(codec.ListSchema(schema_of(codec.string())))
  let assert Ok(parsed) = value.parse("[\"a\"]", value.default_limits())
  let assert Ok(validated) = contract.validate(remote, parsed)
  contract.decode(codec.list(codec.string()), validated)
  |> should.equal(Ok(["a"]))

  // The text of a codec's schema parses back to the same contract
  let assert Ok(shape_text) = codec.schema_json(shape_codec())
  let assert Ok(shapes) = contract.parse(shape_text, value.default_limits())
  contract.same_schema(shapes, contract_of(shape_codec())) |> should.equal(True)
}

pub fn parse_schema_text_errors_test() {
  // Invalid JSON
  case contract.parse("{\"$schema\":", value.default_limits()) {
    Error(contract.InvalidJson(value.ParseError(_, value.UnexpectedEndOfInput))) ->
      Nil
    other -> panic as { "expected end of input, got " <> string.inspect(other) }
  }

  // Duplicate keys are a parse error, not a document error
  case
    contract.parse(
      "{\"$schema\":\""
        <> draft_2020_12
        <> "\",\"type\":\"string\",\"type\":\"integer\"}",
      value.default_limits(),
    )
  {
    Error(contract.InvalidJson(value.ParseError(_, value.DuplicateObjectKey))) ->
      Nil
    other ->
      panic as { "expected duplicate key, got " <> string.inspect(other) }
  }

  // A well-formed document outside the profile
  contract.parse(
    "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"type\":\"string\"}",
    value.default_limits(),
  )
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.UnsupportedDialect(
        [Field("$schema")],
        "http://json-schema.org/draft-07/schema#",
      )),
    ),
  )
  contract.parse(
    "{\"$schema\":\""
      <> draft_2020_12
      <> "\",\"type\":\"integer\",\"minimum\":2,\"maximum\":1}",
    value.default_limits(),
  )
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.InvalidDefinition(
        [Field("minimum")],
        codec.ReversedIntegerBounds(2, 1),
      )),
    ),
  )

  // The limits bound the text
  let text = "{\"$schema\":\"" <> draft_2020_12 <> "\",\"type\":\"string\"}"
  contract.parse(text, value.default_limits()) |> should.be_ok
  case
    contract.parse(text, value.default_limits() |> value.with_max_bytes(10))
  {
    Error(contract.InvalidJson(value.ParseError(_, value.ByteLimitExceeded(10)))) ->
      Nil
    other -> panic as { "expected byte limit, got " <> string.inspect(other) }
  }
  let nested =
    "{\"$schema\":\""
    <> draft_2020_12
    <> "\",\"type\":\"array\",\"items\":"
    <> "{\"type\":\"array\",\"items\":{\"type\":\"string\"}}}"
  contract.parse(nested, value.default_limits()) |> should.be_ok
  case
    contract.parse(nested, value.default_limits() |> value.with_max_depth(2))
  {
    Error(contract.InvalidJson(value.ParseError(_, value.DepthLimitExceeded(2)))) ->
      Nil
    other -> panic as { "expected depth limit, got " <> string.inspect(other) }
  }
}

// --- describe ----------------------------------------------------------------

pub fn describe_document_error_test() {
  let describe = fn(document: Value) {
    let assert Error(error) = contract.load(document)
    contract.describe_document_error(error)
  }

  describe(doc(
    "\"type\":\"object\",\"properties\":{\"age\":{\"type\":\"integer\",\"format\":\"int32\"}},"
    <> "\"required\":[],\"additionalProperties\":false",
  ))
  |> should.equal(
    "$[\"properties\"][\"age\"][\"format\"]: unsupported keyword \"format\"",
  )

  describe(value.Object([#("type", value.String("string"))]))
  |> should.equal("$[\"$schema\"]: missing keyword \"$schema\"")

  describe(doc("\"type\":\"integer\",\"minimum\":10,\"maximum\":5"))
  |> should.equal("$[\"minimum\"]: integer bounds 10 to 5 are reversed")

  describe(doc(
    "\"type\":\"object\",\"oneOf\":["
    <> unit_variant("a")
    <> ","
    <> unit_variant("a")
    <> "]",
  ))
  |> should.equal(
    "$[\"oneOf\"][1][\"properties\"][\"tag\"][\"const\"]: union tag \"a\" appears twice",
  )

  describe(doc("\"type\":\"array\""))
  |> should.equal("$: array without items")

  describe(
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft-07/schema#")),
    ]),
  )
  |> should.equal(
    "$[\"$schema\"]: unsupported dialect \"https://json-schema.org/draft-07/schema#\"",
  )
}

pub fn describe_document_error_omits_document_values_test() {
  // Values of keywords, such as descriptions, malformed items and constants,
  // never appear in the text
  let cases = [
    #(
      doc(
        "\"description\":\"top-secret\",\"type\":\"string\",\"pattern\":\"x\"",
      ),
      "$[\"pattern\"]: unsupported keyword \"pattern\"",
      "top-secret",
    ),
    #(
      doc("\"type\":\"string\",\"enum\":[\"ok\",123456789]"),
      "$[\"enum\"][1]: expected a string",
      "123456789",
    ),
    #(
      doc("\"description\":8675309,\"type\":\"string\""),
      "$[\"description\"]: expected a string",
      "8675309",
    ),
    #(
      doc(
        "\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":424242}},"
        <> "\"required\":[\"tag\"],\"additionalProperties\":false}]",
      ),
      "$[\"oneOf\"][0][\"properties\"][\"tag\"][\"const\"]: expected a string",
      "424242",
    ),
    #(
      doc("\"type\":\"integer\",\"minimum\":1.5,\"maximum\":3"),
      "$[\"minimum\"]: expected an integer",
      "1.5",
    ),
    #(
      doc("\"type\":\"secret-kind\""),
      "$: unsupported schema form",
      "secret-kind",
    ),
  ]
  list.each(cases, fn(item) {
    let #(document, expected, secret) = item
    let assert Error(error) = contract.load(document)
    let text = contract.describe_document_error(error)
    text |> should.equal(expected)
    string.contains(text, secret) |> should.be_false
  })
}

pub fn describe_load_error_test() {
  // A parse error renders without the input text
  let assert Error(error) =
    contract.parse("{\"secret-token\": tru", value.default_limits())
  let text = contract.describe_load_error(error)
  string.starts_with(text, "invalid JSON at line 1, column ") |> should.be_true
  string.contains(text, "secret-token") |> should.be_false

  // A document error renders as `describe_document_error` does
  let assert Error(error) =
    contract.parse(
      "{\"$schema\":\"" <> draft_2020_12 <> "\",\"type\":\"array\"}",
      value.default_limits(),
    )
  let assert contract.InvalidDocument(document_error) = error
  contract.describe_load_error(error)
  |> should.equal(contract.describe_document_error(document_error))
  contract.describe_load_error(error) |> should.equal("$: array without items")
}
