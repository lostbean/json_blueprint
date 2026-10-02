//// The schema oracle corpus: each family is a codec and instances it must
//// accept or reject. `schema_oracle_runner` emits the same corpus for
//// `schema_check.py`, which checks the emitted schemas with Python
//// `jsonschema` Draft 2020-12 against `schema_manifest.json`.

import gleam/list
import gleam/option.{type Option}
import gleeunit/should
import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/number
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
  PriorityRequest(priority: Priority, note: Option(Option(String)))
}

pub type UpdateRecord {
  UpdateRecord(name: String, note: Option(Option(String)))
}

pub type Decision {
  Approve(quantity: Int)
  Decline(reason: String)
}

pub type Signal {
  Dim(level: Int)
  Blink(pattern: List(Bool))
  On
  Off
}

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

pub fn int_value(n: Int) -> value.Value {
  value.Number(int_num(n))
}

// --- corpus codecs -----------------------------------------------------------

pub fn priority_codec() -> codec.Codec(Priority) {
  codec.string_enum([#("low", Low), #("normal", Normal), #("urgent", Urgent)])
}

pub fn decorative_codec() -> codec.Codec(DecorativeLabel) {
  codec.string_enum([#("", EmptyLabel), #("quoted \"雪猫", QuotedUnicodeLabel)])
}

pub fn priority_request_codec() -> codec.Codec(PriorityRequest) {
  use priority <- codec.field(
    "priority",
    priority_codec(),
    fn(r: PriorityRequest) { r.priority },
  )
  use note <- codec.optional_field(
    "note",
    codec.nullable(codec.string()),
    fn(r: PriorityRequest) { r.note },
  )
  codec.success(PriorityRequest(priority:, note:))
}

pub fn update_record_codec() -> codec.Codec(UpdateRecord) {
  use name <- codec.field("name", codec.string(), fn(r: UpdateRecord) { r.name })
  use note <- codec.optional_field(
    "note",
    codec.nullable(codec.string()),
    fn(r: UpdateRecord) { r.note },
  )
  codec.success(UpdateRecord(name:, note:))
}

pub fn decision_codec() -> codec.Codec(Decision) {
  let approve = {
    use quantity <- codec.field(
      "quantity",
      codec.integer_between(1, 100),
      fn(q: Int) { q },
    )
    codec.success(quantity)
  }
  let decline = {
    use reason <- codec.field("reason", codec.string(), fn(r: String) { r })
    codec.success(reason)
  }
  codec.union({
    use approve <- codec.variant("approve", approve, Approve)
    use decline <- codec.variant("decline", decline, Decline)
    codec.match(fn(decision) {
      case decision {
        Approve(quantity) -> approve(quantity)
        Decline(reason) -> decline(reason)
      }
    })
  })
}

pub fn signal_codec() -> codec.Codec(Signal) {
  codec.union({
    use dim <- codec.variant("dim", codec.integer_between(0, 10), Dim)
    use blink <- codec.variant("blink", codec.list(codec.bool()), Blink)
    use on <- codec.unit_variant("on", On)
    use off <- codec.unit_variant("off", Off)
    codec.match(fn(signal) {
      case signal {
        Dim(level) -> dim(level)
        Blink(pattern) -> blink(pattern)
        On -> on
        Off -> off
      }
    })
  })
}

pub fn empty_object_codec() -> codec.Codec(Nil) {
  codec.success(Nil)
}

// --- the check ---------------------------------------------------------------

/// Decoding and contract validation agree on every instance, and the schema
/// document loads back to the codec's contract.
fn run_corpus_case(
  codec: codec.Codec(a),
  instances: List(#(value.Value, Bool)),
) {
  let assert Ok(schema) = codec.schema(codec)
  let assert Ok(from_codec) = contract.from_codec(codec)
  let schema_doc = codec.schema_document(schema)
  let assert Ok(loaded) = contract.load(schema_doc)
  let assert True = contract.same_schema(from_codec, loaded)
  let assert Ok(reparsed) =
    contract.parse(value.to_string(schema_doc), value.default_limits())
  let assert True = contract.same_schema(from_codec, reparsed)

  list.each(instances, fn(case_data) {
    let #(instance, expected_accepted) = case_data
    let decode_accepted = case codec.decode(codec, instance) {
      Ok(_) -> True
      Error(_) -> False
    }
    let contract_accepted = case contract.validate(loaded, instance) {
      Ok(validated) -> {
        // A validated value decodes through the contract
        let assert Ok(_) = contract.decode(codec, validated)
        True
      }
      Error(_) -> False
    }
    decode_accepted |> should.equal(expected_accepted)
    contract_accepted |> should.equal(expected_accepted)
  })
}

pub fn corpus_finite_priority_test() {
  run_corpus_case(priority_codec(), [
    #(value.String("low"), True),
    #(value.String("normal"), True),
    #(value.String("urgent"), True),
    #(value.String("LOW"), False),
    #(value.String("critical"), False),
    #(value.String(""), False),
    #(int_value(1), False),
    #(value.Null, False),
  ])
}

pub fn corpus_finite_unusual_labels_test() {
  run_corpus_case(decorative_codec(), [
    #(value.String(""), True),
    #(value.String("quoted \"雪猫"), True),
    #(value.String("雪猫"), False),
    #(value.Bool(True), False),
  ])
}

pub fn corpus_finite_object_test() {
  run_corpus_case(priority_request_codec(), [
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
  run_corpus_case(codec.list(codec.nullable(priority_codec())), [
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
    #(int_value(1), False),
    #(value.Null, False),
  ])
}

pub fn corpus_integer_test() {
  run_corpus_case(codec.int(), [
    #(int_value(0), True),
    #(value.String("1"), False),
    #(value.Bool(True), False),
  ])
}

pub fn corpus_boolean_test() {
  run_corpus_case(codec.bool(), [
    #(value.Bool(False), True),
    #(int_value(0), False),
  ])
}

pub fn corpus_pair_test() {
  run_corpus_case(codec.pair(codec.string(), codec.int()), [
    #(value.Array([value.String("a"), int_value(1)]), True),
    #(value.Array([]), False),
    #(value.Array([value.String("a")]), False),
    #(value.Array([value.String("a"), int_value(1), int_value(2)]), False),
    #(value.Array([int_value(1), value.String("a")]), False),
  ])
}

pub fn corpus_list_nullable_test() {
  run_corpus_case(codec.list(codec.nullable(codec.int())), [
    #(value.Array([]), True),
    #(value.Array([value.Null, int_value(2)]), True),
    #(value.Array([value.String("bad")]), False),
    #(value.Null, False),
  ])
}

pub fn corpus_empty_object_test() {
  run_corpus_case(empty_object_codec(), [
    #(value.Object([]), True),
    #(value.Object([#("x", int_value(1))]), False),
    #(value.Null, False),
  ])
}

pub fn corpus_optional_nullable_record_test() {
  run_corpus_case(update_record_codec(), [
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
      value.Object([#("name", value.String("Ada")), #("note", int_value(1))]),
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
  run_corpus_case(codec.integer_between(-2, 2), [
    #(int_value(-3), False),
    #(int_value(-2), True),
    #(int_value(0), True),
    #(int_value(2), True),
    #(int_value(3), False),
    #(value.String("2"), False),
  ])
}

pub fn corpus_tagged_decision_test() {
  run_corpus_case(decision_codec(), [
    #(
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", int_value(1))])),
      ]),
      True,
    ),
    #(
      value.Object([
        #("tag", value.String("approve")),
        #("value", value.Object([#("quantity", int_value(0))])),
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

pub fn corpus_union_unit_variants_test() {
  run_corpus_case(
    signal_codec(),
    signal_instances()
      |> list.map(fn(item) { #(item.1, item.2) }),
  )
}

/// The `union-unit-variants` family: name, instance, accepted.
pub fn signal_instances() -> List(#(String, value.Value, Bool)) {
  [
    #("valid-unit-on", value.Object([#("tag", value.String("on"))]), True),
    #("valid-unit-off", value.Object([#("tag", value.String("off"))]), True),
    #(
      "valid-payload-dim",
      value.Object([#("tag", value.String("dim")), #("value", int_value(10))]),
      True,
    ),
    #(
      "valid-payload-blink",
      value.Object([
        #("tag", value.String("blink")),
        #("value", value.Array([value.Bool(True), value.Bool(False)])),
      ]),
      True,
    ),
    #(
      "rejected-unit-with-value",
      value.Object([#("tag", value.String("on")), #("value", value.Null)]),
      False,
    ),
    #(
      "rejected-payload-missing-value",
      value.Object([#("tag", value.String("dim"))]),
      False,
    ),
    #(
      "rejected-payload-out-of-range",
      value.Object([#("tag", value.String("dim")), #("value", int_value(11))]),
      False,
    ),
    #(
      "rejected-unknown-tag",
      value.Object([#("tag", value.String("strobe"))]),
      False,
    ),
    #("rejected-missing-tag", value.Object([]), False),
    #(
      "rejected-non-string-tag",
      value.Object([#("tag", value.Bool(True))]),
      False,
    ),
    #(
      "rejected-extra-member",
      value.Object([#("tag", value.String("off")), #("note", value.Null)]),
      False,
    ),
    #("rejected-type-string", value.String("on"), False),
  ]
}
