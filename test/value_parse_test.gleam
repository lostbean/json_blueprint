//// The strict parser behind `value.parse` and `value.parse_bits`.

import gleam/bit_array
import gleam/list
import gleam/string
import gleeunit/should
import json/blueprint/number
import json/blueprint/value

fn test_limits() -> value.Limits {
  value.default_limits()
  |> value.with_max_bytes(10_000)
}

pub fn limits_below_one_fail_closed_test() {
  let limits = value.default_limits()
  value.parse("null", limits |> value.with_max_bytes(0))
  |> should.equal(
    Error(value.ParseError(value.Location(0, 1, 1), value.ByteLimitExceeded(0))),
  )
}

pub fn parse_primitives_test() {
  let limits = test_limits()

  value.parse("null", limits)
  |> should.equal(Ok(value.Null))

  value.parse("true", limits)
  |> should.equal(Ok(value.Bool(True)))

  value.parse("false", limits)
  |> should.equal(Ok(value.Bool(False)))

  value.parse("  \t\r\n null \n ", limits)
  |> should.equal(Ok(value.Null))
}

pub fn parse_numbers_exact_test() {
  let limits = test_limits()

  let assert Ok(val) = value.parse("1.2300e2", limits)
  let assert value.Number(num) = val
  number.to_string(num) |> should.equal("1.23e2")

  let assert Ok(val2) = value.parse("9007199254740993", limits)
  let assert value.Number(num2) = val2
  number.to_string(num2) |> should.equal("9.007199254740993e15")

  let assert Ok(val3) = value.parse("1e400", limits)
  let assert value.Number(num3) = val3
  number.to_string(num3) |> should.equal("1e400")
}

pub fn parse_strings_and_escapes_test() {
  let limits = test_limits()

  value.parse("\"hello world\"", limits)
  |> should.equal(Ok(value.String("hello world")))

  value.parse("\"quote: \\\" backslash: \\\\ slash: \\/\"", limits)
  |> should.equal(Ok(value.String("quote: \" backslash: \\ slash: /")))

  value.parse("\"tab: \\t newline: \\n cr: \\r\"", limits)
  |> should.equal(Ok(value.String("tab: \t newline: \n cr: \r")))

  value.parse("\"unicode: \\u0041\\u0042\"", limits)
  |> should.equal(Ok(value.String("unicode: AB")))
}

pub fn parse_arrays_and_objects_test() {
  let limits = test_limits()

  value.parse("[]", limits)
  |> should.equal(Ok(value.Array([])))

  value.parse("[1, true, null, \"test\"]", limits)
  |> should.be_ok

  value.parse("{}", limits)
  |> should.equal(Ok(value.Object([])))

  let assert Ok(obj) = value.parse("{\"name\": \"Alice\", \"age\": 30}", limits)
  case obj {
    value.Object(pairs) -> {
      let assert Ok(expected_age) = number.from_int(30)
      pairs
      |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
      |> should.equal([
        #("age", value.Number(expected_age)),
        #("name", value.String("Alice")),
      ])
    }
    _ -> panic as "expected object"
  }
}

@target(javascript)
pub fn duplicate_object_key_rejected_test() {
  let limits = test_limits()

  case value.parse("{\"key\": 1, \"other\": 2, \"key\": 3}", limits) {
    Error(value.ParseError(loc, value.DuplicateObjectKey)) -> {
      loc |> should.equal(value.Location(0, 0, 0))
    }
    _ -> panic as "expected duplicate key error"
  }
}

pub fn byte_limit_enforced_test() {
  let limits = test_limits() |> value.with_max_bytes(10)
  case value.parse_bits(bit_array.from_string("{\"toolong\": 12345}"), limits) {
    Error(value.ParseError(_, value.ByteLimitExceeded(10))) -> Nil
    _ -> panic as "expected byte limit error"
  }
}

pub fn nesting_is_not_capped_by_parse_limits_test() {
  let source = string.repeat("[", 100) <> "0" <> string.repeat("]", 100)
  value.parse(source, test_limits()) |> should.be_ok
}

pub fn invalid_utf8_detected_test() {
  let limits = test_limits()
  let bad_bytes = <<0xFF, 0xFE, 0x00>>
  case value.parse_bits(bad_bytes, limits) {
    Error(value.ParseError(loc, value.InvalidUtf8)) -> {
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
  case value.parse_bits(cr_bad, limits) {
    Error(value.ParseError(loc, value.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(1)
      loc.line |> should.equal(2)
      loc.column |> should.equal(1)
    }
    _ -> panic as "expected invalid utf8 error after CR"
  }

  // LF then invalid byte
  let lf_bad = <<10, 0xFF>>
  case value.parse_bits(lf_bad, limits) {
    Error(value.ParseError(loc, value.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(1)
      loc.line |> should.equal(2)
      loc.column |> should.equal(1)
    }
    _ -> panic as "expected invalid utf8 error after LF"
  }

  // CRLF then invalid byte
  let crlf_bad = <<13, 10, 0xFF>>
  case value.parse_bits(crlf_bad, limits) {
    Error(value.ParseError(loc, value.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(2)
      loc.line |> should.equal(2)
      loc.column |> should.equal(1)
    }
    _ -> panic as "expected invalid utf8 error after CRLF"
  }

  // Mixed multiple lines with CR and CRLF before invalid byte
  let mixed_bad = <<123, 13, 32, 32, 13, 10, 32, 0xFF>>
  case value.parse_bits(mixed_bad, limits) {
    Error(value.ParseError(loc, value.InvalidUtf8)) -> {
      loc.byte_offset |> should.equal(7)
      loc.line |> should.equal(3)
      loc.column |> should.equal(2)
    }
    _ -> panic as "expected invalid utf8 error in mixed newlines"
  }
}

@target(javascript)
pub fn standalone_cr_whitespace_and_error_location_test() {
  let limits = test_limits()

  // Standalone CR parses valid JSON whitespace cleanly
  let valid_cr_json = "{\r  \"name\": \"Bob\",\r  \"valid\": true\r}"
  value.parse(valid_cr_json, limits)
  |> should.be_ok

  // Native syntax failures have no portable source location.
  let cr_syntax_err = "{\r  \"name\": ?}"
  case value.parse(cr_syntax_err, limits) {
    Error(value.ParseError(loc, value.NativeSyntax)) -> {
      loc |> should.equal(value.Location(0, 0, 0))
    }
    _ -> panic as "expected unexpected byte error on line 2"
  }
}

@target(javascript)
pub fn hostile_syntax_errors_test() {
  let limits = test_limits()

  case value.parse("", limits) {
    Error(value.ParseError(_, value.NativeSyntax)) -> Nil
    _ -> panic as "expected unexpected end of input"
  }

  case value.parse("[1, 2,]", limits) {
    Error(value.ParseError(_, value.NativeSyntax)) -> Nil
    _ -> panic as "expected unexpected byte on trailing comma"
  }

  case value.parse("{\"a\": 1,}", limits) {
    Error(value.ParseError(_, value.NativeSyntax)) -> Nil
    _ -> panic as "expected unexpected byte on trailing comma"
  }

  case value.parse("true false", limits) {
    Error(value.ParseError(_, value.NativeSyntax)) -> Nil
    _ -> panic as "expected trailing content error"
  }

  case value.parse("\"unterminated", limits) {
    Error(value.ParseError(_, value.NativeSyntax)) -> Nil
    _ -> panic as "expected unterminated string"
  }

  case value.parse("\"bad escape \\q\"", limits) {
    Error(value.ParseError(_, value.NativeSyntax)) -> Nil
    _ -> panic as "expected invalid escape sequence"
  }
}

@target(javascript)
pub fn wide_object_resource_and_duplicate_boundary_test() {
  let limits = test_limits() |> value.with_max_bytes(10_000_000)

  // 1. Build a wide object with 2,000 distinct members
  let entries =
    list.index_map(list.repeat(Nil, 2000), fn(_, i) {
      let idx = string.inspect(i + 1)
      "\"k" <> idx <> "\": " <> idx
    })
  let wide_valid = "{" <> string.join(entries, ", ") <> "}"

  let assert Ok(value.Object(parsed_entries)) = value.parse(wide_valid, limits)
  list.length(parsed_entries) |> should.equal(2000)

  // 2. Append duplicate of the very first key "k1" at the end (member 2,001)
  let wide_prefix = "{" <> string.join(entries, ", ") <> ", "
  let wide_with_duplicate = wide_prefix <> "\"k1\": 9999}"
  case value.parse(wide_with_duplicate, limits) {
    Error(value.ParseError(loc, value.DuplicateObjectKey)) -> {
      loc |> should.equal(value.Location(0, 0, 0))
    }
    _ -> panic as "expected duplicate key error for wide object"
  }
}

@target(javascript)
pub fn string_runs_preserve_values_and_failure_locations_test() {
  let limits = value.default_limits()
  list.each(
    list.index_map(list.repeat(Nil, 41), fn(_, index) { index }),
    fn(length) {
      let prefix = string.repeat("x", length)
      list.each(
        [
          #("", ""),
          #("plain text", "plain text"),
          #("Olá 世界 👋🏽", "Olá 世界 👋🏽"),
          #("\\nnext\\tline", "\nnext\tline"),
          #("\\\"quote\\\\slash", "\"quote\\slash"),
          #("\\uD83D\\uDE80", "🚀"),
        ],
        fn(pair) {
          let source = "\"" <> prefix <> pair.0 <> "\""
          let expected = Ok(value.String(prefix <> pair.1))
          value.parse(source, limits) |> should.equal(expected)
          value.parse_bits(bit_array.from_string(source), limits)
          |> should.equal(expected)
        },
      )
      list.each(["\n", "\r", "\t"], fn(control) {
        let source = "\"" <> prefix <> control <> "\""
        let expected =
          Error(value.ParseError(value.Location(0, 0, 0), value.NativeSyntax))
        value.parse(source, limits) |> should.equal(expected)
        value.parse_bits(bit_array.from_string(source), limits)
        |> should.equal(expected)
      })
      value.parse("\"" <> prefix <> "\\q\"", limits)
      |> should.equal(
        Error(value.ParseError(value.Location(0, 0, 0), value.NativeSyntax)),
      )
      value.parse("\"" <> prefix, limits)
      |> should.equal(
        Error(value.ParseError(value.Location(0, 0, 0), value.NativeSyntax)),
      )
    },
  )
}

pub fn native_parse_diagnostics_are_explicitly_unlocated_test() {
  value.parse("[1,?]", test_limits())
  |> should.equal(
    Error(value.ParseError(value.Location(0, 0, 0), value.NativeSyntax)),
  )
  let assert Error(error) = value.parse("{\"a\":1,\"a\":2}", test_limits())
  error
  |> should.equal(value.ParseError(
    value.Location(0, 0, 0),
    value.DuplicateObjectKey,
  ))
  value.describe_parse_error(error)
  |> should.equal("invalid JSON: duplicate object key")
  value.is_limit_exceeded(error) |> should.be_false
}

pub fn duplicate_escaped_names_reject_on_both_backends_test() {
  let assert Error(value.ParseError(_, value.DuplicateObjectKey)) =
    value.parse("{\"a\":1,\"\\u0061\":2}", test_limits())
  Nil
}

@target(javascript)
pub fn native_parser_distinguishes_syntax_and_capacity_test() {
  let opens = string.repeat("[", 20_000)
  value.parse(opens, value.default_limits())
  |> should.equal(
    Error(value.ParseError(value.Location(0, 0, 0), value.NativeSyntax)),
  )
  list.each([opens <> "0" <> string.repeat("]", 20_000)], fn(source) {
    let expected =
      Error(value.ParseError(
        value.Location(0, 0, 0),
        value.RuntimeCapacityExceeded,
      ))
    value.parse(source, value.default_limits()) |> should.equal(expected)
    value.parse_bits(bit_array.from_string(source), value.default_limits())
    |> should.equal(expected)
  })
}
