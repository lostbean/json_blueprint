//// Public contract validation retains values and first-error order at varied widths.

import gleam/int
import gleam/list
import gleam/result
import gleeunit/should
import json/blueprint/codec.{Field, Index}
import json/blueprint/contract
import json/blueprint/value

fn names(width: Int) -> List(String) {
  list.append(
    ["a", "b"],
    list.repeat(Nil, width - 2)
      |> list.index_map(fn(_, n) { "field_" <> int.to_string(n + 3) }),
  )
}

fn members(names: List(String)) -> List(#(String, value.Value)) {
  list.map(names, fn(name) { #(name, value.String(name)) })
}

fn object_schema(names: List(String), required: List(String)) -> value.Value {
  value.Object([
    #("type", value.String("object")),
    #(
      "properties",
      value.Object(
        list.map(names, fn(name) {
          #(name, value.Object([#("type", value.String("string"))]))
        }),
      ),
    ),
    #("required", value.Array(list.map(required, value.String))),
    #("additionalProperties", value.Bool(False)),
  ])
}

fn load(schema: value.Value) -> contract.Contract {
  let assert value.Object(fields) = schema
  let assert Ok(bound) =
    contract.load(
      value.Object([
        #(
          "$schema",
          value.String("https://json-schema.org/draft/2020-12/schema"),
        ),
        ..fields
      ]),
    )
  bound
}

fn accepts(bound: contract.Contract, raw: value.Value) {
  contract.validate(bound, raw)
  |> result.map(contract.value)
  |> should.equal(Ok(raw))
  let payload = contract.value_codec(bound)
  codec.encode(payload, raw) |> should.equal(Ok(raw))
  codec.decode(payload, raw) |> should.equal(Ok(raw))
  codec.encode_json(payload, raw) |> should.equal(Ok(value.to_string(raw)))
}

fn rejects(
  bound: contract.Contract,
  raw: value.Value,
  path: List(codec.PathSegment),
  reason: codec.Reason,
) {
  contract.validate(bound, raw)
  |> should.equal(Error(contract.ValidationError(path, reason)))
  let payload = contract.value_codec(bound)
  codec.encode(payload, raw)
  |> should.equal(Error(codec.EncodeError(path, reason)))
  codec.decode(payload, raw)
  |> should.equal(Error(codec.DecodeError(path, reason)))
  codec.encode_json(payload, raw)
  |> should.equal(Error(codec.EncodeError(path, reason)))
}

pub fn object_validation_retains_member_order_at_different_widths_test() {
  list.each([31, 32, 33, 39, 40, 41, 64], fn(width) {
    let names = names(width)
    let bound = load(object_schema(names, names))
    accepts(bound, value.Object(members(names)))
    accepts(bound, value.Object(list.reverse(members(names))))
  })
}

pub fn object_names_fail_in_input_order_before_property_values_test() {
  list.each([32, 33, 40, 41, 64], fn(width) {
    let names = names(width)
    let bound = load(object_schema(names, names))
    // An invalid declared value must lose to a name error anywhere in the input.
    let fields = [#("a", value.Bool(False)), ..members(list.drop(names, 1))]
    list.each([0, 31, 32, 39, 40, 64], fn(position) {
      let before = list.take(fields, position)
      let after = list.drop(fields, position)
      rejects(
        bound,
        value.Object(list.append(before, [#("extra", value.Null), ..after])),
        [Field("extra")],
        codec.UnknownField,
      )
      rejects(
        bound,
        value.Object(list.append(before, [#("a", value.Null), ..after])),
        [Field("a")],
        codec.DuplicateField,
      )
      // Competing name errors still choose the first encountered failure.
      rejects(
        bound,
        value.Object(
          list.append(before, [
            #("extra", value.Null),
            #("extra", value.Null),
            #("a", value.Null),
            ..after
          ]),
        ),
        [Field("extra")],
        codec.UnknownField,
      )
    })
    rejects(
      bound,
      value.Object(
        list.append(fields, [
          #("a", value.Null),
          #("extra", value.Null),
        ]),
      ),
      [Field("a")],
      codec.DuplicateField,
    )
  })
}

pub fn object_property_failures_follow_normalized_schema_order_test() {
  list.each([32, 33, 40, 41, 64], fn(width) {
    let names = names(width)
    // Reversing schema and input order must not change the first property error.
    let bound = load(object_schema(list.reverse(names), names))
    let tail = members(list.drop(names, 2))
    rejects(
      bound,
      value.Object(
        list.append(tail, [
          #("b", value.Bool(False)),
          #("a", value.Null),
        ]),
      ),
      [Field("a")],
      codec.ExpectedString,
    )
    rejects(
      bound,
      value.Object(list.append(tail, [#("b", value.Bool(False))])),
      [Field("a")],
      codec.MissingField,
    )
  })
}

pub fn optional_absence_does_not_accept_present_null_test() {
  list.each([40, 41, 64], fn(width) {
    let names = names(width)
    let bound = load(object_schema(names, ["a"]))
    let fields = [
      #("a", value.String("present")),
      ..members(list.drop(names, 2))
    ]
    accepts(bound, value.Object(fields))
    rejects(
      bound,
      value.Object(list.append(fields, [#("b", value.Null)])),
      [Field("b")],
      codec.ExpectedString,
    )
  })
}

pub fn object_names_preserve_unicode_and_javascript_sensitive_keys_test() {
  list.each([0, 64], fn(width) {
    let names =
      list.append(
        ["", "雪🚀", "é", "e\u{301}", "__proto__", "constructor"],
        list.take(names(64), width),
      )
    let bound = load(object_schema(names, names))
    let fields = members(names)
    accepts(bound, value.Object(list.reverse(fields)))
    rejects(
      bound,
      value.Object(list.append(fields, [#("雪🚀", value.Null)])),
      [Field("雪🚀")],
      codec.DuplicateField,
    )
  })
}

pub fn wide_nested_object_errors_retain_full_paths_test() {
  let names = names(64)
  let bound =
    load(
      value.Object([
        #("type", value.String("array")),
        #("items", object_schema(names, names)),
      ]),
    )
  let valid = value.Object(members(names))
  let invalid =
    value.Object(list.append(members(names), [#("extra", value.Null)]))
  rejects(
    bound,
    value.Array([valid, invalid]),
    [Index(1), Field("extra")],
    codec.UnknownField,
  )
  rejects(
    bound,
    value.Array([
      valid,
      value.Object([#("a", value.Null), ..members(list.drop(names, 1))]),
    ]),
    [Index(1), Field("a")],
    codec.ExpectedString,
  )
}
