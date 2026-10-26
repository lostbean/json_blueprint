// Generated strict entry points share runtime admission and numeric projection.
import generated/mapping_codec
import generated/order_codec
import generated_mapping_fixtures
import gleam/list
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/value
import materialize_fixtures

pub fn strict_numeric_projection_parity_test() {
  let runtime = codegen.runtime(generated_mapping_fixtures.definition())
  let generated = mapping_codec.mapping_codec()
  list.each(
    [
      "1", "1.0", "1e0", "10.0", "1.00000000000000001", "9.99999999999999999",
      "9007199254740993", "-9007199254740993", "1e400", "-1e400", "1e-400", "-0",
      "0.000", "1e10000", "1e-10000", "true", "null", "\"1\"", "[]", "{}",
      "1 trailing", "01", "+1", "1.", "1e", "1e+", "[1,]",
    ],
    fn(source) {
      let expected = codec.decode_json(runtime, source)
      codec.decode_json(generated, source) |> should.equal(expected)
      mapping_codec.decode_mapping_json(source) |> should.equal(expected)
      let nested = "[1," <> source <> "]"
      codec.decode_json(codec.list(generated), nested)
      |> should.equal(codec.decode_json(codec.list(runtime), nested))
    },
  )
}

pub fn strict_parser_policy_and_byte_limit_parity_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  list.each(
    [
      "{\"order_id\":1,\"order_id\":2}",
      "{\"order_id\":1,\"\\u006frder_id\":2}",
      "{\"ignored\":{\"x\":1,\"\\u0078\":2}}",
      "{\"ignored\":\"\\ud800\"}",
      "{\"ignored\":\"\\udc00\"}",
      "{\"ignored\":\"\\ud83d\\ude00\"}",
      "{\"__proto__\":1,\"\\u005f_proto__\":2}",
      "{\"x\":1}garbage",
      "{\"x\":",
      "[[]]",
      "\u{feff}null",
      "{\"items_\\\"list\\\"\":[]}",
    ],
    fn(source) {
      let expected = codec.decode_json(runtime, source)
      codec.decode_json(generated, source) |> should.equal(expected)
      order_codec.decode_order_json(source) |> should.equal(expected)
      list.each([0, 1, 5, 1000], fn(bound) {
        let limits = value.with_max_bytes(value.default_limits(), bound)
        codec.decode_json_with_limits(generated, source, limits)
        |> should.equal(codec.decode_json_with_limits(runtime, source, limits))
      })
    },
  )
}
