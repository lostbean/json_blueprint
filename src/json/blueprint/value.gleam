//// The JSON value model, byte-bounded parsing, its text form and bridges
//// to `gleam/json`.
////
//// Numbers retain exact mathematical values and repeated object keys reject.
//// Erlang uses OTP JSON; JavaScript uses JSON.parse with source retention and
//// strict duplicate/Unicode checks. Parsed member order is target-specific.
//// Native syntax diagnostics have no portable source location. JavaScript
//// requires JSON.parse reviver context.source; unsupported runtimes return
//// UnsupportedRuntime. There is no alternate parser.
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
  /// JavaScript lacks JSON.parse reviver source text; no fallback is used.
  UnsupportedRuntime
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
  case reason, location.line {
    UnsupportedRuntime, _ -> describe_reason(reason)
    _, 0 -> "invalid JSON: " <> describe_reason(reason)
    _, _ ->
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
    UnsupportedRuntime ->
      "JavaScript runtime requires JSON.parse reviver context.source"
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
/// Both targets use native parsing; object order may differ between targets.
/// No depth, value-count or global numeric cap is applied.
pub fn parse(source: String, limits: Limits) -> Result(Value, ParseError) {
  parse_native(source, limits) |> result.try(from_native)
}

/// Native parsing without building the public Value tree. Codec decoding
/// uses this path on both targets. Native syntax and duplicate
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
      // Retain explicit JavaScript runtime/number refusals.
      native.RuntimeCapacity ->
        ParseError(Location(0, 0, 0), RuntimeCapacityExceeded)
      native.NumberRepresentation ->
        ParseError(Location(0, 0, 0), InvalidNumber(number.ExponentOutOfRange))
      native.UnsupportedRuntime ->
        ParseError(Location(0, 0, 0), UnsupportedRuntime)
      native.Syntax(_) -> ParseError(Location(0, 0, 0), NativeSyntax)
    }
  })
}

@target(erlang)
/// Materialize a native subtree only for a public Value or custom-codec
/// fallback. Numbers become exact Number values on demand. Native map key
/// order is not the original source order.
@internal
pub fn from_native(raw: native.Raw) -> Result(Value, ParseError) {
  from_native_value(raw)
}

@target(javascript)
@internal
pub fn from_native(raw: native.Raw) -> Result(Value, ParseError) {
  // Capacity belongs to pure materialization, not callbacks.
  with_parser_capacity(
    fn() { from_native_value(raw) },
    ParseError(Location(0, 0, 0), RuntimeCapacityExceeded),
  )
}

fn from_native_value(raw: native.Raw) -> Result(Value, ParseError) {
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
      |> result.map_error(fn(error) {
        case error {
          native.ProjectionCapacity ->
            ParseError(Location(0, 0, 0), RuntimeCapacityExceeded)
          _ ->
            ParseError(Location(0, 0, 0), InvalidNumber(number.InvalidSyntax))
        }
      })
    native.Array -> {
      let assert Ok(items) = native.array_items(raw)
      list.try_map(items, from_native_value) |> result.map(Array)
    }
    native.Object -> {
      let assert Ok(keys) = native.keys(raw)
      keys
      |> list.try_map(fn(key) {
        let assert Ok(item) = native.field(raw, key)
        from_native_value(item) |> result.map(fn(item) { #(key, item) })
      })
      |> result.map(Object)
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
          case bytes {
            // JavaScript's UTF-8 decoder drops a leading BOM. Refuse it before
            // conversion; native JSON text rejects it too.
            <<239, 187, 191, _:bits>> ->
              Error(ParseError(Location(0, 0, 0), NativeSyntax))
            _ -> {
              let assert Ok(source) = bit_array.to_string(bytes)
              parse_native(source, limits) |> result.try(from_native)
            }
          }
      }
  }
}

@target(javascript)
@external(javascript, "../../json_blueprint_ffi.mjs", "with_parser_capacity")
fn with_parser_capacity(
  work: fn() -> Result(Value, ParseError),
  capacity_error: ParseError,
) -> Result(Value, ParseError)

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
