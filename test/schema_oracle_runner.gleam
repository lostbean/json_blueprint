import gleam/io
import gleam/list
import json/blueprint/codec
import json/blueprint/document
import json/blueprint/number
import json/blueprint/runtime
import json/blueprint/value
import schema_oracle_test.{
  Approve, Decline, EmptyLabel, Low, Normal, PriorityRequest, QuotedUnicodeLabel,
  UpdateRecord, Urgent, value_to_json_string,
}

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

fn emit_cases(
  family: String,
  c: codec.Codec(a),
  cases: List(#(String, value.Value)),
) -> Nil {
  let assert Ok(schema) = codec.schema(c)
  let assert Ok(contract) = runtime.from_codec(c)
  let schema_doc = codec.schema_document(schema)
  let assert Ok(loaded) = document.load(schema_doc)
  let assert True = runtime.same_schema(contract, loaded)
  let normalized_doc = codec.schema_document(runtime.schema(contract))

  list.each(cases, fn(item) {
    let #(case_name, instance) = item
    let case_id = family <> "/" <> case_name
    let accepted = case codec.decode(c, instance) {
      Ok(_) -> True
      Error(_) -> False
    }
    let runtime_accepted = case runtime.validate(contract, instance) {
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
        #("runtime_accepted", value.Bool(runtime_accepted)),
      ])

    io.println(value_to_json_string(payload))
  })
  Nil
}

pub fn main() -> Nil {
  // 1. finite-priority (8 cases)
  let assert Ok(priority) =
    codec.string_enum([
      #("low", Low),
      #("normal", Normal),
      #("urgent", Urgent),
    ])
  emit_cases("finite-priority", priority, [
    #("valid-low", value.String("low")),
    #("valid-normal", value.String("normal")),
    #("valid-urgent", value.String("urgent")),
    #("rejected-uppercase", value.String("LOW")),
    #("rejected-unknown-enum", value.String("critical")),
    #("rejected-empty-string", value.String("")),
    #("rejected-type-integer", value.Number(int_num(1))),
    #("rejected-type-null", value.Null),
  ])

  // 2. finite-unusual-labels (4 cases)
  let assert Ok(decorative) =
    codec.string_enum([
      #("", EmptyLabel),
      #("quoted \"雪猫", QuotedUnicodeLabel),
    ])
  emit_cases("finite-unusual-labels", decorative, [
    #("valid-empty-label", value.String("")),
    #("valid-quoted-unicode", value.String("quoted \"雪猫")),
    #("rejected-missing-prefix", value.String("雪猫")),
    #("rejected-type-bool", value.Bool(True)),
  ])

  // 3. finite-object (7 cases)
  let assert Ok(props) =
    codec.combine(
      codec.required("priority", priority),
      codec.optional("note", codec.nullable(codec.string())),
    )
  let priority_request =
    codec.imap(
      codec.object(props),
      fn(raw) { PriorityRequest(raw.0, raw.1) },
      fn(req) { #(req.priority, req.note) },
    )
  emit_cases("finite-object", priority_request, [
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
  let list_nullable_priority = codec.list(codec.nullable(priority))
  emit_cases("finite-list-nullable", list_nullable_priority, [
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
  ])

  // 5. text (3 cases)
  emit_cases("text", codec.string(), [
    #("valid-string", value.String("hello")),
    #("rejected-type-number", value.Number(int_num(1))),
    #("rejected-type-null", value.Null),
  ])

  // 6. integer (3 cases)
  emit_cases("integer", codec.int(), [
    #("valid-zero", value.Number(int_num(0))),
    #("rejected-type-string", value.String("1")),
    #("rejected-type-bool", value.Bool(True)),
  ])

  // 7. boolean (2 cases)
  emit_cases("boolean", codec.bool(), [
    #("valid-false", value.Bool(False)),
    #("rejected-type-number", value.Number(int_num(0))),
  ])

  // 8. pair (5 cases)
  emit_cases("pair", codec.pair(codec.string(), codec.int()), [
    #(
      "valid-string-int-pair",
      value.Array([value.String("a"), value.Number(int_num(1))]),
    ),
    #("rejected-empty-array", value.Array([])),
    #("rejected-single-element", value.Array([value.String("a")])),
    #(
      "rejected-three-elements",
      value.Array([
        value.String("a"),
        value.Number(int_num(1)),
        value.Number(int_num(2)),
      ]),
    ),
    #(
      "rejected-reversed-element-types",
      value.Array([value.Number(int_num(1)), value.String("a")]),
    ),
  ])

  // 9. list-nullable (4 cases)
  emit_cases("list-nullable", codec.list(codec.nullable(codec.int())), [
    #("valid-empty-list", value.Array([])),
    #("valid-null-and-int", value.Array([value.Null, value.Number(int_num(2))])),
    #("rejected-string-element", value.Array([value.String("bad")])),
    #("rejected-type-null", value.Null),
  ])

  // 10. empty-object (3 cases)
  emit_cases("empty-object", codec.object(codec.empty()), [
    #("valid-empty-object", value.Object([])),
    #(
      "rejected-with-property",
      value.Object([#("x", value.Number(int_num(1)))]),
    ),
    #("rejected-type-null", value.Null),
  ])

  // 11. optional-nullable-record (6 cases)
  let assert Ok(update_props) =
    codec.combine(
      codec.required("name", codec.string()),
      codec.optional("note", codec.nullable(codec.string())),
    )
  let update_codec =
    codec.imap(
      codec.object(update_props),
      fn(raw) { UpdateRecord(raw.0, raw.1) },
      fn(rec) { #(rec.name, rec.note) },
    )
  emit_cases("optional-nullable-record", update_codec, [
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
      value.Object([
        #("name", value.String("Ada")),
        #("note", value.Number(int_num(1))),
      ]),
    ),
    #(
      "rejected-unknown-property",
      value.Object([#("name", value.String("Ada")), #("unknown", value.Null)]),
    ),
    #("rejected-missing-required-field", value.Object([])),
  ])

  // 12. inclusive-bounds (6 cases)
  let assert Ok(range) = codec.integer_between(-2, 2)
  emit_cases("inclusive-bounds", range, [
    #("rejected-below-minimum", value.Number(int_num(-3))),
    #("valid-minimum-boundary", value.Number(int_num(-2))),
    #("valid-middle-value", value.Number(int_num(0))),
    #("valid-maximum-boundary", value.Number(int_num(2))),
    #("rejected-above-maximum", value.Number(int_num(3))),
    #("rejected-type-string", value.String("2")),
  ])

  // 13. tagged-decision (6 cases)
  let assert Ok(quantity) = codec.integer_between(1, 100)
  let assert Ok(decision_tagged) =
    codec.tagged(
      "approve",
      codec.field("quantity", quantity),
      "decline",
      codec.field("reason", codec.string()),
    )
  let decision_codec =
    codec.imap(
      decision_tagged,
      fn(choice) {
        case choice {
          codec.Left(q) -> Approve(q)
          codec.Right(r) -> Decline(r)
        }
      },
      fn(d) {
        case d {
          Approve(q) -> codec.Left(q)
          Decline(r) -> codec.Right(r)
        }
      },
    )
  emit_cases("tagged-decision", decision_codec, [
    #(
      "valid-approve-branch",
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", value.Number(int_num(1)))])),
      ]),
    ),
    #(
      "rejected-approve-out-of-range",
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", value.Number(int_num(0)))])),
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
}
