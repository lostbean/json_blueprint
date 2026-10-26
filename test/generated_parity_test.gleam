// Generated entry points preserve runtime values, errors, and error precedence.
import generated/order_codec
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value
import materialize_fixtures as fixtures

pub fn multi_error_parity_test() {
  let runtime = fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  int.range(0, 256, Nil, fn(_, seed) {
    let fields = [
      #("order_id", case seed % 4 {
        0 -> numeric(10)
        1 -> numeric(0)
        2 -> value.String("bad")
        _ -> value.Null
      }),
      #("items_\"list\"", case seed / 4 % 4 {
        0 -> value.Array([])
        1 -> value.Bool(False)
        2 -> value.Array([value.Array([value.String("x"), value.Null])])
        _ -> value.Array([value.Array([])])
      }),
      #("type", case seed / 16 % 4 {
        0 -> value.Bool(True)
        1 -> value.Null
        2 -> numeric(1)
        _ -> value.String("true")
      }),
      #("status", case seed / 64 % 4 {
        0 -> value.String("pending")
        1 -> value.String("unknown")
        2 -> value.Null
        _ -> value.Array([])
      }),
    ]
    let missing = list.filter(fields, fn(field) { field.0 != "order_id" })
    let variants = [
      fields,
      list.reverse(fields),
      missing,
      [#("extra", value.Null), ..fields],
      [#("order_id", numeric(4)), ..fields],
    ]
    list.each(variants, fn(fields) {
      let raw = value.Object(fields)
      let text = value.to_string(raw)
      let expected_value = codec.decode(runtime, raw)
      let expected_text = codec.decode_json(runtime, text)
      codec.decode(generated, raw) |> should.equal(expected_value)
      order_codec.decode_order(raw) |> should.equal(expected_value)
      codec.decode_json(generated, text) |> should.equal(expected_text)
      order_codec.decode_order_json(text) |> should.equal(expected_text)
    })
    Nil
  })
}

pub fn invalid_encoding_parity_test() {
  let runtime = fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  list.each([0, 1, 999_999, 1_000_000], fn(id) {
    list.each([fixtures.Pending, fixtures.Unmapped], fn(status) {
      list.each([None, Some(None), Some(Some("雪\n"))], fn(note) {
        let item = fixtures.Order(id, [#("x", 1)], note, True, status)
        let expected = codec.encode(runtime, item)
        let expected_text = codec.encode_json(runtime, item)
        codec.encode(generated, item) |> should.equal(expected)
        order_codec.encode_order(item) |> should.equal(expected)
        codec.encode_json(generated, item) |> should.equal(expected_text)
        order_codec.encode_order_json(item) |> should.equal(expected_text)
      })
    })
  })
}

fn numeric(n: Int) -> value.Value {
  let assert Ok(n) = number.from_int(n)
  value.Number(n)
}
