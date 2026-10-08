import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen/schema
import json/blueprint/contract
import json/blueprint/value

fn load(document: String) -> codec.Schema {
  let assert Ok(#("{", rest)) = string.pop_grapheme(document)
  let assert Ok(contract) =
    contract.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"," <> rest,
      value.default_limits(),
    )
  contract.schema(contract)
}

pub fn reordered_properties_generate_identical_source_test() {
  let first =
    load(
      "{\"type\":\"object\",\"properties\":{\"z\":{\"type\":\"string\"},\"a\":{\"type\":\"integer\"}},\"required\":[\"z\",\"a\"],\"additionalProperties\":false}",
    )
  let second =
    load(
      "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"integer\"},\"z\":{\"type\":\"string\"}},\"required\":[\"a\",\"z\"],\"additionalProperties\":false}",
    )
  let assert Ok(generated) = schema.compile("generated/order", "order", first)
  schema.compile("generated/order", "order", second)
  |> should.equal(Ok(generated))
}

pub fn unsupported_nested_shape_has_canonical_location_test() {
  let input =
    load(
      "{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"yes\"]}}},\"required\":[\"items\"],\"additionalProperties\":false}",
    )
  schema.compile("generated/order", "order", input)
  |> should.equal(
    Error(schema.UnsupportedShape(
      [codec.Field("properties"), codec.Field("items"), codec.Field("items")],
      schema.StringEnum,
    )),
  )
}

pub fn colliding_fields_report_both_wire_locations_test() {
  let input =
    load(
      "{\"type\":\"object\",\"properties\":{\"orderId\":{\"type\":\"string\"},\"order_id\":{\"type\":\"string\"}},\"required\":[],\"additionalProperties\":false}",
    )
  schema.compile("generated/order", "order", input)
  |> should.equal(
    Error(schema.NameCollision(
      "order_id",
      schema.SchemaLocation([codec.Field("properties"), codec.Field("orderId")]),
      schema.SchemaLocation([codec.Field("properties"), codec.Field("order_id")]),
    )),
  )
}

pub fn invalid_module_root_and_field_names_are_typed_test() {
  let assert Ok(empty) = codec.schema(codec.success(Nil))
  schema.compile("../escape", "order", empty)
  |> should.equal(
    Error(schema.InvalidModuleName(
      "../escape",
      "module path segments must be non-empty, lowercase identifiers, and not keywords",
    )),
  )
  schema.compile("generated/order", "Order", empty)
  |> should.equal(
    Error(schema.InvalidRootName(
      "Order",
      "accessor name must start with [a-z] and contain only [a-z0-9_]",
    )),
  )
  let input =
    load(
      "{\"type\":\"object\",\"properties\":{\"雪\":{\"type\":\"string\"}},\"required\":[],\"additionalProperties\":false}",
    )
  schema.compile("generated/order", "order", input)
  |> should.equal(
    Error(schema.InvalidFieldName(
      [codec.Field("properties"), codec.Field("雪")],
      "雪",
    )),
  )
}

pub fn colliding_nested_types_report_both_locations_test() {
  let input =
    load(
      "{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}},\"items_item\":{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}},\"required\":[],\"additionalProperties\":false}",
    )
  schema.compile("generated/order", "order", input)
  |> should.equal(
    Error(schema.NameCollision(
      "OrderItemsItem",
      schema.SchemaLocation([
        codec.Field("properties"),
        codec.Field("items"),
        codec.Field("items"),
      ]),
      schema.SchemaLocation([
        codec.Field("properties"),
        codec.Field("items_item"),
      ]),
    )),
  )
}

pub fn builtin_and_imported_type_names_cannot_be_shadowed_test() {
  let assert Ok(empty) = codec.schema(codec.success(Nil))
  schema.compile("generated/int", "int", empty)
  |> should.equal(
    Error(schema.NameCollision(
      "Int",
      schema.ReservedName,
      schema.SchemaLocation([]),
    )),
  )
  let input =
    load(
      "{\"type\":\"object\",\"properties\":{\"item\":{\"type\":\"number\"}},\"required\":[\"item\"],\"additionalProperties\":false}",
    )
  schema.compile("generated/number", "number", input)
  |> should.equal(
    Error(schema.NameCollision(
      "Number",
      schema.ReservedName,
      schema.SchemaLocation([]),
    )),
  )
}

pub fn nonobject_root_and_unconstrained_child_are_refused_test() {
  let assert Ok(string) = codec.schema(codec.string())
  schema.compile("generated/order", "order", string)
  |> should.equal(Error(schema.UnsupportedShape([], schema.NonObjectRoot)))
  let input =
    load(
      "{\"type\":\"object\",\"properties\":{\"item\":{}},\"required\":[\"item\"],\"additionalProperties\":false}",
    )
  schema.compile("generated/order", "order", input)
  |> should.equal(
    Error(schema.UnsupportedShape(
      [codec.Field("properties"), codec.Field("item")],
      schema.AnyValue,
    )),
  )
}

pub fn normalization_retains_ascii_inside_combining_graphemes_test() {
  let input =
    load(
      "{\"type\":\"object\",\"properties\":{\"a\\u0301\":{\"type\":\"string\"}},\"required\":[\"a\\u0301\"],\"additionalProperties\":false}",
    )
  let assert Ok(module) = schema.compile("generated/accent", "accent", input)
  string.contains(module.content, "a: String") |> should.be_true
  string.contains(module.content, "codec.field(\"a\u{301}\"") |> should.be_true
}
