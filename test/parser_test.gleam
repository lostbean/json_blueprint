import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/value

pub fn parser_limits_test() {
  parser.parser_limits(0, 10, default_number_limits())
  |> should.equal(Error(parser.MaxBytesMustBePositive))

  parser.parser_limits(100, 0, default_number_limits())
  |> should.equal(Error(parser.MaxDepthMustBePositive))

  let assert Ok(limits) =
    parser.parser_limits(1024, 16, default_number_limits())
  should.be_ok(parser.parse_value_from_string(limits, "null"))
}

fn default_number_limits() -> number.NumberLimits {
  let assert Ok(limits) = number.number_limits(1024, 100, 1000)
  limits
}

fn test_limits() -> parser.ParserLimits {
  let assert Ok(limits) =
    parser.parser_limits(10_000, 16, default_number_limits())
  limits
}

pub fn parse_primitives_test() {
  let limits = test_limits()

  parser.parse_value_from_string(limits, "null")
  |> should.equal(Ok(value.Null))

  parser.parse_value_from_string(limits, "true")
  |> should.equal(Ok(value.Bool(True)))

  parser.parse_value_from_string(limits, "false")
  |> should.equal(Ok(value.Bool(False)))

  parser.parse_value_from_string(limits, "  \t\r\n null \n ")
  |> should.equal(Ok(value.Null))
}

pub fn parse_numbers_exact_test() {
  let limits = test_limits()

  let assert Ok(val) = parser.parse_value_from_string(limits, "1.2300e2")
  let assert value.Number(num) = val
  number.number_text(num) |> should.equal("1.23e2")

  let assert Ok(val2) =
    parser.parse_value_from_string(limits, "9007199254740993")
  let assert value.Number(num2) = val2
  number.number_text(num2) |> should.equal("9.007199254740993e15")

  let assert Ok(val3) = parser.parse_value_from_string(limits, "1e400")
  let assert value.Number(num3) = val3
  number.number_text(num3) |> should.equal("1e400")
}

pub fn parse_strings_and_escapes_test() {
  let limits = test_limits()

  parser.parse_value_from_string(limits, "\"hello world\"")
  |> should.equal(Ok(value.String("hello world")))

  parser.parse_value_from_string(
    limits,
    "\"quote: \\\" backslash: \\\\ slash: \\/\"",
  )
  |> should.equal(Ok(value.String("quote: \" backslash: \\ slash: /")))

  parser.parse_value_from_string(limits, "\"tab: \\t newline: \\n cr: \\r\"")
  |> should.equal(Ok(value.String("tab: \t newline: \n cr: \r")))

  parser.parse_value_from_string(limits, "\"unicode: \\u0041\\u0042\"")
  |> should.equal(Ok(value.String("unicode: AB")))
}

pub fn parse_arrays_and_objects_test() {
  let limits = test_limits()

  parser.parse_value_from_string(limits, "[]")
  |> should.equal(Ok(value.Array([])))

  parser.parse_value_from_string(limits, "[1, true, null, \"test\"]")
  |> should.be_ok

  parser.parse_value_from_string(limits, "{}")
  |> should.equal(Ok(value.Object([])))

  let assert Ok(obj) =
    parser.parse_value_from_string(limits, "{\"name\": \"Alice\", \"age\": 30}")
  case obj {
    value.Object(pairs) -> {
      let assert Ok(expected_age) = number.from_int(30)
      pairs
      |> should.equal([
        #("name", value.String("Alice")),
        #("age", value.Number(expected_age)),
      ])
    }
    _ -> panic as "expected object"
  }
}

pub fn duplicate_object_key_rejected_test() {
  let limits = test_limits()

  case
    parser.parse_value_from_string(
      limits,
      "{\"key\": 1, \"other\": 2, \"key\": 3}",
    )
  {
    Error(parser.ParseError(loc, parser.DuplicateObjectKey("key"))) -> {
      loc.byte_offset |> should.equal(23)
      loc.line |> should.equal(1)
      loc.column |> should.equal(24)
    }
    _ -> panic as "expected duplicate key error"
  }
}

pub fn byte_limit_enforced_test() {
  let assert Ok(limits) = parser.parser_limits(10, 16, default_number_limits())
  case
    parser.parse_value(limits, bit_array.from_string("{\"toolong\": 12345}"))
  {
    Error(parser.ParseError(_, parser.ByteLimitExceeded(10))) -> Nil
    _ -> panic as "expected byte limit error"
  }
}

pub fn depth_limit_enforced_test() {
  let assert Ok(limits) = parser.parser_limits(1000, 2, default_number_limits())
  case parser.parse_value_from_string(limits, "[[[1]]]") {
    Error(parser.ParseError(_, parser.DepthLimitExceeded(2))) -> Nil
    _ -> panic as "expected depth limit error"
  }
}

pub fn invalid_utf8_detected_test() {
  let limits = test_limits()
  let bad_bytes = <<0xFF, 0xFE, 0x00>>
  case parser.parse_value(limits, bad_bytes) {
    Error(parser.ParseError(loc, parser.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(0)
      loc.line |> should.equal(1)
      loc.column |> should.equal(1)
    }
    _ -> panic as "expected invalid utf8 error"
  }
}

pub fn invalid_utf8_cr_lf_crlf_locations_test() {
  let limits = test_limits()

  // Standalone CR then invalid byte (regression for scanner CR handling)
  let cr_bad = <<13, 0xFF>>
  case parser.parse_value(limits, cr_bad) {
    Error(parser.ParseError(loc, parser.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(1)
      loc.line |> should.equal(2)
      loc.column |> should.equal(1)
    }
    _ -> panic as "expected invalid utf8 error after CR"
  }

  // LF then invalid byte
  let lf_bad = <<10, 0xFF>>
  case parser.parse_value(limits, lf_bad) {
    Error(parser.ParseError(loc, parser.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(1)
      loc.line |> should.equal(2)
      loc.column |> should.equal(1)
    }
    _ -> panic as "expected invalid utf8 error after LF"
  }

  // CRLF then invalid byte
  let crlf_bad = <<13, 10, 0xFF>>
  case parser.parse_value(limits, crlf_bad) {
    Error(parser.ParseError(loc, parser.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(2)
      loc.line |> should.equal(2)
      loc.column |> should.equal(1)
    }
    _ -> panic as "expected invalid utf8 error after CRLF"
  }

  // Mixed multiple lines with CR and CRLF before invalid byte
  let mixed_bad = <<123, 13, 32, 32, 13, 10, 32, 0xFF>>
  case parser.parse_value(limits, mixed_bad) {
    Error(parser.ParseError(loc, parser.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(7)
      loc.line |> should.equal(3)
      loc.column |> should.equal(2)
    }
    _ -> panic as "expected invalid utf8 error in mixed newlines"
  }
}

pub fn standalone_cr_whitespace_and_error_location_test() {
  let limits = test_limits()

  // Standalone CR parses valid JSON whitespace cleanly
  let valid_cr_json = "{\r  \"name\": \"Bob\",\r  \"valid\": true\r}"
  parser.parse_value_from_string(limits, valid_cr_json)
  |> should.be_ok

  // Standalone CR produces aligned line and column on syntax errors
  let cr_syntax_err = "{\r  \"name\": ?}"
  case parser.parse_value_from_string(limits, cr_syntax_err) {
    Error(parser.ParseError(loc, parser.UnexpectedByte("?"))) -> {
      loc.byte_offset |> should.equal(12)
      loc.line |> should.equal(2)
      loc.column |> should.equal(11)
    }
    _ -> panic as "expected unexpected byte error on line 2"
  }
}

pub fn hostile_syntax_errors_test() {
  let limits = test_limits()

  case parser.parse_value_from_string(limits, "") {
    Error(parser.ParseError(_, parser.UnexpectedEndOfInput)) -> Nil
    _ -> panic as "expected unexpected end of input"
  }

  case parser.parse_value_from_string(limits, "[1, 2,]") {
    Error(parser.ParseError(_, parser.UnexpectedByte("]"))) -> Nil
    _ -> panic as "expected unexpected byte on trailing comma"
  }

  case parser.parse_value_from_string(limits, "{\"a\": 1,}") {
    Error(parser.ParseError(_, parser.UnexpectedByte("}"))) -> Nil
    _ -> panic as "expected unexpected byte on trailing comma"
  }

  case parser.parse_value_from_string(limits, "true false") {
    Error(parser.ParseError(_, parser.TrailingContent)) -> Nil
    _ -> panic as "expected trailing content error"
  }

  case parser.parse_value_from_string(limits, "\"unterminated") {
    Error(parser.ParseError(_, parser.UnterminatedString)) -> Nil
    _ -> panic as "expected unterminated string"
  }

  case parser.parse_value_from_string(limits, "\"bad escape \\q\"") {
    Error(parser.ParseError(_, parser.InvalidEscapeSequence)) -> Nil
    _ -> panic as "expected invalid escape sequence"
  }
}

pub fn parse_schema_document_test() {
  let limits = test_limits()

  let valid_schema_json =
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"type\": \"string\"}"
  parser.parse_schema_document_from_string(limits, valid_schema_json)
  |> should.be_ok

  let malformed_json =
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"type\": 123}"
  case parser.parse_schema_document_from_string(limits, malformed_json) {
    Error(parser.DocumentAdmissionError(_)) -> Nil
    _ -> panic as "expected document admission error"
  }

  let syntax_error_json = "{\"$schema\": "
  case parser.parse_schema_document_from_string(limits, syntax_error_json) {
    Error(parser.ParseAdmissionError(_)) -> Nil
    _ -> panic as "expected parse admission error"
  }
}

pub fn wide_object_resource_and_duplicate_boundary_test() {
  let assert Ok(num_limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(limits) = parser.parser_limits(10_000_000, 16, num_limits)

  // 1. Build a wide object with 2,000 distinct members
  let entries =
    list.index_map(list.repeat(Nil, 2000), fn(_, i) {
      let idx = int.to_string(i + 1)
      "\"k" <> idx <> "\": " <> idx
    })
  let wide_valid = "{" <> string.join(entries, ", ") <> "}"

  let assert Ok(value.Object(parsed_entries)) =
    parser.parse_value_from_string(limits, wide_valid)
  list.length(parsed_entries) |> should.equal(2000)

  // 2. Append duplicate of the very first key "k1" at the end (member 2,001)
  let wide_prefix = "{" <> string.join(entries, ", ") <> ", "
  let wide_with_duplicate = wide_prefix <> "\"k1\": 9999}"
  case parser.parse_value_from_string(limits, wide_with_duplicate) {
    Error(parser.ParseError(loc, parser.DuplicateObjectKey("k1"))) -> {
      // Duplicate is located at the exact offset of the duplicate key at the end
      loc.line |> should.equal(1)
      loc.byte_offset |> should.equal(string.byte_size(wide_prefix))
      loc.column |> should.equal(string.byte_size(wide_prefix) + 1)
    }
    _ -> panic as "expected duplicate key error for wide object"
  }
}
