import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleeunit/should
import json/blueprint/number
import json/blueprint/value

fn num(token: String) -> number.Number {
  let assert Ok(parsed) = number.parse(token, number.default_limits())
  parsed
}

fn parse(text: String) -> value.Value {
  let assert Ok(parsed) = value.parse(text, value.default_limits())
  parsed
}

pub fn object_rejects_a_repeated_key_test() {
  value.object([]) |> should.equal(Ok(value.Object([])))

  value.object([#("first", value.String("a")), #("second", value.String("b"))])
  |> should.equal(
    Ok(
      value.Object([
        #("first", value.String("a")),
        #("second", value.String("b")),
      ]),
    ),
  )

  value.object([
    #("duplicate", value.String("first")),
    #("other", value.String("middle")),
    #("duplicate", value.String("second")),
  ])
  |> should.equal(Error(value.DuplicateKey("duplicate")))
}

pub fn to_string_is_compact_and_keeps_member_order_test() {
  value.Object([
    #("b", value.Array([value.Null, value.Bool(True), value.Bool(False)])),
    #("a", value.String("x\"y")),
    #("n", value.Number(num("12.50"))),
    #("i", value.Number(num("-42"))),
    #("big", value.Number(num("1e60"))),
  ])
  |> value.to_string
  |> should.equal(
    "{\"b\":[null,true,false],\"a\":\"x\\\"y\",\"n\":12.5,\"i\":-42,\"big\":1e60}",
  )
}

pub fn to_string_writes_plain_decimals_in_a_readable_range_test() {
  [
    #("0.1", "0.1"),
    #("-12.5", "-12.5"),
    #("1.0000001e-7", "0.00000010000001"),
    #("1e-7", "0.0000001"),
    #("1e-8", "1e-8"),
    #("123456789012345678.5", "123456789012345678.5"),
    #("1.5e20", "150000000000000000000"),
    #("1.25e60", "1.25e60"),
    #("1e60", "1e60"),
  ]
  |> list.each(fn(pair) {
    value.to_string(value.Number(num(pair.0))) |> should.equal(pair.1)
    // The text reads back as the same number.
    value.parse(pair.1, value.default_limits())
    |> should.equal(Ok(value.Number(num(pair.0))))
  })
}

pub fn to_json_is_exact_test() {
  let assert Ok(converted) =
    value.to_json(parse("{\"a\":[1,-2,0.1,2.5,null,true,\"s\"],\"b\":{}}"))
  json.to_string(converted)
  |> should.equal("{\"a\":[1,-2,0.1,2.5,null,true,\"s\"],\"b\":{}}")
}

pub fn to_json_writes_large_floats_that_read_back_the_same_test() {
  let assert Ok(converted) = value.to_json(parse("[1e20]"))
  let assert Ok(round_trip) =
    value.parse(json.to_string(converted), value.default_limits())
  round_trip |> should.equal(parse("[1e20]"))
}

pub fn to_json_refuses_numbers_without_an_exact_form_test() {
  value.to_json(parse("[1, 1e400]")) |> should.equal(Error(num("1e400")))
  value.to_json(parse("0.1000000000000000000001"))
  |> should.equal(Error(num("0.1000000000000000000001")))
}

pub fn decoder_reads_gleam_json_data_test() {
  let assert Ok(decoded) =
    json.parse(
      "{\"a\":[1,2.5,null,true,\"x\"],\"b\":{\"c\":false}}",
      value.decoder(),
    )
  let assert value.Object(members) = decoded
  list.key_find(members, "a")
  |> should.equal(
    Ok(
      value.Array([
        value.Number(num("1")),
        value.Number(num("2.5")),
        value.Null,
        value.Bool(True),
        value.String("x"),
      ]),
    ),
  )
  list.key_find(members, "b")
  |> should.equal(Ok(value.Object([#("c", value.Bool(False))])))
}

pub fn decoder_reads_floats_as_their_shortest_decimal_test() {
  json.parse("[0.1, 1.0, 1e20]", value.decoder())
  |> should.equal(
    Ok(
      value.Array([
        value.Number(num("0.1")),
        value.Number(num("1")),
        value.Number(num("1e20")),
      ]),
    ),
  )
}

pub fn decoder_runs_on_dynamic_data_test() {
  let data =
    dict.from_list([#("k", [1, 2])])
    |> json.dict(fn(key) { key }, fn(items) { json.array(items, json.int) })
    |> json.to_string
  let assert Ok(raw) = json.parse(data, decode.dynamic)
  decode.run(raw, value.decoder())
  |> should.equal(
    Ok(
      value.Object([
        #("k", value.Array([value.Number(num("1")), value.Number(num("2"))])),
      ]),
    ),
  )
}

pub fn describe_parse_error_names_the_limit_setter_test() {
  let limits = value.default_limits() |> value.with_max_bytes(4)
  let assert Error(error) = value.parse("[1,2,3]", limits)
  value.describe_parse_error(error)
  |> should.equal(
    "invalid JSON at line 1, column 1: more than 4 bytes (value.with_max_bytes)",
  )
  value.is_limit_exceeded(error) |> should.be_true

  let assert Error(error) =
    value.parse("{\"secret\": tru}", value.default_limits())
  value.describe_parse_error(error)
  |> should.equal("invalid JSON at line 1, column 12: unexpected character")
  value.is_limit_exceeded(error) |> should.be_false
}
