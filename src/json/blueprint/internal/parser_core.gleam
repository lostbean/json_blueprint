//// Strict JSON text admission over UTF-8 bytes.
////
//// The parser reads bytes directly and keeps only the byte offset while it
//// parses. Line and column are computed from the input once, when an error
//// is reported, so a successful parse allocates no per-character state.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import json/blueprint/number.{type NumberError}
import json/blueprint/parser_limits
import json/blueprint/value.{type Value}

pub type ParserLimits =
  parser_limits.ParserLimits

pub type Location {
  Location(byte_offset: Int, line: Int, column: Int)
}

pub type ParseErrorKind {
  UnexpectedByte(String)
  UnexpectedEndOfInput
  InvalidUtf8
  ByteLimitExceeded(max: Int)
  DepthLimitExceeded(max: Int)
  InvalidNumberToken(number: NumberError)
  DuplicateObjectKey(key: String)
  UnterminatedString
  InvalidEscapeSequence
  InvalidUnicodeEscape
  TrailingContent
}

pub type ParseError {
  ParseError(location: Location, kind: ParseErrorKind)
}

/// A failure at a byte offset whose line and column are not yet known.
type Failure {
  Failure(offset: Int, kind: FailureKind)
}

type FailureKind {
  /// The grapheme at the offset is not allowed there.
  Unexpected
  Known(ParseErrorKind)
}

type Parsed(a) =
  Result(#(a, BitArray, Int), Failure)

/// Report whether `source` has more than `max_bytes` bytes of UTF-8, without
/// encoding it on targets whose strings are not UTF-8.
@external(erlang, "json_blueprint_ffi", "utf8_byte_size_exceeds")
@external(javascript, "../../../json_blueprint_ffi.mjs", "utf8_byte_size_exceeds")
pub fn exceeds_byte_limit(source: String, max_bytes: Int) -> Bool

/// Copy a string so that it does not share memory with the parser's input.
@external(erlang, "json_blueprint_ffi", "copy_string")
@external(javascript, "../../../json_blueprint_ffi.mjs", "copy_string")
fn copy_string(text: String) -> String

pub fn parse_value(
  limits: ParserLimits,
  bytes: BitArray,
) -> Result(Value, ParseError) {
  let max_bytes = parser_limits.max_bytes(limits)
  case bit_array.byte_size(bytes) > max_bytes {
    True -> Error(ParseError(Location(0, 1, 1), ByteLimitExceeded(max_bytes)))
    False ->
      case bit_array.is_utf8(bytes) {
        False ->
          Error(ParseError(find_invalid_utf8(bytes, 0, 1, 1), InvalidUtf8))
        True -> parse_document(limits, bytes)
      }
  }
}

pub fn parse_value_from_string(
  limits: ParserLimits,
  source: String,
) -> Result(Value, ParseError) {
  let max_bytes = parser_limits.max_bytes(limits)
  case exceeds_byte_limit(source, max_bytes) {
    True -> Error(ParseError(Location(0, 1, 1), ByteLimitExceeded(max_bytes)))
    False -> parse_document(limits, bit_array.from_string(source))
  }
}

fn parse_document(
  limits: ParserLimits,
  source: BitArray,
) -> Result(Value, ParseError) {
  let #(rest, offset) = skip_whitespace(source, 0)
  let result = case rest {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    _ ->
      case parse_any(limits, rest, offset, 0) {
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

fn parse_any(
  limits: ParserLimits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
) -> Parsed(Value) {
  case bytes {
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    // null
    <<0x6E, 0x75, 0x6C, 0x6C, rest:bytes>> ->
      Ok(#(value.Null, rest, offset + 4))
    // true
    <<0x74, 0x72, 0x75, 0x65, rest:bytes>> ->
      Ok(#(value.Bool(True), rest, offset + 4))
    // false
    <<0x66, 0x61, 0x6C, 0x73, 0x65, rest:bytes>> ->
      Ok(#(value.Bool(False), rest, offset + 5))
    <<0x22, rest:bytes>> ->
      case parse_string(rest, offset + 1, offset) {
        Error(failure) -> Error(failure)
        Ok(#(text, rest, offset)) -> Ok(#(value.String(text), rest, offset))
      }
    <<0x5B, rest:bytes>> -> parse_array(limits, rest, offset, depth)
    <<0x7B, rest:bytes>> -> parse_object(limits, rest, offset, depth)
    <<byte, _:bytes>> if byte == 0x2D || byte >= 0x30 && byte <= 0x39 ->
      parse_number(limits, bytes, offset)
    _ -> Error(Failure(offset, Unexpected))
  }
}

fn parse_number(
  limits: ParserLimits,
  bytes: BitArray,
  offset: Int,
) -> Parsed(Value) {
  let #(length, rest) = number_span(bytes, 0)
  let assert Ok(token_bytes) = bit_array.slice(bytes, 0, length)
  let number_limits = parser_limits.number_limits(limits)
  let small = case simple_integer(token_bytes) {
    Ok(#(negative, magnitude, digits)) ->
      number.small_integer_token(number_limits, negative, magnitude, digits)
    Error(Nil) -> Error(Nil)
  }
  case small {
    Ok(parsed) -> Ok(#(value.Number(parsed), rest, offset + length))
    Error(Nil) -> {
      let assert Ok(token) = bit_array.to_string(token_bytes)
      case number.parse_number(number_limits, token) {
        Error(error) -> Error(Failure(offset, Known(InvalidNumberToken(error))))
        Ok(parsed) -> Ok(#(value.Number(parsed), rest, offset + length))
      }
    }
  }
}

/// Read an integer token of at most 15 digits without leading zeros as its
/// sign, magnitude and digit count.
fn simple_integer(bytes: BitArray) -> Result(#(Bool, Int, Int), Nil) {
  let #(negative, digits) = case bytes {
    <<0x2D, rest:bytes>> -> #(True, rest)
    _ -> #(False, bytes)
  }
  case digits {
    <<0x30>> -> Ok(#(negative, 0, 1))
    <<digit, rest:bytes>> if digit >= 0x31 && digit <= 0x39 ->
      case simple_digits(rest, digit - 0x30, 1) {
        Ok(#(magnitude, count)) -> Ok(#(negative, magnitude, count))
        Error(Nil) -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn simple_digits(
  bytes: BitArray,
  magnitude: Int,
  count: Int,
) -> Result(#(Int, Int), Nil) {
  case count > 15, bytes {
    True, _ -> Error(Nil)
    False, <<>> -> Ok(#(magnitude, count))
    False, <<digit, rest:bytes>> if digit >= 0x30 && digit <= 0x39 ->
      simple_digits(rest, magnitude * 10 + digit - 0x30, count + 1)
    False, _ -> Error(Nil)
  }
}

/// Count the bytes that may belong to a number token: digits, signs, the
/// decimal point and exponent markers. `number.parse_number` checks the
/// token's syntax.
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
fn parse_string(bytes: BitArray, offset: Int, start: Int) -> Parsed(String) {
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
) -> Parsed(String) {
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
fn parse_escape(bytes: BitArray, escape: Int, start: Int) -> Parsed(BitArray) {
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
    _ -> Error(Failure(escape, Known(InvalidEscapeSequence)))
  }
}

fn parse_unicode_escape(bytes: BitArray, escape: Int) -> Parsed(BitArray) {
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
  limits: ParserLimits,
  bytes: BitArray,
  open: Int,
  depth: Int,
) -> Parsed(Value) {
  let max_depth = parser_limits.max_depth(limits)
  case depth + 1 > max_depth {
    True -> Error(Failure(open, Known(DepthLimitExceeded(max_depth))))
    False -> {
      let #(rest, offset) = skip_whitespace(bytes, open + 1)
      case rest {
        <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
        <<0x5D, rest:bytes>> -> Ok(#(value.Array([]), rest, offset + 1))
        _ -> parse_elements(limits, rest, offset, depth + 1, [])
      }
    }
  }
}

fn parse_elements(
  limits: ParserLimits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  elements: List(Value),
) -> Parsed(Value) {
  case parse_any(limits, bytes, offset, depth) {
    Error(failure) -> Error(failure)
    Ok(#(element, rest, offset)) -> {
      let #(rest, offset) = skip_whitespace(rest, offset)
      case rest {
        <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
        <<0x2C, rest:bytes>> -> {
          let #(rest, offset) = skip_whitespace(rest, offset + 1)
          case rest {
            <<0x5D, _:bytes>> -> Error(Failure(offset, Unexpected))
            _ ->
              parse_elements(limits, rest, offset, depth, [element, ..elements])
          }
        }
        <<0x5D, rest:bytes>> ->
          Ok(#(
            value.Array(list.reverse([element, ..elements])),
            rest,
            offset + 1,
          ))
        _ -> Error(Failure(offset, Unexpected))
      }
    }
  }
}

/// `bytes` follows the `{` at `open`.
fn parse_object(
  limits: ParserLimits,
  bytes: BitArray,
  open: Int,
  depth: Int,
) -> Parsed(Value) {
  let max_depth = parser_limits.max_depth(limits)
  case depth + 1 > max_depth {
    True -> Error(Failure(open, Known(DepthLimitExceeded(max_depth))))
    False -> {
      let #(rest, offset) = skip_whitespace(bytes, open + 1)
      case rest {
        <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
        <<0x7D, rest:bytes>> -> Ok(#(value.Object([]), rest, offset + 1))
        _ -> parse_members(limits, rest, offset, depth + 1, dict.new(), [])
      }
    }
  }
}

type Next {
  More
  Last
}

fn parse_members(
  limits: ParserLimits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  seen: Dict(String, Nil),
  members: List(#(String, Value)),
) -> Parsed(Value) {
  case parse_member(limits, bytes, offset, depth, seen) {
    Error(failure) -> Error(failure)
    Ok(#(#(key, member, next), rest, offset)) -> {
      let members = [#(key, member), ..members]
      case next {
        More ->
          parse_members(
            limits,
            rest,
            offset,
            depth,
            dict.insert(seen, key, Nil),
            members,
          )
        Last -> Ok(#(value.Object(list.reverse(members)), rest, offset))
      }
    }
  }
}

/// Parse one `"key": value` member and the `,` or `}` that follows it.
fn parse_member(
  limits: ParserLimits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  seen: Dict(String, Nil),
) -> Parsed(#(String, Value, Next)) {
  case bytes {
    <<0x22, rest:bytes>> ->
      case parse_string(rest, offset + 1, offset) {
        Error(failure) -> Error(failure)
        Ok(#(key, rest, after_key)) ->
          case dict.has_key(seen, key) {
            True -> Error(Failure(offset, Known(DuplicateObjectKey(key))))
            False -> parse_member_value(limits, rest, after_key, depth, key)
          }
      }
    <<>> -> Error(Failure(offset, Known(UnexpectedEndOfInput)))
    _ -> Error(Failure(offset, Unexpected))
  }
}

fn parse_member_value(
  limits: ParserLimits,
  bytes: BitArray,
  offset: Int,
  depth: Int,
  key: String,
) -> Parsed(#(String, Value, Next)) {
  let #(rest, offset) = skip_whitespace(bytes, offset)
  case rest {
    <<0x3A, rest:bytes>> -> {
      let #(rest, offset) = skip_whitespace(rest, offset + 1)
      case parse_any(limits, rest, offset, depth) {
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
  let kind = case kind {
    Known(kind) -> kind
    Unexpected -> UnexpectedByte(grapheme_at(source, offset))
  }
  ParseError(Location(offset, line, column), kind)
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

fn grapheme_at(source: BitArray, offset: Int) -> String {
  let size = bit_array.byte_size(source)
  case bit_array.slice(source, offset, size - offset) {
    Error(Nil) -> ""
    Ok(rest) ->
      case bit_array.to_string(rest) {
        Error(Nil) -> ""
        Ok(text) ->
          case string.pop_grapheme(text) {
            Ok(#(grapheme, _)) -> grapheme
            Error(Nil) -> ""
          }
      }
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
