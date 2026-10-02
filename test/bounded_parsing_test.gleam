import generated/option_codec
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import json/blueprint
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/parser_limits
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

fn byte_limit_failure(max: Int) -> codec.JsonDecodeError {
  codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
    codec.BlueprintJsonLocation(0, 1, 1),
    codec.BlueprintByteLimitExceeded(max),
  ))
}

fn nested_arrays(depth: Int) -> String {
  string.repeat("[", depth) <> string.repeat("]", depth)
}

pub fn default_limits_are_one_mib_and_depth_64_test() {
  let limits = parser_limits.default()
  parser_limits.max_bytes(limits) |> should.equal(one_mib)
  parser_limits.max_depth(limits) |> should.equal(64)
  parser.default_limits() |> should.equal(limits)
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

pub fn strict_decode_default_depth_is_64_test() {
  let assert Ok(value.Array(_)) =
    parser.parse_value_from_string(parser.default_limits(), nested_arrays(64))
  case
    parser.parse_value_from_string(parser.default_limits(), nested_arrays(65))
  {
    Error(parser.ParseError(location, parser.DepthLimitExceeded(64))) ->
      location.byte_offset |> should.equal(64)
    other -> panic as { "expected depth error: " <> string.inspect(other) }
  }
}

pub fn raised_limits_admit_larger_text_test() {
  let assert Ok(limits) =
    parser_limits.with_max_bytes(parser_limits.default(), 2 * one_mib)
  let assert Ok(limits) = parser_limits.with_max_depth(limits, 100)
  codec.decode_json_with_limits(
    codec.list(codec.int()),
    limits,
    padded("[1]", one_mib + 1),
  )
  |> should.equal(Ok([1]))
  parser.parse_value_from_string(limits, nested_arrays(100)) |> should.be_ok
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

pub fn native_decoders_reject_text_above_one_mib_test() {
  let fits = padded("{}", one_mib)
  let over = padded("{}", one_mib + 1)
  let generated = option_codec.option_codec()

  option_codec.decode_option_json_native(fits) |> should.equal(Ok(None))
  option_codec.decode_option_json_native(over)
  |> should.equal(Error(byte_limit_failure(one_mib)))
  codec.decode_json_native(generated, over)
  |> should.equal(Error(byte_limit_failure(one_mib)))
  codec.decode_json_native_with_max_bytes(generated, 2 * one_mib, over)
  |> should.equal(Ok(None))
  codec.decode_json_native_with_max_bytes(generated, 1, "{}")
  |> should.equal(Error(byte_limit_failure(1)))
}

pub fn custom_native_decoders_get_the_same_check_test() {
  let custom =
    codec.from_json_parts(
      fn(_) { Ok(value.Null) },
      fn(_) { Ok(Nil) },
      fn(_) { Ok("null") },
      fn(_) { Ok(Nil) },
      codec.IntSchema,
    )
  codec.decode_json_native(custom, padded("0", one_mib + 1))
  |> should.equal(Error(byte_limit_failure(one_mib)))
}

pub fn parsed_integers_are_compact_test() {
  // On the BEAM, an array element that holds a small integer takes a list
  // cell (2 words), a `value.Number` (3) and a number (3). Each number used
  // to carry its digits as a list, for 12 words per element.
  let count = 10_000
  let text = "[" <> string.repeat("7,", count - 1) <> "7]"
  let assert Ok(parsed) =
    parser.parse_value_from_string(parser.default_limits(), text)
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
    parser.parse_value_from_string(parser.default_limits(), text)
  shares_input(first) |> should.be_false
  shares_input(second) |> should.be_false
}

pub fn compact_numbers_stay_canonical_test() {
  let assert Ok(limits) = number.number_limits(1024, 800, 1200)
  let parse = fn(token) {
    let assert Ok(parsed) = number.parse_number(limits, token)
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
  number.number_text(parse("1000000000000000")) |> should.equal("1e15")
  number.number_text(parse("-1234567890123456"))
  |> should.equal("-1.234567890123456e15")
  number.number_text(parse("-12.5")) |> should.equal("-1.25e1")
  number.compare(parse("1e15"), largest_small)
  |> should.equal(number.GreaterThan)
  number.compare(parse("-1e15"), parse("-999999999999999"))
  |> should.equal(number.LessThan)
  number.compare(parse("12.5"), parse("12"))
  |> should.equal(number.GreaterThan)
  number.is_integer(parse("1e20")) |> should.be_true
  number.is_integer(parse("1.5")) |> should.be_false
  let assert Ok(four_digits) = number.integer_projection_limit(4)
  number.to_int_exact(parse("12345"), four_digits)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
  number.to_int_exact(parse("-1234"), four_digits) |> should.equal(Ok(-1234))
  number.to_int_exact(parse("1.5"), four_digits)
  |> should.equal(Error(number.FractionalInteger))
}

pub fn integer_fast_path_respects_number_limits_test() {
  let parse_with = fn(token_bytes, digits, exponent, text) {
    let assert Ok(numbers) = number.number_limits(token_bytes, digits, exponent)
    let assert Ok(limits) = parser.parser_limits(one_mib, 64, numbers)
    parser.parse_value_from_string(limits, text)
  }
  let assert Error(parser.ParseError(
    _,
    parser.InvalidNumberToken(number.TooManySignificandDigits),
  )) = parse_with(1024, 2, 1200, "123")
  let assert Error(parser.ParseError(
    _,
    parser.InvalidNumberToken(number.ExponentOutOfRange),
  )) = parse_with(1024, 800, 1, "100")
  let assert Error(parser.ParseError(
    _,
    parser.InvalidNumberToken(number.TokenTooLong),
  )) = parse_with(2, 800, 1200, "-12")
  let assert Error(parser.ParseError(
    _,
    parser.InvalidNumberToken(number.InvalidSyntax),
  )) = parse_with(1024, 800, 1200, "012")
  parse_with(1024, 800, 1200, "-0") |> should.be_ok
}

pub fn strings_may_start_with_a_combining_mark_test() {
  // U+0301 forms one grapheme with a preceding quote. JSON is defined over
  // code points, so it is ordinary string content.
  let text = "{\"\u{0301}k\": [\"\u{0301}v\"]}"
  parser.parse_value_from_string(parser.default_limits(), text)
  |> should.equal(
    Ok(value.Object([#("\u{0301}k", value.Array([value.String("\u{0301}v")]))])),
  )
}

pub fn error_columns_count_graphemes_test() {
  // "é" is two bytes and one column; "e\u{0301}" is three bytes and one column.
  case parser.parse_value_from_string(parser.default_limits(), "{\"é\": ?}") {
    Error(parser.ParseError(location, parser.UnexpectedByte("?"))) ->
      location |> should.equal(parser.Location(7, 1, 7))
    other -> panic as { "expected unexpected byte: " <> string.inspect(other) }
  }
  case
    parser.parse_value_from_string(
      parser.default_limits(),
      "[\r\n\"e\u{0301}\", x]",
    )
  {
    Error(parser.ParseError(location, parser.UnexpectedByte("x"))) ->
      location |> should.equal(parser.Location(10, 2, 6))
    other -> panic as { "expected unexpected byte: " <> string.inspect(other) }
  }
  case parser.parse_value_from_string(parser.default_limits(), "[1, é]") {
    Error(parser.ParseError(location, parser.UnexpectedByte("é"))) ->
      location |> should.equal(parser.Location(4, 1, 5))
    other -> panic as { "expected unexpected byte: " <> string.inspect(other) }
  }
}

pub fn escapes_decode_as_before_test() {
  parser.parse_value_from_string(
    parser.default_limits(),
    "\"a\\\"\\\\\\/\\b\\f\\n\\r\\t\\u00e9\\ud83d\\ude00z\"",
  )
  |> should.equal(Ok(value.String("a\"\\/\u{8}\u{c}\n\r\té😀z")))
  list.each(
    ["\"\\ud83d\"", "\"\\ude00\"", "\"\\u12\"", "\"\\ud83d\\u0041\""],
    fn(text) {
      case parser.parse_value_from_string(parser.default_limits(), text) {
        Error(parser.ParseError(location, parser.InvalidUnicodeEscape)) ->
          location.byte_offset |> should.equal(1)
        other -> panic as { "expected escape error: " <> string.inspect(other) }
      }
    },
  )
}
