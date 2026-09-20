import gleam/json
import gleam/list
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/document
import json/blueprint/number
import json/blueprint/runtime
import json/blueprint/value

pub type Priority {
  Low
  Normal
  Urgent
}

pub type DecorativeLabel {
  EmptyLabel
  QuotedUnicodeLabel
}

pub type PriorityRequest {
  PriorityRequest(
    priority: Priority,
    note: codec.Optional(codec.Nullable(String)),
  )
}

pub type UpdateRecord {
  UpdateRecord(name: String, note: codec.Optional(codec.Nullable(String)))
}

pub type Decision {
  Approve(quantity: Int)
  Decline(reason: String)
}

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

fn run_corpus_case(
  codec: codec.Codec(a),
  instances: List(#(value.Value, Bool)),
) {
  let assert Ok(schema) = codec.schema(codec)
  let assert Ok(contract) = runtime.from_codec(codec)
  let schema_doc = codec.schema_document(schema)
  let assert Ok(loaded) = document.load(schema_doc)
  let assert True = runtime.same_schema(contract, loaded)

  list.each(instances, fn(case_data) {
    let #(instance, expected_accepted) = case_data
    let decode_accepted = case codec.decode(codec, instance) {
      Ok(_) -> True
      Error(_) -> False
    }
    let runtime_accepted = case runtime.validate(contract, instance) {
      Ok(_) -> True
      Error(_) -> False
    }
    decode_accepted |> should.equal(expected_accepted)
    runtime_accepted |> should.equal(expected_accepted)
  })
}

pub fn corpus_finite_priority_test() {
  let assert Ok(priority) =
    codec.string_enum([
      #("low", Low),
      #("normal", Normal),
      #("urgent", Urgent),
    ])

  run_corpus_case(priority, [
    #(value.String("low"), True),
    #(value.String("normal"), True),
    #(value.String("urgent"), True),
    #(value.String("LOW"), False),
    #(value.String("critical"), False),
    #(value.String(""), False),
    #(value.Number(int_num(1)), False),
    #(value.Null, False),
  ])
}

pub fn corpus_finite_unusual_labels_test() {
  let assert Ok(decorative) =
    codec.string_enum([
      #("", EmptyLabel),
      #("quoted \"雪猫", QuotedUnicodeLabel),
    ])

  run_corpus_case(decorative, [
    #(value.String(""), True),
    #(value.String("quoted \"雪猫"), True),
    #(value.String("雪猫"), False),
    #(value.Bool(True), False),
  ])
}

pub fn corpus_finite_object_test() {
  let assert Ok(priority) =
    codec.string_enum([
      #("low", Low),
      #("normal", Normal),
      #("urgent", Urgent),
    ])

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

  run_corpus_case(priority_request, [
    #(value.Object([#("priority", value.String("urgent"))]), True),
    #(
      value.Object([
        #("priority", value.String("normal")),
        #("note", value.Null),
      ]),
      True,
    ),
    #(
      value.Object([
        #("priority", value.String("low")),
        #("note", value.String("hello")),
      ]),
      True,
    ),
    #(value.Object([#("priority", value.String("critical"))]), False),
    #(value.Object([#("priority", value.Null)]), False),
    #(
      value.Object([#("priority", value.String("low")), #("extra", value.Null)]),
      False,
    ),
    #(value.Object([]), False),
  ])
}

pub fn corpus_finite_list_nullable_test() {
  let assert Ok(priority) =
    codec.string_enum([
      #("low", Low),
      #("normal", Normal),
      #("urgent", Urgent),
    ])

  let c = codec.list(codec.nullable(priority))

  run_corpus_case(c, [
    #(value.Array([]), True),
    #(
      value.Array([value.String("low"), value.Null, value.String("urgent")]),
      True,
    ),
    #(value.Array([value.String("normal"), value.String("critical")]), False),
    #(value.Null, False),
  ])
}

pub fn corpus_text_test() {
  run_corpus_case(codec.string(), [
    #(value.String("hello"), True),
    #(value.Number(int_num(1)), False),
    #(value.Null, False),
  ])
}

pub fn corpus_integer_test() {
  run_corpus_case(codec.int(), [
    #(value.Number(int_num(0)), True),
    #(value.String("1"), False),
    #(value.Bool(True), False),
  ])
}

pub fn corpus_boolean_test() {
  run_corpus_case(codec.bool(), [
    #(value.Bool(False), True),
    #(value.Number(int_num(0)), False),
  ])
}

pub fn corpus_pair_test() {
  let c = codec.pair(codec.string(), codec.int())

  run_corpus_case(c, [
    #(value.Array([value.String("a"), value.Number(int_num(1))]), True),
    #(value.Array([]), False),
    #(value.Array([value.String("a")]), False),
    #(
      value.Array([
        value.String("a"),
        value.Number(int_num(1)),
        value.Number(int_num(2)),
      ]),
      False,
    ),
    #(value.Array([value.Number(int_num(1)), value.String("a")]), False),
  ])
}

pub fn corpus_list_nullable_test() {
  let c = codec.list(codec.nullable(codec.int()))

  run_corpus_case(c, [
    #(value.Array([]), True),
    #(value.Array([value.Null, value.Number(int_num(2))]), True),
    #(value.Array([value.String("bad")]), False),
    #(value.Null, False),
  ])
}

pub fn corpus_empty_object_test() {
  let c = codec.object(codec.empty())

  run_corpus_case(c, [
    #(value.Object([]), True),
    #(value.Object([#("x", value.Number(int_num(1)))]), False),
    #(value.Null, False),
  ])
}

pub fn corpus_optional_nullable_record_test() {
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

  run_corpus_case(update_codec, [
    #(value.Object([#("name", value.String("Ada"))]), True),
    #(
      value.Object([#("name", value.String("Ada")), #("note", value.Null)]),
      True,
    ),
    #(
      value.Object([
        #("name", value.String("Ada")),
        #("note", value.String("hello")),
      ]),
      True,
    ),
    #(
      value.Object([
        #("name", value.String("Ada")),
        #("note", value.Number(int_num(1))),
      ]),
      False,
    ),
    #(
      value.Object([#("name", value.String("Ada")), #("unknown", value.Null)]),
      False,
    ),
    #(value.Object([]), False),
  ])
}

pub fn corpus_inclusive_bounds_test() {
  let assert Ok(range) = codec.integer_between(-2, 2)

  run_corpus_case(range, [
    #(value.Number(int_num(-3)), False),
    #(value.Number(int_num(-2)), True),
    #(value.Number(int_num(0)), True),
    #(value.Number(int_num(2)), True),
    #(value.Number(int_num(3)), False),
    #(value.String("2"), False),
  ])
}

pub fn corpus_tagged_decision_test() {
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

  run_corpus_case(decision_codec, [
    #(
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", value.Number(int_num(1)))])),
      ]),
      True,
    ),
    #(
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", value.Number(int_num(0)))])),
      ]),
      False,
    ),
    #(
      value.Object([
        #("tag", value.String("decline")),
        #("value", value.Object([#("reason", value.String("stock"))])),
      ]),
      True,
    ),
    #(
      value.Object([#("tag", value.String("unknown")), #("value", value.Null)]),
      False,
    ),
    #(value.Object([#("tag", value.String("approve"))]), False),
    #(
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
      False,
    ),
  ])
}

pub fn value_to_json_string(val: value.Value) -> String {
  case val {
    value.Null -> "null"
    value.Bool(True) -> "true"
    value.Bool(False) -> "false"
    value.String(s) -> json.string(s) |> json.to_string
    value.Number(n) -> number.number_text(n)
    value.Array(items) ->
      "[" <> string.join(list.map(items, value_to_json_string), ",") <> "]"
    value.Object(pairs) ->
      "{"
      <> string.join(
        list.map(pairs, fn(pair) {
          { json.string(pair.0) |> json.to_string }
          <> ":"
          <> value_to_json_string(pair.1)
        }),
        ",",
      )
      <> "}"
  }
}
