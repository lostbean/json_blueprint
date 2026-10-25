//// The JSON value model, byte-bounded parsing, its text form and bridges
//// to `gleam/json`.
////
//// Numbers retain exact mathematical values and repeated object keys reject.
//// Erlang parses through OTP's native JSON parser; JavaScript uses the package
//// parser. Parsed object member order and syntax diagnostics are target-specific.
//// Manually constructed `Object` values retain the supplied member order.
////
//// `default_limits()` admits at most 1 MiB (1,048,576 bytes). Change that bound
//// with `with_max_bytes`. There are no document-depth, value-count or global
//// numeric-token admission limits. The byte bound is not a heap-memory quota.
//// Numeric native projection and codec constraints still apply independently.
//// JavaScript recursion remains subject to the host stack capacity; exhaustion
//// returns `RuntimeCapacityExceeded`, not a configured document-depth failure.
////
//// `to_string` renders compact JSON. `to_json` and `decoder` bridge native
//// `gleam/json` values, whose parsing policy differs from this module.
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
import gleam/result
import gleam/string
import json/blueprint/internal/native
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

/// The input-byte admission bound for `parse` and `parse_bits`.
pub opaque type Limits {
  Limits(max_bytes: Int)
}

/// Admit at most 1 MiB (1,048,576 bytes) of JSON text.
pub fn default_limits() -> Limits {
  Limits(1_048_576)
}

/// Accept at most `bytes` bytes of UTF-8 text. Below 1 rejects every input.
pub fn with_max_bytes(_limits: Limits, bytes: Int) -> Limits {
  Limits(max_bytes: bytes)
}

// --- errors ------------------------------------------------------------------

/// Where a parse failed: byte offset from 0, line and column from 1.
/// Columns count graphemes. A native diagnostic without a portable source
/// position uses `Location(0, 0, 0)`; it does not identify the first byte.
pub type Location {
  Location(byte_offset: Int, line: Int, column: Int)
}

/// Why parsing failed. `ByteLimitExceeded` is the input admission failure.
/// May gain variants in a minor release; match with a `_` branch.
pub type ParseReason {
  UnexpectedCharacter
  /// The native parser rejected the document without a portable location.
  NativeSyntax
  /// The host runtime could not finish parsing, independently of byte limits.
  RuntimeCapacityExceeded
  UnexpectedEndOfInput
  InvalidUtf8
  InvalidUnicodeScalar
  ByteLimitExceeded(max: Int)
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
    ByteLimitExceeded(_) -> True
    _ -> False
  }
}

/// Render a parse error as text such as
/// `invalid JSON at line 2, column 7: unexpected character`. The text names
/// the setter for a limit error and contains no input text.
pub fn describe_parse_error(error: ParseError) -> String {
  let ParseError(location, reason) = error
  case location.line {
    0 -> "invalid JSON: " <> describe_reason(reason)
    _ ->
      "invalid JSON at line "
      <> int.to_string(location.line)
      <> ", column "
      <> int.to_string(location.column)
      <> ": "
      <> describe_reason(reason)
  }
}

fn describe_reason(reason: ParseReason) -> String {
  case reason {
    UnexpectedCharacter -> "unexpected character"
    NativeSyntax -> "native parser rejected the document"
    RuntimeCapacityExceeded -> "runtime parsing capacity exceeded"
    UnexpectedEndOfInput -> "unexpected end of input"
    InvalidUtf8 -> "invalid UTF-8"
    InvalidUnicodeScalar -> "invalid Unicode scalar"
    ByteLimitExceeded(max) ->
      "more than " <> int.to_string(max) <> " bytes (value.with_max_bytes)"
    InvalidNumber(number.InvalidSyntax) -> "invalid number"
    InvalidNumber(number.TokenTooLong) -> "number token too long"
    InvalidNumber(number.TooManySignificandDigits) ->
      "number has too many digits"
    InvalidNumber(number.ExponentOutOfRange) -> "number exponent out of range"
    DuplicateObjectKey -> "duplicate object key"
    UnterminatedString -> "unterminated string"
    InvalidEscape -> "invalid escape sequence"
    InvalidUnicodeEscape -> "invalid Unicode escape"
    TrailingContent -> "trailing content"
  }
}

// --- parsing -----------------------------------------------------------------

/// Parse JSON with byte admission, duplicate rejection and exact numbers.
/// Erlang uses native parsing; object order and syntax diagnostics may differ
/// from JavaScript. No depth, value-count or global numeric cap is applied.
pub fn parse(source: String, limits: Limits) -> Result(Value, ParseError) {
  case native.supported() {
    True -> parse_native(source, limits) |> result.try(from_native)
    False -> {
      use bytes <- result.try(admit_text(source, limits))
      parse_document(bytes)
    }
  }
}

/// Native parsing without building the public Value tree. Codec decoding
/// uses this path only on a supported backend. Native syntax and duplicate
/// diagnostics have no portable source position and use Location(0, 0, 0).
@internal
pub fn parse_native(
  source: String,
  limits: Limits,
) -> Result(native.Raw, ParseError) {
  native.parse(source, limits.max_bytes)
  |> result.map_error(fn(error) {
    case error {
      native.ByteLimitExceeded ->
        ParseError(Location(0, 1, 1), ByteLimitExceeded(limits.max_bytes))
      native.InvalidUnicodeScalar ->
        ParseError(Location(0, 0, 0), InvalidUnicodeScalar)
      native.DuplicateKey(_) ->
        ParseError(Location(0, 0, 0), DuplicateObjectKey)
      native.Syntax(_) | native.UnsupportedRuntime ->
        ParseError(Location(0, 0, 0), NativeSyntax)
    }
  })
}

/// Materialize a native subtree only for a public Value or custom-codec
/// fallback. Numbers become exact Number values on demand. Native map key
/// order is not the original source order.
@internal
pub fn from_native(raw: native.Raw) -> Result(Value, ParseError) {
  case native.kind(raw) {
    native.Null -> Ok(Null)
    native.Bool -> {
      let assert Ok(item) = native.bool(raw)
      Ok(Bool(item))
    }
    native.String -> {
      let assert Ok(item) = native.string(raw)
      Ok(String(item))
    }
    native.Number ->
      native.number(raw)
      |> result.map(Number)
      |> result.map_error(fn(_) {
        ParseError(Location(0, 0, 0), InvalidNumber(number.InvalidSyntax))
      })
    native.Array -> {
      let assert Ok(items) = native.array_items(raw)
      list.try_map(items, from_native) |> result.map(Array)
    }
    native.Object -> {
      let assert Ok(keys) = native.keys(raw)
      keys
      |> list.try_map(fn(key) {
        let assert Ok(item) = native.field(raw, key)
        from_native(item) |> result.map(fn(item) { #(key, item) })
      })
      |> result.map(Object)
    }
  }
}

fn admit_text(source: String, limits: Limits) -> Result(BitArray, ParseError) {
  case text.exceeds_byte_limit(source, limits.max_bytes) {
    True ->
      Error(ParseError(Location(0, 1, 1), ByteLimitExceeded(limits.max_bytes)))
    False ->
      case text.validate_scalars(source) {
        Ok(Nil) -> Ok(bit_array.from_string(source))
        Error(prefix) -> {
          let prefix = bit_array.from_string(prefix)
          Error(locate(
            prefix,
            Failure(bit_array.byte_size(prefix), Known(InvalidUnicodeScalar)),
          ))
        }
      }
  }
}

/// Parse UTF-8 bytes. Byte admission precedes UTF-8 validation. Invalid UTF-8
/// retains the first invalid byte location independently of the JSON backend.
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
        True ->
          case native.supported() {
            True -> {
              let assert Ok(source) = bit_array.to_string(bytes)
              parse_native(source, limits) |> result.try(from_native)
            }
            False -> parse_document(bytes)
          }
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

/// A parsed item, the rest of the input and its offset.
type Parsed(a) =
  Result(#(a, BitArray, Int), Failure)

@external(erlang, "json_blueprint_ffi", "copy_string")
@external(javascript, "../../json_blueprint_ffi.mjs", "copy_string")
fn copy_string(text: String) -> String

@external(javascript, "../../json_blueprint_ffi.mjs", "with_parser_capacity")
fn with_parser_capacity(
  work: fn() -> Result(Value, ParseError),
  _capacity_error: ParseError,
) -> Result(Value, ParseError) {
  work()
}

fn parse_document(source: BitArray) -> Result(Value, ParseError) {
  with_parser_capacity(
    fn() { parse_portable_document(source) },
    ParseError(Location(0, 0, 0), RuntimeCapacityExceeded),
  )
}

fn parse_portable_document(source: BitArray) -> Result(Value, ParseError) {
  let #(rest, offset) = skip_whitespace(source, 0)
  let result = case rest {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    _ ->
      case parse_any(rest, offset) {
        Error(failure) -> Error(failure)
        Ok(#(parsed, rest, offset)) -> {
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

fn parse_any(bytes: BitArray, offset: Int) -> Parsed(Value) {
  case bytes {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    // null
    <<0x6E, 0x75, 0x6C, 0x6C, rest:bytes>> -> Ok(#(Null, rest, offset + 4))
    // true
    <<0x74, 0x72, 0x75, 0x65, rest:bytes>> ->
      Ok(#(Bool(True), rest, offset + 4))
    // false
    <<0x66, 0x61, 0x6C, 0x73, 0x65, rest:bytes>> ->
      Ok(#(Bool(False), rest, offset + 5))
    <<0x22, rest:bytes>> ->
      case parse_string(rest, offset + 1, offset) {
        Error(failure) -> Error(failure)
        Ok(#(text, rest, offset)) -> Ok(#(String(text), rest, offset))
      }
    <<0x5B, rest:bytes>> -> parse_array(rest, offset)
    <<0x7B, rest:bytes>> -> parse_object(rest, offset)
    <<byte, _:bytes>> if byte == 0x2D || byte >= 0x30 && byte <= 0x39 ->
      case parse_number(bytes, offset) {
        Error(failure) -> Error(failure)
        Ok(#(parsed, rest, offset)) -> Ok(#(Number(parsed), rest, offset))
      }
    _ -> Error(Failure(offset, Unexpected))
  }
}

fn parse_number(
  bytes: BitArray,
  offset: Int,
) -> Result(#(Number, BitArray, Int), Failure) {
  let #(length, rest) = number_span(bytes, 0)
  let assert Ok(token_bytes) = bit_array.slice(bytes, 0, length)
  let small = case simple_integer(token_bytes) {
    Ok(#(negative, magnitude)) ->
      case negative {
        True -> number.from_int(0 - magnitude)
        False -> number.from_int(magnitude)
      }
      |> result_to_nil
    Error(_) -> Error(Nil)
  }
  case small {
    Ok(parsed) -> Ok(#(parsed, rest, offset + length))
    Error(Nil) -> {
      let assert Ok(token) = bit_array.to_string(token_bytes)
      case number.from_json_token(token) {
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
      Ok(#(finish_string(run, run_length, chunks), rest, offset + 1))
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
    // Scan ordinary runs two bytes at a time to reduce bit-array slicing.
    // Quotes, escapes and controls still take the single-byte branches.
    <<a, b, rest:bytes>>
      if a >= 0x20
      && a != 0x22
      && a != 0x5C
      && b >= 0x20
      && b != 0x22
      && b != 0x5C
    -> scan_string(run, rest, run_length + 2, offset + 2, start, chunks)
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

fn finish_string(
  run: BitArray,
  run_length: Int,
  chunks: List(BitArray),
) -> String {
  // Unescaped strings need no chunk list or concatenation. Keep the copy:
  // a short string must not retain the document's source binary.
  let bytes = case chunks {
    [] -> {
      let assert Ok(piece) = bit_array.slice(run, 0, run_length)
      piece
    }
    _ -> bit_array.concat(list.reverse(add_run(chunks, run, run_length)))
  }
  // Runs split valid UTF-8 only at ASCII quotes and backslashes, and decoded
  // escapes are scalar values, so the assembled result is valid UTF-8.
  let assert Ok(text) = bit_array.to_string(bytes)
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
fn parse_array(bytes: BitArray, open: Int) -> Parsed(Value) {
  let #(rest, offset) = skip_whitespace(bytes, open + 1)
  case rest {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    <<0x5D, rest:bytes>> -> Ok(#(Array([]), rest, offset + 1))
    _ -> parse_elements(rest, offset, [])
  }
}

fn parse_elements(
  bytes: BitArray,
  offset: Int,
  elements: List(Value),
) -> Parsed(Value) {
  case parse_any(bytes, offset) {
    Error(failure) -> Error(failure)
    Ok(#(element, rest, offset)) -> {
      let #(rest, offset) = skip_whitespace(rest, offset)
      case rest {
        <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
        <<0x2C, rest:bytes>> -> {
          let #(rest, offset) = skip_whitespace(rest, offset + 1)
          case rest {
            <<0x5D, _:bytes>> -> Error(Failure(offset, Unexpected))
            _ -> parse_elements(rest, offset, [element, ..elements])
          }
        }
        <<0x5D, rest:bytes>> ->
          Ok(#(Array(list.reverse([element, ..elements])), rest, offset + 1))
        _ -> Error(Failure(offset, Unexpected))
      }
    }
  }
}

/// `bytes` follows the `{` at `open`.
fn parse_object(bytes: BitArray, open: Int) -> Parsed(Value) {
  let #(rest, offset) = skip_whitespace(bytes, open + 1)
  case rest {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    <<0x7D, rest:bytes>> -> Ok(#(Object([]), rest, offset + 1))
    _ -> parse_members(rest, offset, dict.new(), [])
  }
}

type Next {
  More
  Last
}

fn parse_members(
  bytes: BitArray,
  offset: Int,
  seen: Dict(String, Nil),
  members: List(#(String, Value)),
) -> Parsed(Value) {
  case parse_member(bytes, offset, seen) {
    Error(failure) -> Error(failure)
    Ok(#(#(key, member, next), rest, offset)) -> {
      let members = [#(key, member), ..members]
      case next {
        More ->
          parse_members(rest, offset, dict.insert(seen, key, Nil), members)
        Last -> Ok(#(Object(list.reverse(members)), rest, offset))
      }
    }
  }
}

/// Parse one `"key": value` member and the `,` or `}` that follows it.
fn parse_member(
  bytes: BitArray,
  offset: Int,
  seen: Dict(String, Nil),
) -> Parsed(#(String, Value, Next)) {
  case bytes {
    <<0x22, rest:bytes>> ->
      case parse_string(rest, offset + 1, offset) {
        Error(failure) -> Error(failure)
        Ok(#(key, rest, after_key)) ->
          case dict.has_key(seen, key) {
            True -> Error(Failure(offset, Known(DuplicateObjectKey)))
            False -> parse_member_value(rest, after_key, key)
          }
      }
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    _ -> Error(Failure(offset, Unexpected))
  }
}

fn parse_member_value(
  bytes: BitArray,
  offset: Int,
  key: String,
) -> Parsed(#(String, Value, Next)) {
  let #(rest, offset) = skip_whitespace(bytes, offset)
  case rest {
    <<0x3A, rest:bytes>> -> {
      let #(rest, offset) = skip_whitespace(rest, offset + 1)
      case parse_any(rest, offset) {
        Error(failure) -> Error(failure)
        Ok(#(member, rest, offset)) -> {
          let #(rest, offset) = skip_whitespace(rest, offset)
          case rest {
            <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
            <<0x2C, rest:bytes>> -> {
              let #(rest, offset) = skip_whitespace(rest, offset + 1)
              case rest {
                <<0x7D, _:bytes>> -> Error(Failure(offset, Unexpected))
                _ -> Ok(#(#(key, member, More), rest, offset))
              }
            }
            <<0x7D, rest:bytes>> ->
              Ok(#(#(key, member, Last), rest, offset + 1))
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
