import commerce/order
import consumer_support as fixture
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should
import json/blueprint/codec.{DecodeError, EncodeError, Field, Index}
import json/blueprint/contract
import json/blueprint/value
import order_app
import projection/numbers

pub fn native_order_round_trips_test() {
  let schema_codec = order.order_codec()
  let original = fixture.sample(2)
  let assert Ok(encoded) = codec.encode_json(schema_codec, original)
  codec.decode_json(schema_codec, encoded) |> should.equal(Ok(original))
  codec.encode(schema_codec, original)
  |> should.equal(codec.encode(fixture.handwritten_codec(), original))
}

pub fn loaded_schema_matches_generated_and_handwritten_codecs_test() {
  let loaded = fixture.loaded("order")
  let assert Ok(generated) = contract.from_codec(order.order_codec())
  let assert Ok(handwritten) = contract.from_codec(fixture.handwritten_codec())
  contract.same_schema(loaded, generated) |> should.be_true
  contract.same_schema(loaded, handwritten) |> should.be_true
  let assert Ok(schema) = codec.schema(order.order_codec())
  codec.description(schema)
  |> should.equal(Some("An order accepted at the application boundary"))
}

pub fn optional_nullable_preserves_missing_null_and_present_test() {
  let original = fixture.sample(1)
  let schema_codec = order.order_codec()
  list.each([None, Some(None), Some(Some("note"))], fn(note) {
    let candidate = order.Order(..original, note:, labels: None)
    let assert Ok(encoded) = codec.encode(schema_codec, candidate)
    let assert value.Object(members) = encoded
    list.key_find(members, "note")
    |> should.equal(case note {
      None -> Error(Nil)
      Some(None) -> Ok(value.Null)
      Some(Some(text)) -> Ok(value.String(text))
    })
    list.key_find(members, "labels") |> should.equal(Error(Nil))
    codec.decode(schema_codec, encoded) |> should.equal(Ok(candidate))
  })
}

pub fn invalid_native_values_have_located_encoding_failures_test() {
  let original = fixture.sample(1)
  let assert [item] = original.items
  let invalid =
    order.Order(..original, items: [order.OrderItemsItem(..item, quantity: 0)])
  codec.encode(order.order_codec(), invalid)
  |> should.equal(
    Error(EncodeError(
      [Field("items"), Index(0), Field("quantity")],
      codec.IntegerOutsideRange(1, 100),
    )),
  )
  let invalid_price =
    order.Order(..original, items: [
      order.OrderItemsItem(..item, unit_price: fixture.decimal("100000")),
    ])
  codec.encode_json(order.order_codec(), invalid_price)
  |> should.equal(
    Error(EncodeError(
      [Field("items"), Index(0), Field("unitPrice")],
      codec.NumberOutsideRange(
        fixture.decimal("0"),
        fixture.decimal("99999.99"),
      ),
    )),
  )
}

pub fn malformed_inputs_are_recoverable_test() {
  let schema_codec = order.order_codec()
  let assert Ok(valid) = codec.encode(schema_codec, fixture.sample(1))
  codec.decode(schema_codec, replace(valid, "orderId", value.String("42")))
  |> should.equal(Error(DecodeError([Field("orderId")], codec.ExpectedInt)))
  codec.decode(schema_codec, replace(valid, "items", value.Array([value.Null])))
  |> should.equal(
    Error(DecodeError([Field("items"), Index(0)], codec.ExpectedObject)),
  )
  let assert Error(DecodeError([], codec.InvalidJson(_))) =
    codec.decode_json(schema_codec, "{")
  codec.decode(schema_codec, valid) |> should.equal(Ok(fixture.sample(1)))
}

pub fn application_envelope_and_business_policy_remain_caller_owned_test() {
  let submission = order_app.Submission("trace-123", fixture.sample(1))
  let assert Ok(text) =
    codec.encode_json(order_app.submission_codec(), submission)
  order_app.accept(text) |> should.equal(Ok(submission))
  let inactive = order.Order(..submission.order, active: False)
  let assert Ok(text) =
    codec.encode_json(
      order_app.submission_codec(),
      order_app.Submission("trace-123", inactive),
    )
  order_app.accept(text) |> should.equal(Error(order_app.InactiveOrder))
  let assert Ok(text) =
    codec.encode_json(
      order_app.submission_codec(),
      order_app.Submission("trace-123", fixture.sample(0)),
    )
  order_app.accept(text) |> should.equal(Error(order_app.EmptyOrder))
  let assert Error(order_app.InvalidWire(DecodeError([], codec.InvalidJson(_)))) =
    order_app.accept("not JSON")
}

pub fn supported_acceptance_corpus_agrees_test() {
  let typed = order.order_codec()
  let loaded = fixture.loaded("order")
  let assert Ok(base) = codec.encode(typed, fixture.sample(1))
  let assert value.Object(root) = base
  let assert Ok(value.Array([item])) = list.key_find(root, "items")
  list.each(["0", "1", "2", "100", "101"], fn(quantity) {
    list.each(["-0.1", "0", "0.1", "99999.99", "100000"], fn(price) {
      let item =
        replace(item, "quantity", value.Number(fixture.decimal(quantity)))
        |> replace("unitPrice", value.Number(fixture.decimal(price)))
      list.each([0, 1, 3], fn(count) {
        let candidate =
          replace(base, "items", value.Array(list.repeat(item, count)))
        assert_acceptance(loaded, typed, candidate)
      })
    })
  })
  list.each(
    [
      value.Null,
      value.Bool(True),
      value.String("order"),
      value.Array([]),
      value.Object([]),
    ],
    fn(candidate) { assert_acceptance(loaded, typed, candidate) },
  )
  list.each(root, fn(member) {
    assert_acceptance(loaded, typed, value.Object([member, ..root]))
    assert_acceptance(
      loaded,
      typed,
      value.Object(list.filter(root, fn(existing) { existing.0 != member.0 })),
    )
  })
  assert_acceptance(
    loaded,
    typed,
    value.Object([#("unexpected", value.Null), ..root]),
  )
}

fn assert_acceptance(
  loaded: contract.Contract,
  typed: codec.Codec(order.Order),
  candidate: value.Value,
) {
  let decoded = codec.decode(typed, candidate)
  result.is_ok(decoded)
  |> should.equal(result.is_ok(contract.validate(loaded, candidate)))
  case decoded {
    Ok(native) -> {
      let assert Ok(encoded) = codec.encode(typed, native)
      contract.validate(loaded, encoded) |> result.is_ok |> should.be_true
      codec.decode(typed, encoded) |> should.equal(Ok(native))
    }
    Error(_) -> Nil
  }
}

pub fn exact_numbers_survive_native_generation_test() {
  let original =
    numbers.Numbers(
      decimal: fixture.decimal("1.234567890123456789e1000"),
      integer: 17,
    )
  let schema_codec = numbers.numbers_codec()
  let assert Ok(text) = codec.encode_json(schema_codec, original)
  codec.decode_json(schema_codec, text) |> should.equal(Ok(original))
  let assert Ok(loaded) = contract.from_codec(schema_codec)
  contract.same_schema(loaded, fixture.loaded("numbers")) |> should.be_true
}

pub fn native_integer_projection_is_distinct_from_schema_acceptance_test() {
  let candidate =
    value.Object([
      #("decimal", value.Number(fixture.decimal("1e1000"))),
      #("integer", value.Number(fixture.decimal("1e30"))),
    ])
  contract.validate(fixture.loaded("numbers"), candidate)
  |> result.is_ok
  |> should.be_true
  codec.decode(numbers.numbers_codec(), candidate)
  |> should.equal(Error(DecodeError([Field("integer")], codec.ExpectedInt)))
}

fn replace(
  raw: value.Value,
  name: String,
  replacement: value.Value,
) -> value.Value {
  let assert value.Object(members) = raw
  value.Object(
    list.map(members, fn(member) {
      case member.0 == name {
        True -> #(name, replacement)
        False -> member
      }
    }),
  )
}

@target(erlang)
pub fn integer_above_javascript_safe_range_projects_on_erlang_test() {
  let assert Ok(decoded) =
    codec.decode_json(
      numbers.numbers_codec(),
      "{\"decimal\":0,\"integer\":9007199254740993}",
    )
  decoded.integer |> should.equal(9_007_199_254_740_993)
  let assert Ok(text) = codec.encode_json(numbers.numbers_codec(), decoded)
  let assert Ok(raw) = value.parse(text, value.default_limits())
  contract.validate(fixture.loaded("numbers"), raw)
  |> result.is_ok
  |> should.be_true
}

@target(javascript)
pub fn integer_above_javascript_safe_range_is_refused_on_javascript_test() {
  let text = "{\"decimal\":0,\"integer\":9007199254740993}"
  let assert Ok(raw) = value.parse(text, value.default_limits())
  contract.validate(fixture.loaded("numbers"), raw)
  |> result.is_ok
  |> should.be_true
  codec.decode_json(numbers.numbers_codec(), text)
  |> should.equal(Error(DecodeError([Field("integer")], codec.ExpectedInt)))
}
