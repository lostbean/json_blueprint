//// Emits the schema oracle corpus as JSON lines for `test/schema_check.py`:
//// `gleam run -m schema_oracle_runner`.

import gleam/io
import gleam/list
import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/value
import schema_oracle_test.{
  decision_codec, decorative_codec, empty_object_codec, int_value,
  priority_codec, priority_request_codec, signal_codec, signal_instances,
  update_record_codec,
}

fn emit_cases(
  family: String,
  c: codec.Codec(a),
  cases: List(#(String, value.Value)),
) -> Nil {
  let assert Ok(schema) = codec.schema(c)
  let assert Ok(from_codec) = contract.from_codec(c)
  let schema_doc = codec.schema_document(schema)
  let assert Ok(loaded) = contract.load(schema_doc)
  let assert True = contract.same_schema(from_codec, loaded)
  let normalized_doc = codec.schema_document(contract.schema(loaded))

  list.each(cases, fn(item) {
    let #(case_name, instance) = item
    let case_id = family <> "/" <> case_name
    let accepted = case codec.decode(c, instance) {
      Ok(_) -> True
      Error(_) -> False
    }
    let contract_accepted = case contract.validate(loaded, instance) {
      Ok(_) -> True
      Error(_) -> False
    }

    let payload =
      value.Object([
        #("case_id", value.String(case_id)),
        #("label", value.String(family)),
        #("schema", schema_doc),
        #("normalized_schema", normalized_doc),
        #("instance", instance),
        #("accepted", value.Bool(accepted)),
        #("runtime_accepted", value.Bool(contract_accepted)),
      ])

    io.println(value.to_string(payload))
  })
  Nil
}

pub fn main() -> Nil {
  // 1. finite-priority (8 cases)
  emit_cases("finite-priority", priority_codec(), [
    #("valid-low", value.String("low")),
    #("valid-normal", value.String("normal")),
    #("valid-urgent", value.String("urgent")),
    #("rejected-uppercase", value.String("LOW")),
    #("rejected-unknown-enum", value.String("critical")),
    #("rejected-empty-string", value.String("")),
    #("rejected-type-integer", int_value(1)),
    #("rejected-type-null", value.Null),
  ])

  // 2. finite-unusual-labels (4 cases)
  emit_cases("finite-unusual-labels", decorative_codec(), [
    #("valid-empty-label", value.String("")),
    #("valid-quoted-unicode", value.String("quoted \"雪猫")),
    #("rejected-missing-prefix", value.String("雪猫")),
    #("rejected-type-bool", value.Bool(True)),
  ])

  // 3. finite-object (7 cases)
  emit_cases("finite-object", priority_request_codec(), [
    #(
      "valid-required-only",
      value.Object([#("priority", value.String("urgent"))]),
    ),
    #(
      "valid-with-null-note",
      value.Object([
        #("priority", value.String("normal")),
        #("note", value.Null),
      ]),
    ),
    #(
      "valid-with-string-note",
      value.Object([
        #("priority", value.String("low")),
        #("note", value.String("hello")),
      ]),
    ),
    #(
      "rejected-invalid-enum-field",
      value.Object([#("priority", value.String("critical"))]),
    ),
    #("rejected-null-required-field", value.Object([#("priority", value.Null)])),
    #(
      "rejected-extra-property",
      value.Object([#("priority", value.String("low")), #("extra", value.Null)]),
    ),
    #("rejected-missing-required-field", value.Object([])),
  ])

  // 4. finite-list-nullable (4 cases)
  emit_cases(
    "finite-list-nullable",
    codec.list(codec.nullable(priority_codec())),
    [
      #("valid-empty-list", value.Array([])),
      #(
        "valid-mixed-elements",
        value.Array([value.String("low"), value.Null, value.String("urgent")]),
      ),
      #(
        "rejected-invalid-element",
        value.Array([value.String("normal"), value.String("critical")]),
      ),
      #("rejected-type-null", value.Null),
    ],
  )

  // 5. text (3 cases)
  emit_cases("text", codec.string(), [
    #("valid-string", value.String("hello")),
    #("rejected-type-number", int_value(1)),
    #("rejected-type-null", value.Null),
  ])

  // 6. integer (3 cases)
  emit_cases("integer", codec.int(), [
    #("valid-zero", int_value(0)),
    #("rejected-type-string", value.String("1")),
    #("rejected-type-bool", value.Bool(True)),
  ])

  // 7. boolean (2 cases)
  emit_cases("boolean", codec.bool(), [
    #("valid-false", value.Bool(False)),
    #("rejected-type-number", int_value(0)),
  ])

  // 8. pair (5 cases)
  emit_cases("pair", codec.pair(codec.string(), codec.int()), [
    #("valid-string-int-pair", value.Array([value.String("a"), int_value(1)])),
    #("rejected-empty-array", value.Array([])),
    #("rejected-single-element", value.Array([value.String("a")])),
    #(
      "rejected-three-elements",
      value.Array([value.String("a"), int_value(1), int_value(2)]),
    ),
    #(
      "rejected-reversed-element-types",
      value.Array([int_value(1), value.String("a")]),
    ),
  ])

  // 9. list-nullable (4 cases)
  emit_cases("list-nullable", codec.list(codec.nullable(codec.int())), [
    #("valid-empty-list", value.Array([])),
    #("valid-null-and-int", value.Array([value.Null, int_value(2)])),
    #("rejected-string-element", value.Array([value.String("bad")])),
    #("rejected-type-null", value.Null),
  ])

  // 10. empty-object (3 cases)
  emit_cases("empty-object", empty_object_codec(), [
    #("valid-empty-object", value.Object([])),
    #("rejected-with-property", value.Object([#("x", int_value(1))])),
    #("rejected-type-null", value.Null),
  ])

  // 11. optional-nullable-record (6 cases)
  emit_cases("optional-nullable-record", update_record_codec(), [
    #("valid-required-only", value.Object([#("name", value.String("Ada"))])),
    #(
      "valid-null-optional",
      value.Object([#("name", value.String("Ada")), #("note", value.Null)]),
    ),
    #(
      "valid-present-optional",
      value.Object([
        #("name", value.String("Ada")),
        #("note", value.String("hello")),
      ]),
    ),
    #(
      "rejected-wrong-type-optional",
      value.Object([#("name", value.String("Ada")), #("note", int_value(1))]),
    ),
    #(
      "rejected-unknown-property",
      value.Object([#("name", value.String("Ada")), #("unknown", value.Null)]),
    ),
    #("rejected-missing-required-field", value.Object([])),
  ])

  // 12. inclusive-bounds (6 cases)
  emit_cases("inclusive-bounds", codec.integer_between(-2, 2), [
    #("rejected-below-minimum", int_value(-3)),
    #("valid-minimum-boundary", int_value(-2)),
    #("valid-middle-value", int_value(0)),
    #("valid-maximum-boundary", int_value(2)),
    #("rejected-above-maximum", int_value(3)),
    #("rejected-type-string", value.String("2")),
  ])

  // 13. tagged-decision (6 cases)
  emit_cases("tagged-decision", decision_codec(), [
    #(
      "valid-approve-branch",
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", int_value(1))])),
      ]),
    ),
    #(
      "rejected-approve-out-of-range",
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", int_value(0))])),
      ]),
    ),
    #(
      "valid-decline-branch",
      value.Object([
        #("tag", value.String("decline")),
        #("value", value.Object([#("reason", value.String("stock"))])),
      ]),
    ),
    #(
      "rejected-unknown-tag",
      value.Object([#("tag", value.String("unknown")), #("value", value.Null)]),
    ),
    #(
      "rejected-missing-value-field",
      value.Object([#("tag", value.String("approve"))]),
    ),
    #(
      "rejected-extra-property-in-branch",
      value.Object([
        #("tag", value.String("decline")),
        #(
          "value",
          value.Object([
            #("reason", value.String("stock")),
            #("extra", value.Bool(True)),
          ]),
        ),
      ]),
    ),
  ])

  // 14. union-unit-variants (12 cases): N-ary union with unit variants
  emit_cases(
    "union-unit-variants",
    signal_codec(),
    list.map(signal_instances(), fn(item) { #(item.0, item.1) }),
  )
}
