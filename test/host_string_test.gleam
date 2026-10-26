import gleam/list
import gleeunit/should
import json/blueprint/codec
import json/blueprint/value

@target(javascript)
@external(javascript, "./host_string_test_ffi.mjs", "utf16_unit")
fn utf16_unit(unit: Int) -> String

@target(javascript)
pub fn raw_surrogates_reject_before_utf8_conversion_test() {
  list.each([0xD800, 0xDBFF, 0xDC00, 0xDFFF], fn(unit) {
    value.parse("\"" <> utf16_unit(unit) <> "\"", value.default_limits())
    |> should.equal(
      Error(value.ParseError(
        value.Location(1, 1, 2),
        value.InvalidUnicodeScalar,
      )),
    )
  })
  value.parse("\"" <> utf16_unit(0xD800), value.default_limits())
  |> should.equal(
    Error(value.ParseError(value.Location(1, 1, 2), value.InvalidUnicodeScalar)),
  )
  value.parse(
    "\"" <> utf16_unit(0xD800) <> utf16_unit(0xD800) <> "\"",
    value.default_limits(),
  )
  |> should.equal(
    Error(value.ParseError(value.Location(1, 1, 2), value.InvalidUnicodeScalar)),
  )
}

@target(javascript)
pub fn raw_surrogate_locations_count_utf8_bytes_and_graphemes_test() {
  let source = "[\r\n\"á🚀" <> utf16_unit(0xDC00) <> "\"]"
  let assert Error(error) = value.parse(source, value.default_limits())
  error
  |> should.equal(value.ParseError(
    value.Location(11, 2, 4),
    value.InvalidUnicodeScalar,
  ))
  value.is_limit_exceeded(error) |> should.be_false
  value.describe_parse_error(error)
  |> should.equal("invalid JSON at line 2, column 4: invalid Unicode scalar")

  value.parse(" \r\n \r \n\"" <> utf16_unit(0xD800), value.default_limits())
  |> should.equal(
    Error(value.ParseError(value.Location(8, 4, 2), value.InvalidUnicodeScalar)),
  )
}

@target(javascript)
pub fn byte_limit_precedes_raw_surrogate_rejection_test() {
  let limits = value.default_limits() |> value.with_max_bytes(2)
  value.parse("\"" <> utf16_unit(0xD800) <> "\"", limits)
  |> should.equal(
    Error(value.ParseError(value.Location(0, 1, 1), value.ByteLimitExceeded(2))),
  )
}

@target(javascript)
pub fn raw_valid_pairs_are_preserved_test() {
  value.parse(
    "\"" <> utf16_unit(0xD83D) <> utf16_unit(0xDE80) <> "\"",
    value.default_limits(),
  )
  |> should.equal(Ok(value.String("🚀")))
}

pub fn scalar_strings_and_escaped_pairs_parse_test() {
  list.each(["plain", "á 🚀", "�"], fn(text) {
    value.parse("\"" <> text <> "\"", value.default_limits())
    |> should.equal(Ok(value.String(text)))
  })
  value.parse("\"\\uD83D\\uDE80\"", value.default_limits())
  |> should.equal(Ok(value.String("🚀")))
  codec.decode_json(codec.string(), "\"\\uD83D\\uDE80\"")
  |> should.equal(Ok("🚀"))
}

@target(javascript)
pub fn every_unpaired_utf16_unit_rejects_in_values_and_names_test() {
  check_raw_surrogate(0xD800)
}

@target(javascript)
fn check_raw_surrogate(unit: Int) -> Nil {
  case unit > 0xDFFF {
    True -> Nil
    False -> {
      let raw = utf16_unit(unit)
      list.each(["\"" <> raw <> "\"", "{\"" <> raw <> "\":0}"], fn(source) {
        let assert Error(value.ParseError(_, value.InvalidUnicodeScalar)) =
          value.parse(source, value.default_limits())
        let assert Error(codec.DecodeError(
          [],
          codec.InvalidJson(value.ParseError(_, value.InvalidUnicodeScalar)),
        )) = codec.decode_json(codec.value(), source)
      })
      check_raw_surrogate(unit + 1)
    }
  }
}

@target(javascript)
pub fn valid_utf16_pair_boundaries_are_not_rejected_test() {
  list.each([0xD800, 0xD83D, 0xDBFF], fn(high) {
    list.each([0xDC00, 0xDE80, 0xDFFF], fn(low) {
      let pair = utf16_unit(high) <> utf16_unit(low)
      codec.decode_json(codec.string(), "\"" <> pair <> "\"")
      |> should.equal(Ok(pair))
    })
  })
}

pub fn utf8_surrogate_bytes_reject_but_replacement_character_is_valid_test() {
  // Wire bytes encoding a surrogate are invalid UTF-8, independently of the
  // JavaScript host-string boundary. U+FFFD itself remains a valid scalar.
  let assert Error(value.ParseError(_, value.InvalidUtf8)) =
    value.parse_bits(<<34, 0xED, 0xA0, 0x80, 34>>, value.default_limits())
  value.parse_bits(<<34, 0xEF, 0xBF, 0xBD, 34>>, value.default_limits())
  |> should.equal(Ok(value.String("�")))
}
