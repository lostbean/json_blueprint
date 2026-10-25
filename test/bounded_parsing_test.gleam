import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/order
import gleam/string
import gleeunit/should
import json/blueprint
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value

const one_mib = 1_048_576

@external(erlang, "bounded_parsing_test_ffi", "flat_size_words")
@external(javascript, "./bounded_parsing_test_ffi.mjs", "flat_size_words")
fn flat_size_words(term: a) -> Int

@external(erlang, "bounded_parsing_test_ffi", "shares_input")
@external(javascript, "./bounded_parsing_test_ffi.mjs", "shares_input")
fn shares_input(text: String) -> Bool

/// `text` padded with trailing spaces to exactly `size` bytes.
fn padded(text: String, size: Int) -> String {
  text <> string.repeat(" ", size - string.byte_size(text))
}

fn byte_limit_failure(max: Int) -> codec.DecodeError {
  codec.DecodeError(
    [],
    codec.InvalidJson(value.ParseError(
      value.Location(0, 1, 1),
      value.ByteLimitExceeded(max),
    )),
  )
}

fn nested_arrays(depth: Int) -> String {
  string.repeat("[", depth) <> string.repeat("]", depth)
}

pub fn default_limits_bound_only_input_bytes_test() {
  let limits = value.default_limits()
  value.parse(padded("[1]", one_mib), limits) |> should.be_ok
  let assert Error(value.ParseError(_, value.ByteLimitExceeded(1_048_576))) =
    value.parse(padded("[1]", one_mib + 1), limits)
  value.parse(nested_arrays(100), limits) |> should.be_ok
}

/// An array of `count` ones: `count + 1` values.
fn ones(count: Int) -> String {
  "[" <> string.repeat("1,", count - 1) <> "1]"
}

pub fn value_count_is_not_a_global_admission_cap_test() {
  let assert Ok(decoded) =
    codec.decode_json(codec.list(codec.int()), ones(262_144))
  list.length(decoded) |> should.equal(262_144)
}

pub fn strict_decode_admits_one_mib_and_rejects_one_byte_more_test() {
  let ints = codec.list(codec.int())
  codec.decode_json(ints, padded("[1]", one_mib))
  |> should.equal(Ok([1]))
  codec.decode_json(ints, padded("[1]", one_mib + 1))
  |> should.equal(Error(byte_limit_failure(one_mib)))
}

pub fn strict_decode_counts_utf8_bytes_test() {
  // Each "é" is one UTF-16 code unit but two UTF-8 bytes.
  let fits = "\"" <> string.repeat("é", { one_mib - 2 } / 2) <> "\""
  let over = "\"" <> string.repeat("é", one_mib / 2) <> "\""
  string.byte_size(fits) |> should.equal(one_mib)
  codec.decode_json(codec.string(), fits) |> should.be_ok
  codec.decode_json(codec.string(), over)
  |> should.equal(Error(byte_limit_failure(one_mib)))
  blueprint.decode(blueprint.string(), fits) |> should.be_ok
  blueprint.decode(blueprint.string(), over) |> should.be_error
}

pub fn raised_limits_admit_larger_text_test() {
  let limits =
    value.default_limits()
    |> value.with_max_bytes(2 * one_mib)
  codec.decode_json_with_limits(
    codec.list(codec.int()),
    padded("[1]", one_mib + 1),
    limits,
  )
  |> should.equal(Ok([1]))
  value.parse(nested_arrays(100), limits) |> should.be_ok
}

pub fn legacy_decode_rejects_text_above_one_mib_test() {
  let decoder = blueprint.list(blueprint.int())
  blueprint.decode(decoder, padded("[1]", one_mib))
  |> should.equal(Ok([1]))
  blueprint.decode(decoder, padded("[1]", one_mib + 1))
  |> should.equal(
    Error(
      json.UnableToDecode([
        decode.DecodeError(
          expected: "JSON text of at most 1048576 bytes",
          found: "more than 1048576 bytes",
          path: [],
        ),
      ]),
    ),
  )
  blueprint.decode_with_max_bytes(
    decoder,
    padded("[1]", one_mib + 1),
    max_bytes: 2 * one_mib,
  )
  |> should.equal(Ok([1]))
  blueprint.decode_with_max_bytes(decoder, "[1]", max_bytes: 2)
  |> should.be_error
}

pub fn parsed_integers_are_compact_test() {
  // On the BEAM, an array element that holds a small integer takes a list
  // cell (2 words), a `value.Number` (3) and a number (3). Each number used
  // to carry its digits as a list, for 12 words per element.
  let count = 10_000
  let text = "[" <> string.repeat("7,", count - 1) <> "7]"
  let assert Ok(parsed) = value.parse(text, value.default_limits())
  case flat_size_words(parsed) {
    -1 -> Nil
    words -> { words <= 8 * count + 8 } |> should.be_true
  }
}

pub fn parsed_strings_do_not_share_the_input_test() {
  let text =
    "[\""
    <> string.repeat("a", 100)
    <> "\",\""
    <> string.repeat("b", 100)
    <> "\"]"
  let assert Ok(value.Array([value.String(first), value.String(second)])) =
    value.parse(text, value.default_limits())
  shares_input(first) |> should.be_false
  shares_input(second) |> should.be_false
}

pub fn compact_numbers_stay_canonical_test() {
  let limits = number.default_limits()
  let parse = fn(token) {
    let assert Ok(parsed) = number.parse(token, limits)
    parsed
  }
  let assert Ok(hundred) = number.from_int(100)
  let assert Ok(zero) = number.from_int(0)
  parse("100") |> should.equal(hundred)
  parse("1e2") |> should.equal(hundred)
  parse("100.00") |> should.equal(hundred)
  parse("-0") |> should.equal(zero)
  parse("0.0e5") |> should.equal(zero)
  let assert Ok(largest_small) = number.from_int(999_999_999_999_999)
  parse("999999999999999") |> should.equal(largest_small)
  parse("9.99999999999999e14") |> should.equal(largest_small)
  // 16 digits and fractions use the decimal representation.
  number.to_string(parse("1000000000000000")) |> should.equal("1e15")
  number.to_string(parse("-1234567890123456"))
  |> should.equal("-1.234567890123456e15")
  number.to_string(parse("-12.5")) |> should.equal("-1.25e1")
  number.compare(parse("1e15"), largest_small)
  |> should.equal(order.Gt)
  number.compare(parse("-1e15"), parse("-999999999999999"))
  |> should.equal(order.Lt)
  number.compare(parse("12.5"), parse("12"))
  |> should.equal(order.Gt)
  number.is_integer(parse("1e20")) |> should.be_true
  number.is_integer(parse("1.5")) |> should.be_false
  let four_digits = 4
  number.to_int(parse("12345"), four_digits)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
  number.to_int(parse("-1234"), four_digits) |> should.equal(Ok(-1234))
  number.to_int(parse("1.5"), four_digits)
  |> should.equal(Error(number.FractionalInteger))
}

pub fn document_numbers_do_not_inherit_number_parse_limits_test() {
  list.each(
    [
      "0." <> string.repeat("0", 1024),
      string.repeat("1", 801),
      "1e1201",
      "1e-1201",
    ],
    fn(source) {
      let assert Ok(expected) = number.from_json_token(source)
      value.parse(source, value.default_limits())
      |> should.equal(Ok(value.Number(expected)))
    },
  )
  value.parse("012", value.default_limits()) |> should.be_error
}

pub fn strings_may_start_with_a_combining_mark_test() {
  // U+0301 forms one grapheme with a preceding quote. JSON is defined over
  // code points, so it is ordinary string content.
  let text = "{\"\u{0301}k\": [\"\u{0301}v\"]}"
  value.parse(text, value.default_limits())
  |> should.equal(
    Ok(value.Object([#("\u{0301}k", value.Array([value.String("\u{0301}v")]))])),
  )
}

@target(javascript)
pub fn error_columns_count_graphemes_test() {
  // "é" is two bytes and one column; "e\u{0301}" is three bytes and one column.
  case value.parse("{\"é\": ?}", value.default_limits()) {
    Error(value.ParseError(location, value.UnexpectedCharacter)) ->
      location |> should.equal(value.Location(7, 1, 7))
    other -> panic as { "expected unexpected byte: " <> string.inspect(other) }
  }
  case value.parse("[\r\n\"e\u{0301}\", x]", value.default_limits()) {
    Error(value.ParseError(location, value.UnexpectedCharacter)) ->
      location |> should.equal(value.Location(10, 2, 6))
    other -> panic as { "expected unexpected byte: " <> string.inspect(other) }
  }
  case value.parse("[1, é]", value.default_limits()) {
    Error(value.ParseError(location, value.UnexpectedCharacter)) ->
      location |> should.equal(value.Location(4, 1, 5))
    other -> panic as { "expected unexpected byte: " <> string.inspect(other) }
  }
}

pub fn escapes_decode_as_before_test() {
  value.parse(
    "\"a\\\"\\\\\\/\\b\\f\\n\\r\\t\\u00e9\\ud83d\\ude00z\"",
    value.default_limits(),
  )
  |> should.equal(Ok(value.String("a\"\\/\u{8}\u{c}\n\r\té😀z")))
  list.each(
    ["\"\\ud83d\"", "\"\\ude00\"", "\"\\u12\"", "\"\\ud83d\\u0041\""],
    fn(text) {
      case value.parse(text, value.default_limits()) {
        Error(value.ParseError(_, _)) -> Nil
        other -> panic as { "expected escape error: " <> string.inspect(other) }
      }
    },
  )
}

// A returned field must not retain the much larger source through a subbinary.
pub fn typed_strings_do_not_retain_ignored_source_test() {
  let keep_first =
    codec.map(
      codec.pair(codec.string(), codec.string()),
      decode: fn(pair) { pair.0 },
      encode: fn(first) { #(first, "") },
    )
  let first = string.repeat("a", 100)
  let source = "[\"" <> first <> "\",\"" <> string.repeat("b", 100_000) <> "\"]"
  let assert Ok(found) = codec.decode_json(keep_first, source)
  found |> should.equal(first)
  shares_input(found) |> should.be_false
}

pub fn unknown_field_errors_do_not_retain_source_test() {
  let key = string.repeat("k", 100)
  let source = "{\"" <> key <> "\":\"" <> string.repeat("b", 100_000) <> "\"}"
  let assert Error(codec.DecodeError([codec.Field(found)], codec.UnknownField)) =
    codec.decode_json(codec.success(Nil), source)
  found |> should.equal(key)
  shares_input(found) |> should.be_false
}

@target(erlang)
pub fn long_written_exponents_keep_exact_values_test() {
  list.each(["", "+", "-"], fn(sign) {
    let token = "1e" <> sign <> string.repeat("0", 10_000) <> "2"
    let short = "1e" <> sign <> "2"
    let assert Ok(expected) = number.from_json_token(short)
    value.parse(token, value.default_limits())
    |> should.equal(Ok(value.Number(expected)))
  })
}

pub fn written_exponent_zero_padding_is_exact_test() {
  list.each(["", "+", "-"], fn(sign) {
    let assert Ok(expected) = number.from_json_token("1e" <> sign <> "2")
    value.parse(
      "1e" <> sign <> string.repeat("0", 1000) <> "2",
      value.default_limits(),
    )
    |> should.equal(Ok(value.Number(expected)))
  })
}

@target(javascript)
pub fn long_written_exponents_have_a_capacity_outcome_test() {
  let token = "1e" <> string.repeat("0", 10_000) <> "2"
  case value.parse(token, value.default_limits()) {
    Ok(found) -> {
      let assert Ok(expected) = number.from_int(100)
      found |> should.equal(value.Number(expected))
    }
    Error(value.ParseError(_, value.RuntimeCapacityExceeded)) -> Nil
    other ->
      panic as { "unexpected number parsing outcome: " <> string.inspect(other) }
  }
}
