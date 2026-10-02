import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/internal/schema_materialize.{
  DuplicateAccessor, InvalidAccessorName, SchemaExport, UnknownSchema,
  UnsupportedConstructor,
}
import materialize_fixtures
import schema_materialization_runner

pub fn validate_module_path_valid_test() {
  schema_materialize.validate_module_path("generated/schema_catalog")
  |> should.equal(Ok("generated/schema_catalog"))

  schema_materialize.validate_module_path("catalog")
  |> should.equal(Ok("catalog"))

  schema_materialize.validate_module_path("my_pkg/sub_mod/schema")
  |> should.equal(Ok("my_pkg/sub_mod/schema"))
}

pub fn validate_module_path_invalid_test() {
  schema_materialize.validate_module_path("")
  |> should.be_error

  schema_materialize.validate_module_path("/leading_slash")
  |> should.be_error

  schema_materialize.validate_module_path("trailing_slash/")
  |> should.be_error

  schema_materialize.validate_module_path("double//slash")
  |> should.be_error

  schema_materialize.validate_module_path("Upper/catalog")
  |> should.be_error

  schema_materialize.validate_module_path("hyphen-name/catalog")
  |> should.be_error

  schema_materialize.validate_module_path("generated/type")
  |> should.be_error

  schema_materialize.validate_module_path("import/catalog")
  |> should.be_error

  schema_materialize.validate_module_path("generated/else")
  |> should.be_error

  schema_materialize.validate_module_path("else/catalog")
  |> should.be_error
}

pub fn validate_accessor_name_valid_test() {
  schema_materialize.validate_accessor_name("order_schema")
  |> should.equal(Ok("order_schema"))

  schema_materialize.validate_accessor_name("decision_schema")
  |> should.equal(Ok("decision_schema"))

  schema_materialize.validate_accessor_name("item_123")
  |> should.equal(Ok("item_123"))

  schema_materialize.validate_accessor_name("a")
  |> should.equal(Ok("a"))
}

pub fn validate_accessor_name_invalid_test() {
  schema_materialize.validate_accessor_name("")
  |> should.be_error

  schema_materialize.validate_accessor_name("OrderSchema")
  |> should.be_error

  schema_materialize.validate_accessor_name("123item")
  |> should.be_error

  schema_materialize.validate_accessor_name("order-schema")
  |> should.be_error

  schema_materialize.validate_accessor_name("order.schema")
  |> should.be_error

  // Explicit test for "else"
  schema_materialize.validate_accessor_name("else")
  |> should.equal(
    Error(InvalidAccessorName("else", "accessor name cannot be a keyword")),
  )

  // All Gleam keywords including else and auto
  let keywords = [
    "as", "assert", "auto", "case", "const", "echo", "else", "external", "fn",
    "if", "import", "let", "opaque", "panic", "pub", "todo", "try", "type",
    "use",
  ]
  let assert True =
    keywords
    |> list_all(fn(kw) {
      case schema_materialize.validate_accessor_name(kw) {
        Error(InvalidAccessorName(name, _)) -> name == kw
        _ -> False
      }
    })
}

fn list_all(items: List(a), predicate: fn(a) -> Bool) -> Bool {
  case items {
    [] -> True
    [first, ..rest] ->
      case predicate(first) {
        True -> list_all(rest, predicate)
        False -> False
      }
  }
}

pub fn direct_export_invalid_name_bypass_rejected_test() {
  let order_c = materialize_fixtures.build_order_codec()
  let assert Ok(s) = codec.schema(order_c)

  // Direct injection attempt bypassing from_codec
  let injection_export = SchemaExport("injected() {\n}\nfn hacked", s)
  schema_materialize.materialize("generated/catalog", [injection_export])
  |> should.be_error

  // Direct keyword bypass attempt: "else"
  let keyword_else_export = SchemaExport("else", s)
  schema_materialize.materialize("generated/catalog", [keyword_else_export])
  |> should.equal(
    Error(InvalidAccessorName("else", "accessor name cannot be a keyword")),
  )

  // Direct keyword bypass attempt: "type"
  let keyword_type_export = SchemaExport("type", s)
  schema_materialize.materialize("generated/catalog", [keyword_type_export])
  |> should.equal(
    Error(InvalidAccessorName("type", "accessor name cannot be a keyword")),
  )

  // Direct empty name bypass attempt
  let empty_export = SchemaExport("", s)
  schema_materialize.materialize("generated/catalog", [empty_export])
  |> should.equal(
    Error(InvalidAccessorName("", "accessor name cannot be empty")),
  )

  // Direct non-identifier syntax bypass attempts
  let hyphen_export = SchemaExport("bad-name", s)
  schema_materialize.materialize("generated/catalog", [hyphen_export])
  |> should.be_error

  let digit_export = SchemaExport("123bad", s)
  schema_materialize.materialize("generated/catalog", [digit_export])
  |> should.be_error

  let capital_export = SchemaExport("BadCapital", s)
  schema_materialize.materialize("generated/catalog", [capital_export])
  |> should.be_error
}

pub fn duplicate_accessor_rejected_test() {
  let order_c = materialize_fixtures.build_order_codec()
  let assert Ok(s) = codec.schema(order_c)

  let exports = [
    SchemaExport("order_schema", s),
    SchemaExport("order_schema", s),
  ]

  schema_materialize.materialize("generated/catalog", exports)
  |> should.equal(Error(DuplicateAccessor("order_schema")))
}

pub fn unknown_schema_from_codec_test() {
  let unknown_c = materialize_fixtures.build_custom_unknown_codec()

  schema_materialize.from_codec("custom_unknown", unknown_c)
  |> should.equal(Error(UnknownSchema("custom_unknown")))
}

pub fn described_schema_expression_preserves_escaped_text_test() {
  schema_materialize.emit_schema_expression(
    codec.DescribedSchema("owner's \"name\"", codec.StringSchema),
    ["name"],
  )
  |> should.equal(Ok(
    "codec.DescribedSchema(\"owner's \\\"name\\\"\", codec.StringSchema)",
  ))
}

pub fn unsupported_number_range_schema_located_test() {
  let range_c = materialize_fixtures.build_number_range_codec()
  let assert Ok(export) = schema_materialize.from_codec("range_schema", range_c)

  schema_materialize.materialize("generated/catalog", [export])
  |> should.equal(
    Error(UnsupportedConstructor(["range_schema"], "NumberRangeSchema")),
  )

  // Also test nested inside an object property
  let assert Ok(s) = codec.schema(range_c)
  let nested_schema =
    codec.ObjectSchema([codec.PropertySchema("amount", True, s)])
  let nested_export = SchemaExport("nested_range", nested_schema)

  schema_materialize.materialize("generated/catalog", [nested_export])
  |> should.equal(
    Error(UnsupportedConstructor(
      ["nested_range", "amount"],
      "NumberRangeSchema",
    )),
  )

  // And inside a union variant's payload, located by its tag.
  let union_schema =
    codec.UnionSchema([
      codec.VariantSchema("empty", None),
      codec.VariantSchema("ranged", Some(codec.ListSchema(s))),
    ])
  schema_materialize.materialize("generated/catalog", [
    SchemaExport("union_range", union_schema),
  ])
  |> should.equal(
    Error(UnsupportedConstructor(
      ["union_range", "ranged", "*"],
      "NumberRangeSchema",
    )),
  )
}

pub fn union_schema_expression_keeps_unit_and_payload_variants_test() {
  schema_materialize.emit_schema_expression(
    codec.UnionSchema([
      codec.VariantSchema("defer", None),
      codec.VariantSchema(
        "approve \"let\"",
        Some(codec.IntegerRangeSchema(-1000, 1_000_000)),
      ),
    ]),
    ["decision"],
  )
  |> should.equal(Ok(
    "codec.UnionSchema([codec.VariantSchema(\"defer\", option.None), "
    <> "codec.VariantSchema(\"approve \\\"let\\\"\", "
    <> "option.Some(codec.IntegerRangeSchema(-1_000, 1_000_000)))])",
  ))
}

pub fn decision_union_schema_materializes_test() {
  let assert Ok(export) =
    schema_materialize.from_codec(
      "decision_schema",
      materialize_fixtures.build_decision_codec(),
    )
  let assert codec.UnionSchema([approve, decline, defer]) = export.schema
  approve.tag |> should.equal("approve \"let\"")
  decline.tag |> should.equal("decline \n\r\f\t\\import")
  defer |> should.equal(codec.VariantSchema("defer", None))

  let assert Ok(module) =
    schema_materialize.materialize("generated/decision_catalog", [export])
  module.path |> should.equal("generated/decision_catalog.gleam")
  module.content
  |> string.contains("import gleam/option\n")
  |> should.be_true
  module.content
  |> string.contains("codec.VariantSchema(\"defer\", option.None)")
  |> should.be_true
  module.content
  |> string.contains(
    "codec.VariantSchema(\"decline \\n\\r\\f\\t\\\\import\", option.Some(",
  )
  |> should.be_true
}

pub fn integer_literals_use_digit_separators_test() {
  schema_materialize.format_int_literal(0) |> should.equal("0")
  schema_materialize.format_int_literal(999) |> should.equal("999")
  schema_materialize.format_int_literal(1000) |> should.equal("1_000")
  schema_materialize.format_int_literal(-999_999) |> should.equal("-999_999")
  schema_materialize.format_int_literal(1_234_567)
  |> should.equal("1_234_567")
}

pub fn string_literal_escaping_test() {
  schema_materialize.escape_string_literal("hello")
  |> should.equal("\"hello\"")

  schema_materialize.escape_string_literal("with \"quotes\"")
  |> should.equal("\"with \\\"quotes\\\"\"")

  schema_materialize.escape_string_literal("with \\backslash")
  |> should.equal("\"with \\\\backslash\"")

  schema_materialize.escape_string_literal("line1\nline2")
  |> should.equal("\"line1\\nline2\"")

  schema_materialize.escape_string_literal("return\rcarriage")
  |> should.equal("\"return\\rcarriage\"")

  schema_materialize.escape_string_literal("form\ffeed")
  |> should.equal("\"form\\ffeed\"")

  schema_materialize.escape_string_literal("tab\tseparated")
  |> should.equal("\"tab\\tseparated\"")

  // Unicode graphemes are preserved directly
  schema_materialize.escape_string_literal("雪猫 🚀")
  |> should.equal("\"雪猫 🚀\"")
}

pub fn determinism_and_ordering_rule_test() {
  let order_c = materialize_fixtures.build_order_codec()
  let decision_c = materialize_fixtures.build_decision_codec()

  let assert Ok(order_export) =
    schema_materialize.from_codec("order_schema", order_c)
  let assert Ok(decision_export) =
    schema_materialize.from_codec("decision_schema", decision_c)

  // 1. Emitting twice from identical inputs yields byte-identical result
  let assert Ok(res1) =
    schema_materialize.materialize("generated/schema_catalog", [
      order_export,
      decision_export,
    ])
  let assert Ok(res2) =
    schema_materialize.materialize("generated/schema_catalog", [
      order_export,
      decision_export,
    ])

  res1.path |> should.equal(res2.path)
  res1.content |> should.equal(res2.content)

  // 2. Reordering inputs preserves canonical alphabetical accessor order
  let assert Ok(res_reversed) =
    schema_materialize.materialize("generated/schema_catalog", [
      decision_export,
      order_export,
    ])

  res1.path |> should.equal(res_reversed.path)
  res1.content |> should.equal(res_reversed.content)

  // Ensure generated content imports only json/blueprint/codec
  let assert True =
    res1.content
    |> string_contains("import json/blueprint/codec")

  let assert False =
    res1.content
    |> string_contains("schema_materialize")
}

fn string_contains(haystack: String, needle: String) -> Bool {
  case needle {
    "" -> True
    _ -> {
      let parts = string.split(haystack, needle)
      list.length(parts) > 1
    }
  }
}

pub fn end_to_end_fixture_generation_test() {
  let res = schema_materialization_runner.generate_fixture()
  res |> should.equal(Ok("build/schema-materialization/fixture"))
}
