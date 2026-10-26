// Named callbacks are observable: preserve their order, count, and timing.
import generated/mapping_codec
import generated_mapping_fixtures as fixtures
import gleam/list
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/number
import json/blueprint/value

fn observe(work: fn() -> a) -> #(a, String) {
  fixtures.reset()
  let result = work()
  #(result, fixtures.trace())
}

fn runtime() -> codec.Codec(Int) {
  codegen.runtime(fixtures.definition())
}

pub fn mapping_construction_callback_parity_test() {
  let expected =
    observe(fn() {
      let _ = runtime()
      Nil
    })
  observe(fn() {
    let _ = mapping_codec.mapping_codec()
    Nil
  })
  |> should.equal(expected)
  expected |> should.equal(#(Nil, ""))
}

pub fn mapping_decode_callback_parity_test() {
  list.each(
    [
      "5",
      "11",
      "false",
      "1.00000000000000001",
      "5 trailing",
      "{\"x\":1,\"x\":2}",
    ],
    fn(source) {
      let expected = observe(fn() { codec.decode_json(runtime(), source) })
      observe(fn() { codec.decode_json(mapping_codec.mapping_codec(), source) })
      |> should.equal(expected)
      observe(fn() { mapping_codec.decode_mapping_json(source) })
      |> should.equal(expected)
      case source {
        "5" -> expected |> should.equal(#(Ok(5), "inner_from;outer_from;"))
        _ -> expected.1 |> should.equal("")
      }
    },
  )
  let assert Ok(valid) = number.from_int(5)
  let assert Ok(invalid) = number.from_int(11)
  list.each(
    [value.Number(valid), value.Number(invalid), value.Bool(False)],
    fn(raw) {
      let expected = observe(fn() { codec.decode(runtime(), raw) })
      observe(fn() { codec.decode(mapping_codec.mapping_codec(), raw) })
      |> should.equal(expected)
      observe(fn() { mapping_codec.decode_mapping(raw) })
      |> should.equal(expected)
    },
  )
}

pub fn mapping_encode_callback_parity_test() {
  list.each([5, 11], fn(item) {
    let expected_text = observe(fn() { codec.encode_json(runtime(), item) })
    observe(fn() { codec.encode_json(mapping_codec.mapping_codec(), item) })
    |> should.equal(expected_text)
    observe(fn() { mapping_codec.encode_mapping_json(item) })
    |> should.equal(expected_text)
    expected_text.1 |> should.equal("outer_to;inner_to;")
    let expected_value = observe(fn() { codec.encode(runtime(), item) })
    observe(fn() { codec.encode(mapping_codec.mapping_codec(), item) })
    |> should.equal(expected_value)
    observe(fn() { mapping_codec.encode_mapping(item) })
    |> should.equal(expected_value)
    expected_value.1 |> should.equal("outer_to;inner_to;")
  })
}
