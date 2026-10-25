import gleam/list
import gleeunit/should
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
}
