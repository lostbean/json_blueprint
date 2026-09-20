@target(erlang)
import gleam/io
@target(erlang)
import gleam/list
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
import schema_oracle_test.{
  Approve, Decline, EmptyLabel, Low, Normal, PriorityRequest, QuotedUnicodeLabel,
  UpdateRecord, Urgent, value_to_json_string,
}

@target(erlang)
fn emit_cases(
  label: String,
  c: codec.Codec(a),
  instances: List(value.Value),
) -> Nil {
  let assert Ok(schema) = codec.schema(c)
  let assert Ok(contract) = runtime.from_codec(c)
  let schema_doc = codec.schema_document(schema)
  let assert Ok(loaded) = document.load(schema_doc)
  let assert True = runtime.same_schema(contract, loaded)
  let normalized_doc = codec.schema_document(runtime.schema(contract))

  list.each(instances, fn(instance) {
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
        #("label", value.String(label)),
        #("schema", schema_doc),
        #("normalized_schema", normalized_doc),
        #("instance", instance),
        #("accepted", value.Bool(accepted)),
        #("runtime_accepted", value.Bool(runtime_accepted)),
      ])

    io.println(value_to_json_string(payload))
  })
}

@target(erlang)
pub fn main() -> Nil {
  // 1. finite-priority (8 cases)
  let assert Ok(priority) =
    codec.string_enum([
      #("low", Low),
      #("normal", Normal),
      #("urgent", Urgent),
    ])
  emit_cases("finite-priority", priority, [
    value.String("low"),
    value.String("normal"),
    value.String("urgent"),
    value.String("LOW"),
    value.String("critical"),
    value.String(""),
    value.Number(number.from_int(1)),
    value.Null,
  ])

  // 2. finite-unusual-labels (4 cases)
  let assert Ok(decorative) =
    codec.string_enum([
      #("", EmptyLabel),
      #("quoted \"雪猫", QuotedUnicodeLabel),
    ])
  emit_cases("finite-unusual-labels", decorative, [
    value.String(""),
    value.String("quoted \"雪猫"),
    value.String("雪猫"),
    value.Bool(True),
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
    value.Object([#("priority", value.String("urgent"))]),
    value.Object([#("priority", value.String("normal")), #("note", value.Null)]),
    value.Object([
      #("priority", value.String("low")),
      #("note", value.String("hello")),
    ]),
    value.Object([#("priority", value.String("critical"))]),
    value.Object([#("priority", value.Null)]),
    value.Object([#("priority", value.String("low")), #("extra", value.Null)]),
    value.Object([]),
  ])

  // 4. finite-list-nullable (4 cases)
  let list_nullable_priority = codec.list(codec.nullable(priority))
  emit_cases("finite-list-nullable", list_nullable_priority, [
    value.Array([]),
    value.Array([value.String("low"), value.Null, value.String("urgent")]),
    value.Array([value.String("normal"), value.String("critical")]),
    value.Null,
  ])

  // 5. text (3 cases)
  emit_cases("text", codec.string(), [
    value.String("hello"),
    value.Number(number.from_int(1)),
    value.Null,
  ])

  // 6. integer (3 cases)
  emit_cases("integer", codec.int(), [
    value.Number(number.from_int(0)),
    value.String("1"),
    value.Bool(True),
  ])

  // 7. boolean (2 cases)
  emit_cases("boolean", codec.bool(), [
    value.Bool(False),
    value.Number(number.from_int(0)),
  ])

  // 8. pair (5 cases)
  emit_cases("pair", codec.pair(codec.string(), codec.int()), [
    value.Array([value.String("a"), value.Number(number.from_int(1))]),
    value.Array([]),
    value.Array([value.String("a")]),
    value.Array([
      value.String("a"),
      value.Number(number.from_int(1)),
      value.Number(number.from_int(2)),
    ]),
    value.Array([value.Number(number.from_int(1)), value.String("a")]),
  ])

  // 9. list-nullable (4 cases)
  emit_cases("list-nullable", codec.list(codec.nullable(codec.int())), [
    value.Array([]),
    value.Array([value.Null, value.Number(number.from_int(2))]),
    value.Array([value.String("bad")]),
    value.Null,
  ])

  // 10. empty-object (3 cases)
  emit_cases("empty-object", codec.object(codec.empty()), [
    value.Object([]),
    value.Object([#("x", value.Number(number.from_int(1)))]),
    value.Null,
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
    value.Object([#("name", value.String("Ada"))]),
    value.Object([#("name", value.String("Ada")), #("note", value.Null)]),
    value.Object([
      #("name", value.String("Ada")),
      #("note", value.String("hello")),
    ]),
    value.Object([
      #("name", value.String("Ada")),
      #("note", value.Number(number.from_int(1))),
    ]),
    value.Object([#("name", value.String("Ada")), #("unknown", value.Null)]),
    value.Object([]),
  ])

  // 12. inclusive-bounds (6 cases)
  let assert Ok(range) = codec.integer_between(-2, 2)
  emit_cases("inclusive-bounds", range, [
    value.Number(number.from_int(-3)),
    value.Number(number.from_int(-2)),
    value.Number(number.from_int(0)),
    value.Number(number.from_int(2)),
    value.Number(number.from_int(3)),
    value.String("2"),
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
    value.Object([
      #("tag", value.String("approve")),
      #(
        "value",
        value.Object([#("quantity", value.Number(number.from_int(1)))]),
      ),
    ]),
    value.Object([
      #("tag", value.String("approve")),
      #(
        "value",
        value.Object([#("quantity", value.Number(number.from_int(0)))]),
      ),
    ]),
    value.Object([
      #("tag", value.String("decline")),
      #("value", value.Object([#("reason", value.String("stock"))])),
    ]),
    value.Object([#("tag", value.String("unknown")), #("value", value.Null)]),
    value.Object([#("tag", value.String("approve"))]),
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
  ])
}
