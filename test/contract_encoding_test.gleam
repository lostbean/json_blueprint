//// The dynamic Value codec enforces finite contract acceptance on output.
//// All fixtures use the public codec, contract, number, and value modules.

import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec.{Field, Index}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

fn parsed(text: String) -> value.Value {
  let assert Ok(raw) = value.parse(text, value.default_limits())
  raw
}

fn dynamic(native: codec.Codec(a)) -> codec.Codec(value.Value) {
  let assert Ok(bound) = contract.from_codec(native)
  contract.value_codec(bound)
}

pub fn value_codec_rejects_out_of_range_encoding_test() {
  let payload = dynamic(codec.integer_between(1, 10))
  let invalid = parsed("99")

  codec.encode(payload, invalid)
  |> should.equal(
    Error(codec.EncodeError([], codec.IntegerOutsideRange(1, 10))),
  )
  codec.encode_json(payload, invalid)
  |> should.equal(
    Error(codec.EncodeError([], codec.IntegerOutsideRange(1, 10))),
  )
  codec.to_json(payload, invalid)
  |> should.equal(
    Error(codec.EncodeError([], codec.IntegerOutsideRange(1, 10))),
  )
}

pub fn value_codec_checks_structure_without_refinements_test() {
  let payload = dynamic(codec.list(codec.string()))
  codec.encode(payload, parsed("[\"valid\", false]"))
  |> should.equal(Error(codec.EncodeError([Index(1)], codec.ExpectedString)))

  let record =
    dynamic({
      use name <- codec.field("name", codec.string(), get: fn(item) { item })
      codec.success(name)
    })
  codec.encode(record, parsed("{}"))
  |> should.equal(Error(codec.EncodeError([Field("name")], codec.MissingField)))
  // Member checks precede a wrong value in a declared field.
  codec.encode(record, parsed("{\"name\":false,\"extra\":true}"))
  |> should.equal(
    Error(codec.EncodeError([Field("extra")], codec.UnknownField)),
  )
  codec.encode(
    record,
    value.Object([
      #("name", value.Bool(False)),
      #("name", value.String("again")),
    ]),
  )
  |> should.equal(
    Error(codec.EncodeError([Field("name")], codec.DuplicateField)),
  )
}

pub fn value_codec_preserves_exact_numbers_and_member_order_test() {
  let assert Ok(minimum) = number.parse("1e399", number.default_limits())
  let assert Ok(maximum) = number.parse("1e401", number.default_limits())
  let assert Ok(huge) = number.parse("1e400", number.default_limits())
  let payload =
    dynamic({
      use amount <- codec.field(
        "amount",
        codec.number_between(minimum, maximum),
        get: fn(item) { item.0 },
      )
      use note <- codec.field("note", codec.string(), get: fn(item) { item.1 })
      codec.success(#(amount, note))
    })
  let valid = parsed("{\"note\":\"retained order\",\"amount\":1e400}")
  codec.encode(payload, valid) |> should.equal(Ok(valid))
  codec.encode_json(payload, valid)
  |> should.equal(Ok(value.to_string(valid)))
  codec.to_json(payload, valid)
  |> should.equal(
    Error(codec.EncodeError(
      [Field("amount")],
      codec.UnrepresentableNumber(huge),
    )),
  )
  codec.encode(payload, parsed("{\"note\":\"too large\",\"amount\":1e402}"))
  |> should.equal(
    Error(codec.EncodeError(
      [Field("amount")],
      codec.NumberOutsideRange(minimum, maximum),
    )),
  )

  // Mathematical integer acceptance does not invoke native Int conversion.
  codec.encode(dynamic(codec.int()), value.Number(huge))
  |> should.equal(Ok(value.Number(huge)))
}

pub fn value_codec_nullable_preserves_null_and_checks_present_value_test() {
  let payload = dynamic(codec.nullable(codec.integer_between(1, 10)))
  codec.encode(payload, value.Null) |> should.equal(Ok(value.Null))
  codec.encode(payload, parsed("3")) |> should.equal(Ok(parsed("3")))
  codec.encode(payload, parsed("0"))
  |> should.equal(
    Error(codec.EncodeError([], codec.IntegerOutsideRange(1, 10))),
  )
  // The typed nullable path keeps its native Option interface.
  codec.encode(codec.nullable(codec.int()), None)
  |> should.equal(Ok(value.Null))
  codec.encode(codec.nullable(codec.int()), Some(3))
  |> should.equal(Ok(parsed("3")))
}

pub fn value_codec_any_retains_raw_duplicate_objects_test() {
  let raw =
    value.Object([
      #("same", value.String("first")),
      #("same", value.Bool(False)),
    ])
  let payload = dynamic(codec.value())
  codec.encode(payload, raw) |> should.equal(Ok(raw))
  codec.decode(payload, raw) |> should.equal(Ok(raw))
}
