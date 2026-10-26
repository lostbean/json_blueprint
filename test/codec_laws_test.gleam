import generated/order_codec
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value
import materialize_fixtures as fixtures
import vanilla_order

// Deterministic varied values exercise the law across independently authored,
// interpreted and compiled conversions. The native comparison is restricted to
// representable inputs: it cannot certify duplicate or exact-token admission.
pub fn generated_codec_roundtrip_and_schema_laws_test() {
  let handwritten = fixtures.build_order_codec()
  let interpreted = codegen.runtime(fixtures.order_definition())
  let compiled = order_codec.order_codec()
  let assert Ok(schema) = codec.schema(handwritten)
  let assert Ok(expected_contract) = contract.from_codec(handwritten)
  let assert Ok(loaded) = contract.load(codec.schema_document(schema))
  contract.same_schema(expected_contract, loaded) |> should.be_true
  codec.schema(compiled) |> should.equal(Ok(schema))
  codec.schema_json(interpreted) |> should.equal(codec.schema_json(handwritten))

  int.range(0, 128, Nil, fn(_, seed) {
    let candidate = order(seed)
    let assert Ok(encoded) = codec.encode(handwritten, candidate)
    let assert Ok(wire) = codec.encode_json(handwritten, candidate)
    order_codec.encode_order(candidate) |> should.equal(Ok(encoded))
    order_codec.encode_order_json(candidate) |> should.equal(Ok(wire))
    let assert Ok(native) = vanilla_order.encode(candidate)
    json.to_string(native) |> should.equal(wire)
    json.parse(wire, vanilla_order.decoder()) |> should.equal(Ok(candidate))

    let assert Ok(witness) = contract.validate(loaded, encoded)
    contract.value(witness) |> should.equal(encoded)
    codec.encode(contract.value_codec(loaded), encoded)
    |> should.equal(Ok(encoded))
    list.each([handwritten, interpreted, compiled], fn(current) {
      codec.encode(current, candidate) |> should.equal(Ok(encoded))
      codec.decode(current, encoded) |> should.equal(Ok(candidate))
      codec.decode_json(current, wire) |> should.equal(Ok(candidate))
      contract.decode(current, witness) |> should.equal(Ok(candidate))
    })
    order_codec.decode_order_json(wire) |> should.equal(Ok(candidate))
    order_codec.decode_order_json_native(wire) |> should.equal(Ok(candidate))

    // Object order and surrounding whitespace cannot change the typed value.
    let assert value.Object(fields) = encoded
    let reordered = value.Object(list.reverse(fields))
    let spaced = " \r\n" <> value.to_string(reordered) <> "\t "
    codec.decode_json(handwritten, spaced) |> should.equal(Ok(candidate))
    order_codec.decode_order_json(spaced) |> should.equal(Ok(candidate))
    contract.validate(loaded, reordered) |> should.be_ok
    Nil
  })
}

pub fn generated_codec_rejects_single_fault_mutations_test() {
  let handwritten = fixtures.build_order_codec()
  let compiled = order_codec.order_codec()
  let assert Ok(schema_contract) = contract.from_codec(handwritten)
  let assert Ok(zero) = number.from_int(0)
  int.range(0, 32, Nil, fn(_, seed) {
    let assert Ok(value.Object(fields)) = codec.encode(handwritten, order(seed))
    let mutations = [
      #(
        value.Object(list.filter(fields, fn(pair) { pair.0 != "order_id" })),
        codec.DecodeError([codec.Field("order_id")], codec.MissingField),
      ),
      #(
        replace(fields, "order_id", value.Number(zero)),
        codec.DecodeError(
          [codec.Field("order_id")],
          codec.IntegerOutsideRange(1, 999_999),
        ),
      ),
      #(
        replace(fields, "status", value.String("not-a-status")),
        codec.DecodeError([codec.Field("status")], codec.UnknownEnumLabel),
      ),
      #(
        value.Object([#("extra", value.Null), ..fields]),
        codec.DecodeError([codec.Field("extra")], codec.UnknownField),
      ),
      #(
        replace(
          fields,
          "items_\"list\"",
          value.Array([value.Array([value.String("item"), value.Bool(False)])]),
        ),
        codec.DecodeError(
          [codec.Field("items_\"list\""), codec.Index(0), codec.Index(1)],
          codec.ExpectedInt,
        ),
      ),
    ]
    list.each(mutations, fn(mutation) {
      let #(invalid, expected) = mutation
      contract.validate(schema_contract, invalid) |> should.be_error
      codec.encode(contract.value_codec(schema_contract), invalid)
      |> should.be_error
      list.each([handwritten, compiled], fn(current) {
        codec.decode(current, invalid) |> should.equal(Error(expected))
        codec.decode_json(current, value.to_string(invalid))
        |> should.equal(Error(expected))
      })
      order_codec.decode_order(invalid) |> should.equal(Error(expected))
      order_codec.decode_order_json(value.to_string(invalid))
      |> should.equal(Error(expected))
    })
    // A duplicate is preserved by raw Value rendering, but every strict text
    // entry point must reject it before codec field conversion.
    let assert [first, ..] = fields
    let duplicate = value.to_string(value.Object([first, ..fields]))
    let assert Error(codec.DecodeError([], codec.InvalidJson(error))) =
      codec.decode_json(handwritten, duplicate)
    error.reason |> should.equal(value.DuplicateObjectKey)
    order_codec.decode_order_json(duplicate)
    |> should.equal(Error(codec.DecodeError([], codec.InvalidJson(error))))
  })
}

fn replace(
  fields: List(#(String, value.Value)),
  name: String,
  item: value.Value,
) -> value.Value {
  value.Object(
    list.map(fields, fn(pair) {
      case pair.0 == name {
        True -> #(name, item)
        False -> pair
      }
    }),
  )
}

fn order(seed: Int) -> fixtures.Order {
  let text = case seed % 4 {
    0 -> ""
    1 -> "quote \" slash \\ line\n\t\r"
    2 -> "雪 🚀 á"
    _ -> "\u{0000}\u{2028}\u{2029}"
  }
  let note = case seed % 3 {
    0 -> None
    1 -> Some(None)
    _ -> Some(Some(text))
  }
  let status = case seed % 4 {
    0 -> fixtures.Pending
    1 -> fixtures.Processing
    2 -> fixtures.ShippedQuoted
    _ -> fixtures.DeliveredUnicode
  }
  let items = case seed % 7 {
    0 -> []
    count ->
      list.index_map(list.repeat(Nil, count), fn(_, index) {
        #(text, seed - 64 + index)
      })
  }
  let id = case seed {
    0 -> 1
    1 -> 999_999
    _ -> 1 + seed * 7919 % 999_999
  }
  fixtures.Order(id, items, note, seed % 2 == 0, status)
}
