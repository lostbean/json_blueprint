//// The JSON value model, its strict bounded parser, its text form and its
//// bridges to `gleam/json`.
////
//// `Value` is what `parse` returns, what `json/blueprint/contract` validates
//// and what `codec.encode` and `codec.decode` exchange. Object members keep
//// their order. Numbers are `number.Number`, so they are exact.
////
//// `parse` reads JSON text strictly: it rejects duplicate object keys, keeps
//// numbers exact, and stops at the `Limits` it is given. Start from
//// `default_limits()` and change one bound with a `with_` setter:
////
//// | Bound | Default | Setter |
//// | --- | --- | --- |
//// | input bytes | 1 MiB (1,048,576) | `with_max_bytes` |
//// | array and object nesting | 64 | `with_max_depth` |
//// | values in the document | 262,144 | `with_max_elements` |
//// | number tokens | 1,024 bytes, 800 digits, exponent 1,200 | `with_number_limits` |
////
//// A bound below 1 rejects every input. `to_string` renders compact JSON
//// text. `to_json` converts a value to `gleam/json`, and `decoder` reads a
//// value from `gleam/json`'s parser, for use with libraries that speak
//// `gleam/json`.
////
//// ```gleam
//// import json/blueprint/value
////
//// pub fn example() {
////   let limits = value.default_limits() |> value.with_max_bytes(64 * 1024)
////   case value.parse("{\"tags\": [\"a\"]}", limits) {
////     Ok(value.Object(members)) -> Ok(members)
////     Ok(_) -> Error("expected an object")
////     Error(error) -> Error(value.describe_parse_error(error))
////   }
//// }
//// ```

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string
import json/blueprint/internal/text
import json/blueprint/number.{type Number}

/// A JSON value. Object members keep their order; the `Object` constructor
/// accepts any list, and `object` rejects a repeated key.
pub type Value {
  Null
  Bool(Bool)
  String(String)
  Number(Number)
  Array(List(Value))
  Object(List(#(String, Value)))
}

/// The key that `object` found twice.
pub type DuplicateKey {
  DuplicateKey(key: String)
}

/// Build an object, rejecting a key that appears twice.
pub fn object(entries: List(#(String, Value))) -> Result(Value, DuplicateKey) {
  case find_duplicate_key(entries, dict.new()) {
    Error(key) -> Error(DuplicateKey(key))
    Ok(Nil) -> Ok(Object(entries))
  }
}

fn find_duplicate_key(
  entries: List(#(String, Value)),
  seen: Dict(String, Nil),
) -> Result(Nil, String) {
  case entries {
    [] -> Ok(Nil)
    [#(key, _), ..rest] ->
      case dict.has_key(seen, key) {
        True -> Error(key)
        False -> find_duplicate_key(rest, dict.insert(seen, key, Nil))
      }
  }
}

// --- limits ------------------------------------------------------------------

/// Bounds for `parse`: input bytes, nesting depth, the number of values, and
/// number tokens.
pub opaque type Limits {
  Limits(
    max_bytes: Int,
    max_depth: Int,
    max_elements: Int,
    numbers: number.Limits,
    // Whether every integer token of at most 15 digits fits `numbers`, so the
    // parser may build such integers directly.
    small_integers_fit: Bool,
  )
}

/// 1 MiB (1,048,576 bytes) of JSON text, nesting depth 64, 262,144 values,
/// and `number.default_limits()`.
///
/// The value bound is one per 4 bytes of the byte bound, so it stops only
/// documents denser than JSON text written for people; it caps the parsed
/// value's memory when the byte bound is raised. The README defaults table
/// lists the measured peak heap at these defaults.
pub fn default_limits() -> Limits {
  // The default number limits admit every integer token of 15 digits.
  Limits(
    max_bytes: default_max_bytes,
    max_depth: default_max_depth,
    max_elements: default_max_elements,
    numbers: number.default_limits(),
    small_integers_fit: True,
  )
}

const default_max_bytes = 1_048_576

const default_max_depth = 64

const default_max_elements = 262_144

fn new_limits(
  max_bytes: Int,
  max_depth: Int,
  max_elements: Int,
  numbers: number.Limits,
) -> Limits {
  // Every integer token of at most 15 digits passes the bounds when the
  // longest one and the one with the largest exponent do.
  let small_integers_fit = case
    number.parse("-999999999999999", numbers),
    number.parse("-100000000000000", numbers)
  {
    Ok(_), Ok(_) -> True
    _, _ -> False
  }
  Limits(max_bytes, max_depth, max_elements, numbers, small_integers_fit)
}

/// Accept at most `bytes` bytes of UTF-8 text. Below 1 rejects every input.
pub fn with_max_bytes(limits: Limits, bytes: Int) -> Limits {
  Limits(..limits, max_bytes: bytes)
}

/// Accept arrays and objects nested at most `depth` deep. A depth of 0 admits
/// only scalar documents.
pub fn with_max_depth(limits: Limits, depth: Int) -> Limits {
  Limits(..limits, max_depth: depth)
}

/// Accept at most `count` values in a document: every scalar, array and
/// object counts once, including the root and object member values.
pub fn with_max_elements(limits: Limits, count: Int) -> Limits {
  Limits(..limits, max_elements: count)
}

/// Bound number tokens with `numbers`.
pub fn with_number_limits(limits: Limits, numbers: number.Limits) -> Limits {
  new_limits(limits.max_bytes, limits.max_depth, limits.max_elements, numbers)
}

// --- errors ------------------------------------------------------------------

/// Where a parse failed: the byte offset from 0, and the line and column from
/// 1. Columns count graphemes.
pub type Location {
  Location(byte_offset: Int, line: Int, column: Int)
}

/// Why a parse failed. The `*LimitExceeded` variants, and an `InvalidNumber`
/// other than `number.InvalidSyntax`, mean the input exceeded `Limits`.
/// May gain variants in a minor release; match with a `_` branch.
pub type ParseReason {
  UnexpectedCharacter
  UnexpectedEndOfInput
  InvalidUtf8
  ByteLimitExceeded(max: Int)
  DepthLimitExceeded(max: Int)
  ElementLimitExceeded(max: Int)
  InvalidNumber(number.NumberError)
  DuplicateObjectKey
  UnterminatedString
  InvalidEscape
  InvalidUnicodeEscape
  TrailingContent
}

/// A parse failure. It carries no input text.
pub type ParseError {
  ParseError(location: Location, reason: ParseReason)
}

/// Whether the input exceeded a bound of `Limits`, as opposed to being
/// invalid JSON.
pub fn is_limit_exceeded(error: ParseError) -> Bool {
  case error.reason {
    ByteLimitExceeded(_) | DepthLimitExceeded(_) | ElementLimitExceeded(_) ->
      True
    InvalidNumber(number.InvalidSyntax) -> False
    InvalidNumber(_) -> True
    _ -> False
  }
}

/// Render a parse error as text such as
/// `invalid JSON at line 2, column 7: unexpected character`. The text names
/// the setter for a limit error and contains no input text.
pub fn describe_parse_error(error: ParseError) -> String {
  let ParseError(location, reason) = error
  "invalid JSON at line "
  <> int.to_string(location.line)
  <> ", column "
  <> int.to_string(location.column)
  <> ": "
  <> describe_reason(reason)
}

fn describe_reason(reason: ParseReason) -> String {
  case reason {
    UnexpectedCharacter -> "unexpected character"
    UnexpectedEndOfInput -> "unexpected end of input"
    InvalidUtf8 -> "invalid UTF-8"
    ByteLimitExceeded(max) ->
      "more than " <> int.to_string(max) <> " bytes (value.with_max_bytes)"
    DepthLimitExceeded(max) ->
      "nesting deeper than " <> int.to_string(max) <> " (value.with_max_depth)"
    ElementLimitExceeded(max) ->
      "more than " <> int.to_string(max) <> " values (value.with_max_elements)"
    InvalidNumber(number.InvalidSyntax) -> "invalid number"
    InvalidNumber(number.TokenTooLong) ->
      "number token too long (value.with_number_limits)"
    InvalidNumber(number.TooManySignificandDigits) ->
      "number has too many digits (value.with_number_limits)"
    InvalidNumber(number.ExponentOutOfRange) ->
      "number exponent out of range (value.with_number_limits)"
    DuplicateObjectKey -> "duplicate object key"
    UnterminatedString -> "unterminated string"
    InvalidEscape -> "invalid escape sequence"
    InvalidUnicodeEscape -> "invalid Unicode escape"
    TrailingContent -> "trailing content"
  }
}

// --- parsing -----------------------------------------------------------------

/// Parse JSON text within `limits`.
pub fn parse(text: String, limits: Limits) -> Result(Value, ParseError) {
  case text.exceeds_byte_limit(text, limits.max_bytes) {
    True ->
      Error(ParseError(Location(0, 1, 1), ByteLimitExceeded(limits.max_bytes)))
    False -> parse_document(limits, bit_array.from_string(text))
  }
}

/// Parse JSON text given as UTF-8 bytes within `limits`. Invalid UTF-8 fails
/// with `InvalidUtf8` at the first invalid byte.
pub fn parse_bits(
  bytes: BitArray,
  limits: Limits,
) -> Result(Value, ParseError) {
  case bit_array.byte_size(bytes) > limits.max_bytes {
    True ->
      Error(ParseError(Location(0, 1, 1), ByteLimitExceeded(limits.max_bytes)))
    False ->
      case bit_array.is_utf8(bytes) {
        False ->
          Error(ParseError(find_invalid_utf8(bytes, 0, 1, 1), InvalidUtf8))
        True -> parse_document(limits, bytes)
      }
  }
}

/// A failure at a byte offset whose line and column are not yet known.
type Failure {
  Failure(offset: Int, kind: FailureKind)
}

type FailureKind {
  /// The grapheme at the offset is not allowed there.
  Unexpected
  Known(ParseReason)
}

/// A parsed item, the rest of the input, its offset, and the number of
/// values parsed so far.
type Parsed(a) =
  Result(#(a, BitArray, Int, Int), Failure)

@external(erlang, "json_blueprint_ffi", "copy_string")
@external(javascript, "../../json_blueprint_ffi.mjs", "copy_string")
fn copy_string(text: String) -> String

fn parse_document(
  limits: Limits,
  source: BitArray,
) -> Result(Value, ParseError) {
  let #(rest, offset) = skip_whitespace(source, 0)
  let result = case rest {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    _ ->
      case parse_any(limits, rest, offset, 0, 0) {
        Error(failure) -> Error(failure)
        Ok(#(parsed, rest, offset, _)) -> {
          let #(rest, offset) = skip_whitespace(rest, offset)
          case rest {
            <<>> -> Ok(parsed)
            _ -> Error(Failure(offset, Known(TrailingContent)))
          }
        }
      }
  }
  case result {
    Ok(parsed) -> Ok(parsed)
    Error(failure) -> Error(locate(source, failure))
  }
}

fn skip_whitespace(bytes: BitArray, offset: Int) -> #(BitArray, Int) {
  case bytes {
    <<0x20, rest:bytes>>
    | <<0x09, rest:bytes>>
    | <<0x0A, rest:bytes>>
    | <<0x0D, rest:bytes>> -> skip_whitespace(rest, offset + 1)
    _ -> #(bytes, offset)
  }
}

fn parse_any(
  limits: Limits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  count: Int,
) -> Parsed(Value) {
  case count + 1 > limits.max_elements {
    True ->
      Error(Failure(offset, Known(ElementLimitExceeded(limits.max_elements))))
    False -> parse_counted(limits, bytes, offset, depth, count + 1)
  }
}

fn parse_counted(
  limits: Limits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  count: Int,
) -> Parsed(Value) {
  case bytes {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    // null
    <<0x6E, 0x75, 0x6C, 0x6C, rest:bytes>> ->
      Ok(#(Null, rest, offset + 4, count))
    // true
    <<0x74, 0x72, 0x75, 0x65, rest:bytes>> ->
      Ok(#(Bool(True), rest, offset + 4, count))
    // false
    <<0x66, 0x61, 0x6C, 0x73, 0x65, rest:bytes>> ->
      Ok(#(Bool(False), rest, offset + 5, count))
    <<0x22, rest:bytes>> ->
      case parse_string(rest, offset + 1, offset) {
        Error(failure) -> Error(failure)
        Ok(#(text, rest, offset)) -> Ok(#(String(text), rest, offset, count))
      }
    <<0x5B, rest:bytes>> -> parse_array(limits, rest, offset, depth, count)
    <<0x7B, rest:bytes>> -> parse_object(limits, rest, offset, depth, count)
    <<byte, _:bytes>> if byte == 0x2D || byte >= 0x30 && byte <= 0x39 ->
      case parse_number(limits, bytes, offset) {
        Error(failure) -> Error(failure)
        Ok(#(parsed, rest, offset)) ->
          Ok(#(Number(parsed), rest, offset, count))
      }
    _ -> Error(Failure(offset, Unexpected))
  }
}

fn parse_number(
  limits: Limits,
  bytes: BitArray,
  offset: Int,
) -> Result(#(Number, BitArray, Int), Failure) {
  let #(length, rest) = number_span(bytes, 0)
  let assert Ok(token_bytes) = bit_array.slice(bytes, 0, length)
  let small = case limits.small_integers_fit, simple_integer(token_bytes) {
    True, Ok(#(negative, magnitude)) ->
      case negative {
        True -> number.from_int(0 - magnitude)
        False -> number.from_int(magnitude)
      }
      |> result_to_nil
    _, _ -> Error(Nil)
  }
  case small {
    Ok(parsed) -> Ok(#(parsed, rest, offset + length))
    Error(Nil) -> {
      let assert Ok(token) = bit_array.to_string(token_bytes)
      case number.parse(token, limits.numbers) {
        Error(error) -> Error(Failure(offset, Known(InvalidNumber(error))))
        Ok(parsed) -> Ok(#(parsed, rest, offset + length))
      }
    }
  }
}

fn result_to_nil(result: Result(a, e)) -> Result(a, Nil) {
  case result {
    Ok(item) -> Ok(item)
    Error(_) -> Error(Nil)
  }
}

/// Read an integer token of at most 15 digits without leading zeros as its
/// sign and magnitude.
fn simple_integer(bytes: BitArray) -> Result(#(Bool, Int), Nil) {
  let #(negative, digits) = case bytes {
    <<0x2D, rest:bytes>> -> #(True, rest)
    _ -> #(False, bytes)
  }
  case digits {
    <<0x30>> -> Ok(#(negative, 0))
    <<digit, rest:bytes>> if digit >= 0x31 && digit <= 0x39 ->
      case simple_digits(rest, digit - 0x30, 1) {
        Ok(magnitude) -> Ok(#(negative, magnitude))
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn simple_digits(
  bytes: BitArray,
  magnitude: Int,
  count: Int,
) -> Result(Int, Nil) {
  case count > 15, bytes {
    True, _ -> Error(Nil)
    False, <<>> -> Ok(magnitude)
    False, <<digit, rest:bytes>> if digit >= 0x30 && digit <= 0x39 ->
      simple_digits(rest, magnitude * 10 + digit - 0x30, count + 1)
    False, _ -> Error(Nil)
  }
}

/// Count the bytes that may belong to a number token: digits, signs, the
/// decimal point and exponent markers. `number.parse` checks the syntax.
fn number_span(bytes: BitArray, length: Int) -> #(Int, BitArray) {
  case bytes {
    <<byte, rest:bytes>>
      if byte >= 0x30
      && byte <= 0x39
      || byte == 0x2D
      || byte == 0x2B
      || byte == 0x2E
      || byte == 0x65
      || byte == 0x45
    -> number_span(rest, length + 1)
    _ -> #(length, bytes)
  }
}

/// Parse string contents that follow the opening quote at `start`.
fn parse_string(
  bytes: BitArray,
  offset: Int,
  start: Int,
) -> Result(#(String, BitArray, Int), Failure) {
  scan_string(bytes, bytes, 0, offset, start, [])
}

/// `run` holds the bytes from the start of the current unescaped run, of
/// which `run_length` have been scanned. `chunks` holds earlier pieces in
/// reverse order.
fn scan_string(
  run: BitArray,
  bytes: BitArray,
  run_length: Int,
  offset: Int,
  start: Int,
  chunks: List(BitArray),
) -> Result(#(String, BitArray, Int), Failure) {
  case bytes {
    <<>> -> Error(Failure(start, Known(UnterminatedString)))
    <<0x22, rest:bytes>> -> {
      let chunks = add_run(chunks, run, run_length)
      Ok(#(finish_string(chunks), rest, offset + 1))
    }
    <<0x5C, rest:bytes>> -> {
      let chunks = add_run(chunks, run, run_length)
      case parse_escape(rest, offset, start) {
        Error(failure) -> Error(failure)
        Ok(#(decoded, rest, offset)) ->
          scan_string(rest, rest, 0, offset, start, [decoded, ..chunks])
      }
    }
    <<byte, _:bytes>> if byte < 0x20 -> Error(Failure(offset, Unexpected))
    <<_, rest:bytes>> ->
      scan_string(run, rest, run_length + 1, offset + 1, start, chunks)
    _ -> Error(Failure(start, Known(UnterminatedString)))
  }
}

fn add_run(
  chunks: List(BitArray),
  run: BitArray,
  run_length: Int,
) -> List(BitArray) {
  case run_length {
    0 -> chunks
    _ -> {
      let assert Ok(piece) = bit_array.slice(run, 0, run_length)
      [piece, ..chunks]
    }
  }
}

fn finish_string(chunks: List(BitArray)) -> String {
  // Pieces split the valid UTF-8 input only at ASCII quotes and backslashes,
  // and decoded escapes are valid scalar values, so the result is UTF-8.
  let assert Ok(text) =
    bit_array.to_string(bit_array.concat(list.reverse(chunks)))
  copy_string(text)
}

/// Decode the escape whose backslash is at `escape`.
fn parse_escape(
  bytes: BitArray,
  escape: Int,
  start: Int,
) -> Result(#(BitArray, BitArray, Int), Failure) {
  case bytes {
    <<>> -> Error(Failure(start, Known(UnterminatedString)))
    <<0x22, rest:bytes>> -> Ok(#(<<0x22>>, rest, escape + 2))
    <<0x5C, rest:bytes>> -> Ok(#(<<0x5C>>, rest, escape + 2))
    <<0x2F, rest:bytes>> -> Ok(#(<<0x2F>>, rest, escape + 2))
    <<0x62, rest:bytes>> -> Ok(#(<<0x08>>, rest, escape + 2))
    <<0x66, rest:bytes>> -> Ok(#(<<0x0C>>, rest, escape + 2))
    <<0x6E, rest:bytes>> -> Ok(#(<<0x0A>>, rest, escape + 2))
    <<0x72, rest:bytes>> -> Ok(#(<<0x0D>>, rest, escape + 2))
    <<0x74, rest:bytes>> -> Ok(#(<<0x09>>, rest, escape + 2))
    <<0x75, rest:bytes>> -> parse_unicode_escape(rest, escape)
    _ -> Error(Failure(escape, Known(InvalidEscape)))
  }
}

fn parse_unicode_escape(
  bytes: BitArray,
  escape: Int,
) -> Result(#(BitArray, BitArray, Int), Failure) {
  let invalid = Error(Failure(escape, Known(InvalidUnicodeEscape)))
  case hex4(bytes) {
    Error(Nil) -> invalid
    Ok(#(high, rest)) ->
      case high >= 0xD800 && high <= 0xDBFF {
        False ->
          case string.utf_codepoint(high) {
            Error(Nil) -> invalid
            Ok(codepoint) ->
              Ok(#(encode_codepoint(codepoint), rest, escape + 6))
          }
        True ->
          case rest {
            <<0x5C, 0x75, rest:bytes>> ->
              case hex4(rest) {
                Ok(#(low, rest)) if low >= 0xDC00 && low <= 0xDFFF -> {
                  let combined =
                    0x10000 + { high - 0xD800 } * 1024 + { low - 0xDC00 }
                  case string.utf_codepoint(combined) {
                    Error(Nil) -> invalid
                    Ok(codepoint) ->
                      Ok(#(encode_codepoint(codepoint), rest, escape + 12))
                  }
                }
                _ -> invalid
              }
            _ -> invalid
          }
      }
  }
}

fn encode_codepoint(codepoint: UtfCodepoint) -> BitArray {
  bit_array.from_string(string.from_utf_codepoints([codepoint]))
}

fn hex4(bytes: BitArray) -> Result(#(Int, BitArray), Nil) {
  case bytes {
    <<a, b, c, d, rest:bytes>> ->
      case hex_value(a), hex_value(b), hex_value(c), hex_value(d) {
        Ok(a), Ok(b), Ok(c), Ok(d) ->
          Ok(#(a * 4096 + b * 256 + c * 16 + d, rest))
        _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn hex_value(byte: Int) -> Result(Int, Nil) {
  case byte {
    _ if byte >= 0x30 && byte <= 0x39 -> Ok(byte - 0x30)
    _ if byte >= 0x61 && byte <= 0x66 -> Ok(byte - 0x61 + 10)
    _ if byte >= 0x41 && byte <= 0x46 -> Ok(byte - 0x41 + 10)
    _ -> Error(Nil)
  }
}

/// `bytes` follows the `[` at `open`.
fn parse_array(
  limits: Limits,
  bytes: BitArray,
  open: Int,
  depth: Int,
  count: Int,
) -> Parsed(Value) {
  case depth + 1 > limits.max_depth {
    True -> Error(Failure(open, Known(DepthLimitExceeded(limits.max_depth))))
    False -> {
      let #(rest, offset) = skip_whitespace(bytes, open + 1)
      case rest {
        <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
        <<0x5D, rest:bytes>> -> Ok(#(Array([]), rest, offset + 1, count))
        _ -> parse_elements(limits, rest, offset, depth + 1, count, [])
      }
    }
  }
}

fn parse_elements(
  limits: Limits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  count: Int,
  elements: List(Value),
) -> Parsed(Value) {
  case parse_any(limits, bytes, offset, depth, count) {
    Error(failure) -> Error(failure)
    Ok(#(element, rest, offset, count)) -> {
      let #(rest, offset) = skip_whitespace(rest, offset)
      case rest {
        <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
        <<0x2C, rest:bytes>> -> {
          let #(rest, offset) = skip_whitespace(rest, offset + 1)
          case rest {
            <<0x5D, _:bytes>> -> Error(Failure(offset, Unexpected))
            _ ->
              parse_elements(limits, rest, offset, depth, count, [
                element,
                ..elements
              ])
          }
        }
        <<0x5D, rest:bytes>> ->
          Ok(#(
            Array(list.reverse([element, ..elements])),
            rest,
            offset + 1,
            count,
          ))
        _ -> Error(Failure(offset, Unexpected))
      }
    }
  }
}

/// `bytes` follows the `{` at `open`.
fn parse_object(
  limits: Limits,
  bytes: BitArray,
  open: Int,
  depth: Int,
  count: Int,
) -> Parsed(Value) {
  case depth + 1 > limits.max_depth {
    True -> Error(Failure(open, Known(DepthLimitExceeded(limits.max_depth))))
    False -> {
      let #(rest, offset) = skip_whitespace(bytes, open + 1)
      case rest {
        <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
        <<0x7D, rest:bytes>> -> Ok(#(Object([]), rest, offset + 1, count))
        _ ->
          parse_members(limits, rest, offset, depth + 1, count, dict.new(), [])
      }
    }
  }
}

type Next {
  More
  Last
}

fn parse_members(
  limits: Limits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  count: Int,
  seen: Dict(String, Nil),
  members: List(#(String, Value)),
) -> Parsed(Value) {
  case parse_member(limits, bytes, offset, depth, count, seen) {
    Error(failure) -> Error(failure)
    Ok(#(#(key, member, next), rest, offset, count)) -> {
      let members = [#(key, member), ..members]
      case next {
        More ->
          parse_members(
            limits,
            rest,
            offset,
            depth,
            count,
            dict.insert(seen, key, Nil),
            members,
          )
        Last -> Ok(#(Object(list.reverse(members)), rest, offset, count))
      }
    }
  }
}

/// Parse one `"key": value` member and the `,` or `}` that follows it.
fn parse_member(
  limits: Limits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  count: Int,
  seen: Dict(String, Nil),
) -> Parsed(#(String, Value, Next)) {
  case bytes {
    <<0x22, rest:bytes>> ->
      case parse_string(rest, offset + 1, offset) {
        Error(failure) -> Error(failure)
        Ok(#(key, rest, after_key)) ->
          case dict.has_key(seen, key) {
            True -> Error(Failure(offset, Known(DuplicateObjectKey)))
            False ->
              parse_member_value(limits, rest, after_key, depth, count, key)
          }
      }
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    _ -> Error(Failure(offset, Unexpected))
  }
}

fn parse_member_value(
  limits: Limits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  count: Int,
  key: String,
) -> Parsed(#(String, Value, Next)) {
  let #(rest, offset) = skip_whitespace(bytes, offset)
  case rest {
    <<0x3A, rest:bytes>> -> {
      let #(rest, offset) = skip_whitespace(rest, offset + 1)
      case parse_any(limits, rest, offset, depth, count) {
        Error(failure) -> Error(failure)
        Ok(#(member, rest, offset, count)) -> {
          let #(rest, offset) = skip_whitespace(rest, offset)
          case rest {
            <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
            <<0x2C, rest:bytes>> -> {
              let #(rest, offset) = skip_whitespace(rest, offset + 1)
              case rest {
                <<0x7D, _:bytes>> -> Error(Failure(offset, Unexpected))
                _ -> Ok(#(#(key, member, More), rest, offset, count))
              }
            }
            <<0x7D, rest:bytes>> ->
              Ok(#(#(key, member, Last), rest, offset + 1, count))
            _ -> Error(Failure(offset, Unexpected))
          }
        }
      }
    }
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    _ -> Error(Failure(offset, Unexpected))
  }
}

/// Compute the line and column of a failure. Lines end at LF, CR or CRLF.
/// Columns count grapheme clusters from the start of the line, from 1.
fn locate(source: BitArray, failure: Failure) -> ParseError {
  let Failure(offset, kind) = failure
  let #(line, line_start) = find_line(source, 0, offset, 1, 0)
  let column = case bit_array.slice(source, line_start, offset - line_start) {
    Ok(segment) ->
      case bit_array.to_string(segment) {
        Ok(text) -> string.length(text) + 1
        Error(Nil) -> offset - line_start + 1
      }
    Error(Nil) -> 1
  }
  let reason = case kind {
    Known(reason) -> reason
    Unexpected -> UnexpectedCharacter
  }
  ParseError(Location(offset, line, column), reason)
}

fn find_line(
  bytes: BitArray,
  position: Int,
  stop: Int,
  line: Int,
  line_start: Int,
) -> #(Int, Int) {
  case position >= stop, bytes {
    True, _ -> #(line, line_start)
    False, <<0x0D, 0x0A, rest:bytes>> ->
      find_line(rest, position + 2, stop, line + 1, position + 2)
    False, <<0x0D, rest:bytes>> | False, <<0x0A, rest:bytes>> ->
      find_line(rest, position + 1, stop, line + 1, position + 1)
    False, <<_, rest:bytes>> ->
      find_line(rest, position + 1, stop, line, line_start)
    False, _ -> #(line, line_start)
  }
}

fn find_invalid_utf8(
  bytes: BitArray,
  offset: Int,
  line: Int,
  col: Int,
) -> Location {
  case bytes {
    <<>> -> Location(offset, line, col)
    <<13, 10, rest:bits>> -> find_invalid_utf8(rest, offset + 2, line + 1, 1)
    <<13, rest:bits>> -> find_invalid_utf8(rest, offset + 1, line + 1, 1)
    <<10, rest:bits>> -> find_invalid_utf8(rest, offset + 1, line + 1, 1)
    <<b, rest:bits>> if b < 128 ->
      find_invalid_utf8(rest, offset + 1, line, col + 1)
    <<b1, b2, rest:bits>> if b1 >= 194 && b1 <= 223 && b2 >= 128 && b2 <= 191 ->
      find_invalid_utf8(rest, offset + 2, line, col + 1)
    <<b1, b2, b3, rest:bits>>
      if b1 == 224
      && b2 >= 160
      && b2 <= 191
      && b3 >= 128
      && b3 <= 191
      || b1 >= 225
      && b1 <= 236
      && b2 >= 128
      && b2 <= 191
      && b3 >= 128
      && b3 <= 191
      || b1 == 237
      && b2 >= 128
      && b2 <= 159
      && b3 >= 128
      && b3 <= 191
      || b1 >= 238
      && b1 <= 239
      && b2 >= 128
      && b2 <= 191
      && b3 >= 128
      && b3 <= 191
    -> find_invalid_utf8(rest, offset + 3, line, col + 1)
    <<b1, b2, b3, b4, rest:bits>>
      if b1 == 240
      && b2 >= 144
      && b2 <= 191
      && b3 >= 128
      && b3 <= 191
      && b4 >= 128
      && b4 <= 191
      || b1 >= 241
      && b1 <= 243
      && b2 >= 128
      && b2 <= 191
      && b3 >= 128
      && b3 <= 191
      && b4 >= 128
      && b4 <= 191
      || b1 == 244
      && b2 >= 128
      && b2 <= 143
      && b3 >= 128
      && b3 <= 191
      && b4 >= 128
      && b4 <= 191
    -> find_invalid_utf8(rest, offset + 4, line, col + 1)
    _ -> Location(offset, line, col)
  }
}

// --- text --------------------------------------------------------------------

/// Render compact JSON text with no whitespace, keeping member order.
/// Numbers are exact. A number whose decimal exponent is from -7 to 20, and
/// on Erlang an integer of at most 50 digits, is written in plain decimal,
/// such as `12.5` or `0.001`; other numbers use `number.to_string`, such as
/// `1e-9`.
pub fn to_string(value: Value) -> String {
  case value {
    Null -> "null"
    Bool(True) -> "true"
    Bool(False) -> "false"
    String(item) -> json.to_string(json.string(item))
    Number(item) ->
      case number.to_int(item, 50) {
        Ok(integer) -> int.to_string(integer)
        Error(_) -> decimal_text(number.to_string(item))
      }
    Array(items) -> "[" <> string.join(list.map(items, to_string), ",") <> "]"
    Object(pairs) ->
      "{"
      <> string.join(
        list.map(pairs, fn(pair) {
          json.to_string(json.string(pair.0)) <> ":" <> to_string(pair.1)
        }),
        ",",
      )
      <> "}"
  }
}

/// Rewrite `number.to_string`'s `d.ddde±x` form in plain decimal when the
/// exponent is from -7 to 20.
fn decimal_text(scientific: String) -> String {
  let #(sign, unsigned) = case scientific {
    "-" <> rest -> #("-", rest)
    _ -> #("", scientific)
  }
  let #(mantissa, exponent) = case string.split_once(unsigned, "e") {
    Ok(#(mantissa, exponent)) -> #(mantissa, int.parse(exponent))
    Error(Nil) -> #(unsigned, Ok(0))
  }
  let digits = string.replace(mantissa, ".", "")
  let count = string.length(digits)
  case exponent {
    Ok(scale) if scale >= 0 && scale <= 20 && count > scale + 1 ->
      sign
      <> string.slice(digits, 0, scale + 1)
      <> "."
      <> string.drop_start(digits, scale + 1)
    Ok(scale) if scale >= 0 && scale <= 20 ->
      sign <> digits <> string.repeat("0", scale + 1 - count)
    Ok(scale) if scale < 0 && scale >= -7 ->
      sign <> "0." <> string.repeat("0", -scale - 1) <> digits
    _ -> scientific
  }
}

// --- gleam/json bridges ------------------------------------------------------

/// Convert to `gleam/json`, exactly. An integer becomes `json.int` (on
/// JavaScript, only a safe integer); another number becomes `json.float`
/// when the float's printed form reads back as the same number, such as
/// `0.1` or `1e20`. Fails with the first number that has no exact
/// `gleam/json` form, such as `1e400` or `0.1000000000000000001`.
pub fn to_json(value: Value) -> Result(json.Json, Number) {
  case value {
    Null -> Ok(json.null())
    Bool(item) -> Ok(json.bool(item))
    String(item) -> Ok(json.string(item))
    Number(item) -> number_to_json(item)
    Array(items) -> array_to_json(items, [])
    Object(members) -> members_to_json(members, [])
  }
}

fn array_to_json(
  items: List(Value),
  done: List(json.Json),
) -> Result(json.Json, Number) {
  case items {
    [] -> Ok(json.preprocessed_array(list.reverse(done)))
    [item, ..rest] ->
      case to_json(item) {
        Ok(converted) -> array_to_json(rest, [converted, ..done])
        Error(number) -> Error(number)
      }
  }
}

fn members_to_json(
  members: List(#(String, Value)),
  done: List(#(String, json.Json)),
) -> Result(json.Json, Number) {
  case members {
    [] -> Ok(json.object(list.reverse(done)))
    [#(key, item), ..rest] ->
      case to_json(item) {
        Ok(converted) -> members_to_json(rest, [#(key, converted), ..done])
        Error(number) -> Error(number)
      }
  }
}

fn number_to_json(item: Number) -> Result(json.Json, Number) {
  case number.to_int(item, 400) {
    Ok(integer) -> Ok(json.int(integer))
    Error(_) ->
      case number.to_float(item) {
        Error(_) -> Error(item)
        Ok(float) ->
          case number.from_float(float) {
            Ok(printed) ->
              case number.compare(printed, item) {
                order.Eq -> Ok(json.float(float))
                _ -> Error(item)
              }
            Error(_) -> Error(item)
          }
      }
  }
}

/// A decoder of the data that `gleam/json`'s `json.parse` produces. Use it to
/// read a `Value` through another JSON parser, for example
/// `json.parse(text, value.decoder())`.
///
/// That parser owns duplicate keys, number precision and size limits: it
/// keeps one of repeated keys, reads numbers as `Int` or `Float`, and does not
/// keep member order. A float becomes the shortest decimal that reads back
/// as the same float. Use `parse` for strict, bounded reading.
pub fn decoder() -> decode.Decoder(Value) {
  decode.recursive(fn() {
    decode.one_of(decode.string |> decode.map(String), [
      decode.bool |> decode.map(Bool),
      decode.int |> decode.then(int_value),
      decode.float |> decode.then(float_value),
      decode.list(decoder()) |> decode.map(Array),
      decode.dict(decode.string, decoder())
        |> decode.map(fn(members) { Object(dict.to_list(members)) }),
      null_decoder(),
    ])
  })
}

fn int_value(item: Int) -> decode.Decoder(Value) {
  case number.from_int(item) {
    Ok(parsed) -> decode.success(Number(parsed))
    // A JavaScript integer outside the safe range is a float to JSON.
    Error(_) -> float_value(int.to_float(item))
  }
}

fn float_value(item: Float) -> decode.Decoder(Value) {
  case number.from_float(item) {
    Ok(parsed) -> decode.success(Number(parsed))
    Error(_) -> decode.failure(Null, "a finite number")
  }
}

fn null_decoder() -> decode.Decoder(Value) {
  decode.optional(decode.failure(Null, "Null"))
  |> decode.then(fn(found) {
    case found {
      None -> decode.success(Null)
      Some(_) -> decode.failure(Null, "Null")
    }
  })
}
