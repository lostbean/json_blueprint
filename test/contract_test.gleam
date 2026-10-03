//// Contracts built from codecs and schemas: normalization, definition
//// errors, validation paths and reasons, `decode`, `value_codec` and
//// `describe_validation_error`. Schema documents are in
//// `contract_document_test`.

import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import json/blueprint/codec.{type Codec, Field, Index}
import json/blueprint/contract
import json/blueprint/internal/schema_tree as tree
import json/blueprint/number
import json/blueprint/value.{type Value}

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

fn int_value(n: Int) -> Value {
  value.Number(int_num(n))
}

fn decimal_value(text: String) -> Value {
  let assert Ok(num) = number.parse(text, number.default_limits())
  value.Number(num)
}

fn object(members: List(#(String, Value))) -> Value {
  value.Object(members)
}

pub type Decision {
  Approve(qty: Int)
  Decline(reason: String)
  Defer
}

fn decision_codec() -> Codec(Decision) {
  let approve = {
    use qty <- codec.field("qty", codec.integer_between(1, 10), get: fn(q) { q })
    codec.success(qty)
  }
  let decline = {
    use reason <- codec.field("reason", codec.string(), get: fn(r) { r })
    codec.success(reason)
  }
  codec.union({
    use approve <- codec.variant("approve", approve, Approve)
    use decline <- codec.variant("decline", decline, Decline)
    use defer <- codec.unit_variant("defer", Defer)
    codec.match(fn(decision) {
      case decision {
        Approve(qty) -> approve(qty)
        Decline(reason) -> decline(reason)
        Defer -> defer
      }
    })
  })
}

/// The contract of a schema tree, as a generated module builds one.
fn tree_contract(schema: tree.Tree) -> contract.Contract {
  contract.from_schema(codec.from_tree(schema))
}

fn contract_tree(found: contract.Contract) -> tree.Tree {
  codec.to_tree(contract.schema(found))
}

fn approve_schema() -> tree.Tree {
  tree.ObjectSchema([
    tree.PropertySchema("qty", True, tree.IntegerRangeSchema(1, 10)),
  ])
}

fn decline_schema() -> tree.Tree {
  tree.ObjectSchema([tree.PropertySchema("reason", True, tree.StringSchema)])
}

fn tagged(tag: String, payload: Value) -> Value {
  object([#("tag", value.String(tag)), #("value", payload)])
}

// --- normalization -----------------------------------------------------------

pub fn contract_normalization_sorting_test() {
  // Object properties normalize in alphabetical order
  let unsorted_schema =
    tree.ObjectSchema([
      tree.PropertySchema("zeta", True, tree.StringSchema),
      tree.PropertySchema("alpha", False, tree.IntSchema),
      tree.PropertySchema("beta", True, tree.BoolSchema),
    ])

  let unsorted = tree_contract(unsorted_schema)
  contract_tree(unsorted)
  |> should.equal(
    tree.ObjectSchema([
      tree.PropertySchema("alpha", False, tree.IntSchema),
      tree.PropertySchema("beta", True, tree.BoolSchema),
      tree.PropertySchema("zeta", True, tree.StringSchema),
    ]),
  )

  // Enum labels normalize in alphabetical order
  let unsorted_enum = tree.StringEnumSchema(["urgent", "low", "normal"])
  let enum_contract = tree_contract(unsorted_enum)
  contract_tree(enum_contract)
  |> should.equal(tree.StringEnumSchema(["low", "normal", "urgent"]))

  // Union variants, with and without payloads, normalize by tag, and their
  // payloads normalize too
  let unsorted_union =
    tree.UnionSchema([
      tree.VariantSchema("zeta", Some(tree.IntSchema)),
      tree.VariantSchema("mid", None),
      tree.VariantSchema("alpha", Some(tree.StringEnumSchema(["b", "a"]))),
    ])
  let union_contract = tree_contract(unsorted_union)
  contract_tree(union_contract)
  |> should.equal(
    tree.UnionSchema([
      tree.VariantSchema("alpha", Some(tree.StringEnumSchema(["a", "b"]))),
      tree.VariantSchema("mid", None),
      tree.VariantSchema("zeta", Some(tree.IntSchema)),
    ]),
  )

  // same_schema respects normalization
  let sorted_schema =
    tree.ObjectSchema([
      tree.PropertySchema("alpha", False, tree.IntSchema),
      tree.PropertySchema("beta", True, tree.BoolSchema),
      tree.PropertySchema("zeta", True, tree.StringSchema),
    ])
  let sorted = tree_contract(sorted_schema)
  contract.same_schema(unsorted, sorted)
  |> should.equal(True)

  let sorted_union =
    tree_contract(
      tree.UnionSchema([
        tree.VariantSchema("alpha", Some(tree.StringEnumSchema(["a", "b"]))),
        tree.VariantSchema("mid", None),
        tree.VariantSchema("zeta", Some(tree.IntSchema)),
      ]),
    )
  contract.same_schema(union_contract, sorted_union)
  |> should.equal(True)

  // A unit variant and a variant with a payload are different schemas
  let with_payload =
    tree_contract(
      tree.UnionSchema([
        tree.VariantSchema("alpha", Some(tree.StringEnumSchema(["a", "b"]))),
        tree.VariantSchema("mid", Some(tree.StringSchema)),
        tree.VariantSchema("zeta", Some(tree.IntSchema)),
      ]),
    )
  contract.same_schema(union_contract, with_payload)
  |> should.equal(False)

  // Descriptions do not affect same_schema
  let described = tree_contract(tree.DescribedSchema("notes", sorted_schema))
  contract.same_schema(described, sorted)
  |> should.equal(True)
}

pub fn contract_normalization_invariants_test() {
  // Reversed integer range
  codec.validate_tree(tree.IntegerRangeSchema(10, 5))
  |> should.equal(Error(codec.ReversedIntegerBounds(10, 5)))

  // Reversed number range
  let min = int_num(20)
  let max = int_num(10)
  codec.validate_tree(tree.NumberRangeSchema(min, max))
  |> should.equal(Error(codec.ReversedNumberBounds(min, max)))

  // Duplicate object properties
  codec.validate_tree(
    tree.ObjectSchema([
      tree.PropertySchema("dup", True, tree.StringSchema),
      tree.PropertySchema("dup", False, tree.IntSchema),
    ]),
  )
  |> should.equal(Error(codec.DuplicateFieldName("dup")))

  // Duplicate tags, between a payload variant and a unit variant
  codec.validate_tree(
    tree.UnionSchema([
      tree.VariantSchema("same", Some(tree.StringSchema)),
      tree.VariantSchema("other", None),
      tree.VariantSchema("same", None),
    ]),
  )
  |> should.equal(Error(codec.DuplicateTag("same")))

  // A union without variants
  codec.validate_tree(tree.UnionSchema([]))
  |> should.equal(Error(codec.EmptyUnion))

  // Empty string enum
  codec.validate_tree(tree.StringEnumSchema([]))
  |> should.equal(Error(codec.EmptyEnum))

  // Duplicate enum labels
  codec.validate_tree(tree.StringEnumSchema(["a", "b", "a"]))
  |> should.equal(Error(codec.DuplicateEnumLabel("a")))

  // Mistakes nested in lists, pairs, nullables, descriptions, properties and
  // union payloads are found too
  codec.validate_tree(tree.ListSchema(tree.StringEnumSchema([])))
  |> should.equal(Error(codec.EmptyEnum))
  codec.validate_tree(tree.PairSchema(
    tree.StringSchema,
    tree.IntegerRangeSchema(3, 1),
  ))
  |> should.equal(Error(codec.ReversedIntegerBounds(3, 1)))
  codec.validate_tree(tree.DescribedSchema(
    "d",
    tree.NullableSchema(tree.UnionSchema([])),
  ))
  |> should.equal(Error(codec.EmptyUnion))
  codec.validate_tree(
    tree.ObjectSchema([
      tree.PropertySchema(
        "inner",
        True,
        tree.ObjectSchema([
          tree.PropertySchema("x", True, tree.IntSchema),
          tree.PropertySchema("x", True, tree.IntSchema),
        ]),
      ),
    ]),
  )
  |> should.equal(Error(codec.DuplicateFieldName("x")))
  codec.validate_tree(
    tree.UnionSchema([
      tree.VariantSchema("unit", None),
      tree.VariantSchema("payload", Some(tree.StringEnumSchema(["a", "a"]))),
    ]),
  )
  |> should.equal(Error(codec.DuplicateEnumLabel("a")))
}

pub fn from_codec_matches_from_schema_test() {
  let assert Ok(from_codec) = contract.from_codec(decision_codec())
  let from_schema =
    tree_contract(
      tree.UnionSchema([
        tree.VariantSchema("defer", None),
        tree.VariantSchema("decline", Some(decline_schema())),
        tree.VariantSchema("approve", Some(approve_schema())),
      ]),
    )
  contract.same_schema(from_codec, from_schema) |> should.equal(True)
  contract.schema(from_codec) |> should.equal(contract.schema(from_schema))

  // A codec without a schema has no contract
  let unknown =
    codec.custom(
      encode: fn(_: Int) { Ok(value.Null) },
      decode: fn(_) { Ok(0) },
      schema: None,
      placeholder: 0,
    )
  contract.from_codec(unknown) |> should.equal(Error(codec.UnknownSchema))
}

// --- validation --------------------------------------------------------------

pub fn validation_located_errors_test() {
  // Root error
  let str_contract = tree_contract(tree.StringSchema)
  contract.validate(str_contract, int_value(123))
  |> should.equal(Error(contract.ValidationError([], codec.ExpectedString)))

  // Nested object field error
  let obj_contract =
    tree_contract(
      tree.ObjectSchema([
        tree.PropertySchema(
          "user",
          True,
          tree.ObjectSchema([
            tree.PropertySchema("age", True, tree.IntSchema),
          ]),
        ),
      ]),
    )

  contract.validate(
    obj_contract,
    object([#("user", object([#("age", value.String("not-an-int"))]))]),
  )
  |> should.equal(
    Error(contract.ValidationError(
      [Field("user"), Field("age")],
      codec.ExpectedInt,
    )),
  )

  // Array index error
  let list_contract = tree_contract(tree.ListSchema(tree.StringSchema))
  contract.validate(
    list_contract,
    value.Array([value.String("ok"), value.Bool(True)]),
  )
  |> should.equal(
    Error(contract.ValidationError([Index(1)], codec.ExpectedString)),
  )

  // Closed object: unexpected extra field
  let simple_obj_contract =
    tree_contract(
      tree.ObjectSchema([
        tree.PropertySchema("name", True, tree.StringSchema),
      ]),
    )
  contract.validate(
    simple_obj_contract,
    object([#("name", value.String("valid")), #("extra", value.Null)]),
  )
  |> should.equal(
    Error(contract.ValidationError([Field("extra")], codec.UnknownField)),
  )

  // Missing required field
  contract.validate(simple_obj_contract, object([]))
  |> should.equal(
    Error(contract.ValidationError([Field("name")], codec.MissingField)),
  )

  // Duplicate key in payload
  contract.validate(
    simple_obj_contract,
    object([
      #("name", value.String("first")),
      #("name", value.String("second")),
    ]),
  )
  |> should.equal(
    Error(contract.ValidationError([Field("name")], codec.DuplicateField)),
  )

  // Union validation and errors
  let assert Ok(decision) = contract.from_codec(decision_codec())

  // Valid variant with a payload
  let valid_tagged = tagged("approve", object([#("qty", int_value(5))]))
  let assert Ok(validated) = contract.validate(decision, valid_tagged)
  contract.value(validated)
  |> should.equal(valid_tagged)
  contract.decode(decision_codec(), validated)
  |> should.equal(Ok(Approve(5)))

  // Payload out of range: the path runs through "value" with no tag segment
  contract.validate(
    decision,
    tagged("approve", object([#("qty", int_value(0))])),
  )
  |> should.equal(
    Error(contract.ValidationError(
      [Field("value"), Field("qty")],
      codec.IntegerOutsideRange(1, 10),
    )),
  )

  // Unknown tag
  contract.validate(decision, tagged("unknown", value.Null))
  |> should.equal(
    Error(contract.ValidationError([Field("tag")], codec.UnknownTag)),
  )
}

pub fn union_validation_reasons_and_paths_test() {
  let assert Ok(decision) = contract.from_codec(decision_codec())
  let check = fn(raw: Value, path, reason) {
    contract.validate(decision, raw)
    |> should.equal(Error(contract.ValidationError(path, reason)))
  }

  // Missing tag (was MissingTag)
  check(object([#("value", value.Null)]), [Field("tag")], codec.MissingField)
  check(object([]), [Field("tag")], codec.MissingField)

  // Non-string tag (was NonStringTag)
  check(
    object([#("tag", int_value(1)), #("value", value.Null)]),
    [Field("tag")],
    codec.ExpectedString,
  )

  // Unknown tag
  check(
    object([#("tag", value.String("cancel"))]),
    [Field("tag")],
    codec.UnknownTag,
  )

  // A payload variant without "value"
  check(
    object([#("tag", value.String("approve"))]),
    [Field("value")],
    codec.MissingField,
  )

  // A unit variant with "value"
  check(tagged("defer", value.Null), [Field("value")], codec.UnknownField)

  // A payload of the wrong type, and a payload with an unknown field
  check(
    tagged("decline", value.String("x")),
    [Field("value")],
    codec.ExpectedObject,
  )
  check(
    tagged(
      "decline",
      object([#("reason", value.String("stock")), #("extra", value.Bool(True))]),
    ),
    [Field("value"), Field("extra")],
    codec.UnknownField,
  )

  // Members other than "tag" and "value", and repeated members
  check(
    object([#("tag", value.String("defer")), #("note", value.Null)]),
    [Field("note")],
    codec.UnknownField,
  )
  check(
    object([#("tag", value.String("defer")), #("tag", value.String("defer"))]),
    [Field("tag")],
    codec.DuplicateField,
  )

  // Not an object
  check(value.String("defer"), [], codec.ExpectedObject)

  // Accepted: each variant, member order does not matter, unit without value
  let accepted = [
    tagged("approve", object([#("qty", int_value(10))])),
    object([
      #("value", object([#("reason", value.String("stock"))])),
      #("tag", value.String("decline")),
    ]),
    object([#("tag", value.String("defer"))]),
  ]
  list.each(accepted, fn(raw) {
    let assert Ok(validated) = contract.validate(decision, raw)
    contract.value(validated) |> should.equal(raw)
  })

  // A union nested in a list reports the index first
  let assert Ok(decisions) = contract.from_codec(codec.list(decision_codec()))
  contract.validate(
    decisions,
    value.Array([
      object([#("tag", value.String("defer"))]),
      tagged("approve", object([#("qty", int_value(11))])),
    ]),
  )
  |> should.equal(
    Error(contract.ValidationError(
      [Index(1), Field("value"), Field("qty")],
      codec.IntegerOutsideRange(1, 10),
    )),
  )
}

/// Validation and decoding share one vocabulary: an input with one failure
/// fails both at the same path with the same reason.
fn agree(c: Codec(a), raw: Value, path: List(codec.PathSegment), reason) {
  let assert Ok(found) = contract.from_codec(c)
  contract.validate(found, raw)
  |> should.equal(Error(contract.ValidationError(path, reason)))
  codec.decode(c, raw)
  |> should.equal(Error(codec.DecodeError(path, reason)))
}

pub type Level {
  Low
  High
}

fn person_codec() -> Codec(#(String, Int)) {
  use name <- codec.field("name", codec.string(), get: fn(p) { p.0 })
  use age <- codec.field("age", codec.int(), get: fn(p) { p.1 })
  codec.success(#(name, age))
}

pub fn validation_reasons_match_decoding_test() {
  agree(codec.string(), int_value(1), [], codec.ExpectedString)
  agree(codec.int(), value.String("1"), [], codec.ExpectedInt)
  agree(codec.int(), decimal_value("1.5"), [], codec.ExpectedInt)
  agree(codec.float(), value.String("1"), [], codec.ExpectedNumber)
  agree(codec.number(), value.Null, [], codec.ExpectedNumber)
  agree(codec.bool(), value.Null, [], codec.ExpectedBool)
  agree(codec.list(codec.string()), object([]), [], codec.ExpectedArray)
  agree(
    codec.list(codec.string()),
    value.Array([value.String("a"), int_value(1)]),
    [Index(1)],
    codec.ExpectedString,
  )
  let pair = codec.pair(codec.string(), codec.int())
  agree(pair, value.String("a"), [], codec.ExpectedArray)
  agree(pair, value.Array([value.String("a")]), [], codec.WrongLength(2, 1))
  agree(
    pair,
    value.Array([value.String("a"), int_value(1), int_value(2)]),
    [],
    codec.WrongLength(2, 3),
  )
  agree(
    pair,
    value.Array([value.String("a"), value.String("b")]),
    [Index(1)],
    codec.ExpectedInt,
  )
  agree(codec.nullable(codec.int()), value.String("x"), [], codec.ExpectedInt)
  let level = codec.string_enum([#("low", Low), #("high", High)])
  agree(level, value.String("medium"), [], codec.UnknownEnumLabel)
  agree(level, int_value(1), [], codec.ExpectedString)
  let bounded = codec.integer_between(1, 10)
  agree(bounded, int_value(0), [], codec.IntegerOutsideRange(1, 10))
  agree(bounded, int_value(11), [], codec.IntegerOutsideRange(1, 10))
  agree(bounded, decimal_value("2.5"), [], codec.ExpectedInt)
  agree(bounded, value.String("2"), [], codec.ExpectedInt)
  let unit = codec.number_between(int_num(0), int_num(1))
  agree(
    unit,
    int_value(2),
    [],
    codec.NumberOutsideRange(int_num(0), int_num(1)),
  )
  agree(
    unit,
    decimal_value("-0.5"),
    [],
    codec.NumberOutsideRange(int_num(0), int_num(1)),
  )
  agree(unit, value.Bool(True), [], codec.ExpectedNumber)
  agree(person_codec(), value.Array([]), [], codec.ExpectedObject)
  agree(
    person_codec(),
    object([#("name", value.String("Ada"))]),
    [Field("age")],
    codec.MissingField,
  )
  agree(
    person_codec(),
    object([
      #("name", value.String("Ada")),
      #("age", int_value(3)),
      #("extra", value.Null),
    ]),
    [Field("extra")],
    codec.UnknownField,
  )
  agree(
    person_codec(),
    object([
      #("name", value.String("Ada")),
      #("name", value.String("Eve")),
      #("age", int_value(3)),
    ]),
    [Field("name")],
    codec.DuplicateField,
  )
  agree(
    decision_codec(),
    object([#("value", value.Null)]),
    [Field("tag")],
    codec.MissingField,
  )
  agree(
    decision_codec(),
    object([#("tag", value.Bool(True))]),
    [Field("tag")],
    codec.ExpectedString,
  )
  agree(
    decision_codec(),
    object([#("tag", value.String("cancel"))]),
    [Field("tag")],
    codec.UnknownTag,
  )
  agree(
    decision_codec(),
    object([#("tag", value.String("approve"))]),
    [Field("value")],
    codec.MissingField,
  )
  agree(
    decision_codec(),
    tagged("defer", object([])),
    [Field("value")],
    codec.UnknownField,
  )
  agree(
    decision_codec(),
    tagged("approve", object([#("qty", int_value(0))])),
    [Field("value"), Field("qty")],
    codec.IntegerOutsideRange(1, 10),
  )
}

pub fn validation_accepts_what_decoding_accepts_test() {
  // Nullable accepts null and the inner value
  let assert Ok(nullable) =
    contract.from_codec(codec.nullable(codec.integer_between(1, 3)))
  contract.validate(nullable, value.Null) |> should.be_ok
  contract.validate(nullable, int_value(2)) |> should.be_ok

  // Optional properties may be absent
  let optional =
    tree_contract(
      tree.ObjectSchema([
        tree.PropertySchema("a", False, tree.StringSchema),
      ]),
    )
  contract.validate(optional, object([])) |> should.be_ok
  contract.validate(optional, object([#("a", value.Null)]))
  |> should.equal(
    Error(contract.ValidationError([Field("a")], codec.ExpectedString)),
  )

  // Integer spellings with an exponent or a zero fraction are integers
  let assert Ok(range) = contract.from_codec(codec.integer_between(1, 100))
  contract.validate(range, decimal_value("1.2e1")) |> should.be_ok
  contract.validate(range, decimal_value("12.0")) |> should.be_ok

  // Number ranges are inclusive and exact
  let bounds = tree_contract(tree.NumberRangeSchema(int_num(0), int_num(1)))
  contract.validate(bounds, decimal_value("0")) |> should.be_ok
  contract.validate(bounds, decimal_value("1.0")) |> should.be_ok
  contract.validate(bounds, decimal_value("0.999999999999999999999"))
  |> should.be_ok
  contract.validate(bounds, decimal_value("1.000000000000000000001"))
  |> should.equal(
    Error(contract.ValidationError(
      [],
      codec.NumberOutsideRange(int_num(0), int_num(1)),
    )),
  )
}

// --- decoding ----------------------------------------------------------------

pub fn contract_decode_test() {
  let c = codec.pair(codec.string(), codec.int())
  let assert Ok(pair_contract) = contract.from_codec(c)

  let raw = value.Array([value.String("item"), int_value(42)])
  let assert Ok(validated) = contract.validate(pair_contract, raw)

  contract.decode(c, validated)
  |> should.equal(Ok(#("item", 42)))

  // Unit variants decode through a contract
  let assert Ok(decision) = contract.from_codec(decision_codec())
  let assert Ok(deferred) =
    contract.validate(decision, object([#("tag", value.String("defer"))]))
  contract.decode(decision_codec(), deferred) |> should.equal(Ok(Defer))
}

pub fn decode_ignores_descriptions_and_order_test() {
  // A contract from a schema with other label order and no descriptions
  let levels = tree_contract(tree.StringEnumSchema(["low", "high"]))
  let assert Ok(validated) = contract.validate(levels, value.String("high"))
  let level =
    codec.string_enum([#("high", High), #("low", Low)])
    |> codec.describe("A level")
  contract.decode(level, validated) |> should.equal(Ok(High))

  // A record codec whose fields are declared in another order
  let person =
    tree_contract(
      tree.ObjectSchema([
        tree.PropertySchema("age", True, tree.IntSchema),
        tree.PropertySchema(
          "name",
          True,
          tree.DescribedSchema("Full name", tree.StringSchema),
        ),
      ]),
    )
  let assert Ok(validated) =
    contract.validate(
      person,
      object([#("age", int_value(36)), #("name", value.String("Ada"))]),
    )
  contract.decode(person_codec(), validated)
  |> should.equal(Ok(#("Ada", 36)))
}

fn mismatch() -> Result(a, codec.DecodeError) {
  Error(codec.DecodeError([], codec.ContractMismatch))
}

pub fn decode_contract_mismatch_test() {
  let assert Ok(pair_contract) =
    contract.from_codec(codec.pair(codec.string(), codec.int()))
  let assert Ok(validated) =
    contract.validate(
      pair_contract,
      value.Array([value.String("item"), int_value(42)]),
    )

  // Another schema
  contract.decode(codec.pair(codec.string(), codec.number()), validated)
  |> should.equal(mismatch())

  // A codec without a schema
  let unknown =
    codec.custom(
      encode: fn(_: Int) { Ok(value.Null) },
      decode: fn(_) { Ok(0) },
      schema: None,
      placeholder: 0,
    )
  contract.decode(unknown, validated) |> should.equal(mismatch())

  // A narrower schema that would accept this value still mismatches
  let assert Ok(any_int) = contract.from_codec(codec.int())
  let assert Ok(five) = contract.validate(any_int, int_value(5))
  contract.decode(codec.integer_between(0, 10), five)
  |> should.equal(mismatch())

  // A union with a unit variant differs from one with a payload variant
  let assert Ok(decision) = contract.from_codec(decision_codec())
  let assert Ok(deferred) =
    contract.validate(decision, object([#("tag", value.String("defer"))]))
  let other = {
    codec.union({
      use defer <- codec.variant("defer", codec.int(), fn(_) { Defer })
      codec.match(fn(_) { defer(0) })
    })
  }
  contract.decode(other, deferred) |> should.equal(mismatch())
}

// --- value_codec -------------------------------------------------------------

fn limit_contract() -> contract.Contract {
  let found =
    tree_contract(
      tree.ObjectSchema([
        tree.PropertySchema("limit", True, tree.IntegerRangeSchema(1, 10)),
        tree.PropertySchema("note", False, tree.StringSchema),
      ]),
    )
  found
}

pub fn value_codec_validates_on_decode_test() {
  let payload = contract.value_codec(limit_contract())
  let good = object([#("limit", int_value(3))])

  codec.decode(payload, good) |> should.equal(Ok(good))
  codec.decode_json(payload, "{\"note\":\"n\",\"limit\":10}")
  |> should.equal(
    Ok(object([#("note", value.String("n")), #("limit", int_value(10))])),
  )

  codec.decode(payload, object([#("limit", int_value(0))]))
  |> should.equal(
    Error(codec.DecodeError([Field("limit")], codec.IntegerOutsideRange(1, 10))),
  )
  codec.decode(payload, object([]))
  |> should.equal(
    Error(codec.DecodeError([Field("limit")], codec.MissingField)),
  )
  codec.decode(payload, value.Array([]))
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedObject)))

  // Encoding passes the value through
  codec.encode(payload, good) |> should.equal(Ok(good))
  codec.encode_json(payload, good) |> should.equal(Ok("{\"limit\":3}"))
}

pub fn value_codec_has_the_contract_schema_test() {
  let remote = limit_contract()
  let payload = contract.value_codec(remote)

  codec.schema(payload) |> should.equal(Ok(contract.schema(remote)))
  let assert Ok(again) = contract.from_codec(payload)
  contract.same_schema(again, remote) |> should.equal(True)

  // A value validated by the contract decodes through `contract.decode`
  let good = object([#("limit", int_value(3))])
  let assert Ok(validated) = contract.validate(remote, good)
  contract.decode(payload, validated) |> should.equal(Ok(good))

  // The schema appears inside the schema of codecs built from it
  let envelope = {
    use id <- codec.field("id", codec.int(), get: fn(e) { e.0 })
    use body <- codec.field("body", payload, get: fn(e) { e.1 })
    codec.success(#(id, body))
  }
  codec.schema(envelope)
  |> result.map(codec.to_tree)
  |> should.equal(
    Ok(
      tree.ObjectSchema([
        tree.PropertySchema("id", True, tree.IntSchema),
        tree.PropertySchema("body", True, contract_tree(remote)),
      ]),
    ),
  )
}

pub fn value_codec_error_paths_test() {
  let payload = contract.value_codec(limit_contract())
  let envelope = {
    use id <- codec.field("id", codec.int(), get: fn(e) { e.0 })
    use body <- codec.field("body", payload, get: fn(e) { e.1 })
    codec.success(#(id, body))
  }

  codec.decode_json(envelope, "{\"id\":1,\"body\":{\"limit\":2}}")
  |> should.equal(Ok(#(1, object([#("limit", int_value(2))]))))
  codec.decode_json(envelope, "{\"id\":1,\"body\":{\"limit\":0}}")
  |> should.equal(
    Error(codec.DecodeError(
      [Field("body"), Field("limit")],
      codec.IntegerOutsideRange(1, 10),
    )),
  )
  codec.decode_json(envelope, "{\"id\":1,\"body\":{\"limit\":2,\"x\":1}}")
  |> should.equal(
    Error(codec.DecodeError([Field("body"), Field("x")], codec.UnknownField)),
  )

  codec.decode_json(
    codec.list(payload),
    "[{\"limit\":1},{\"limit\":1,\"note\":7}]",
  )
  |> should.equal(
    Error(codec.DecodeError([Index(1), Field("note")], codec.ExpectedString)),
  )

  // A union contract's errors keep their union paths
  let assert Ok(decision) = contract.from_codec(decision_codec())
  codec.decode_json(
    contract.value_codec(decision),
    "{\"tag\":\"approve\",\"value\":{\"qty\":99}}",
  )
  |> should.equal(
    Error(codec.DecodeError(
      [Field("value"), Field("qty")],
      codec.IntegerOutsideRange(1, 10),
    )),
  )
}

// --- describe ----------------------------------------------------------------

pub fn describe_validation_error_test() {
  contract.describe_validation_error(contract.ValidationError(
    [Field("limit")],
    codec.IntegerOutsideRange(1, 10),
  ))
  |> should.equal("$[\"limit\"]: integer outside range 1 to 10")

  contract.describe_validation_error(contract.ValidationError(
    [Field("items"), Index(2), Field("value")],
    codec.MissingField,
  ))
  |> should.equal("$[\"items\"][2][\"value\"]: missing field")

  contract.describe_validation_error(contract.ValidationError(
    [],
    codec.ExpectedObject,
  ))
  |> should.equal("$: expected an object")
}

pub fn describe_validation_error_omits_input_values_test() {
  let account =
    tree_contract(
      tree.ObjectSchema([
        tree.PropertySchema(
          "level",
          True,
          tree.StringEnumSchema(["low", "high"]),
        ),
        tree.PropertySchema("limit", False, tree.IntegerRangeSchema(1, 10)),
      ]),
    )
  let assert Ok(decision) = contract.from_codec(decision_codec())
  let cases = [
    #(
      account,
      object([#("level", value.String("hunter2-secret"))]),
      "$[\"level\"]: unknown enum label",
      "hunter2",
    ),
    #(
      account,
      object([
        #("level", value.String("low")),
        #("secret-key-name", value.String("v")),
      ]),
      "$: unknown field",
      "secret-key-name",
    ),
    #(
      account,
      object([#("level", value.String("low")), #("limit", int_value(987_654))]),
      "$[\"limit\"]: integer outside range 1 to 10",
      "987654",
    ),
    #(
      account,
      object([
        #("level", value.String("low")),
        #("level", value.String("private-dup")),
      ]),
      "$: duplicate field",
      "private-dup",
    ),
    #(
      decision,
      object([#("tag", value.String("private-tag"))]),
      "$[\"tag\"]: unknown tag",
      "private-tag",
    ),
    #(
      decision,
      tagged("decline", object([#("reason", value.Bool(True))])),
      "$[\"value\"][\"reason\"]: expected a string",
      "true",
    ),
  ]
  list.each(cases, fn(item) {
    let #(found, raw, expected, secret) = item
    let assert Error(error) = contract.validate(found, raw)
    let text = contract.describe_validation_error(error)
    text |> should.equal(expected)
    string.contains(text, secret) |> should.be_false
  })
}
