import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/string
import json/blueprint/number.{type NumberError, type NumberLimits}
import json/blueprint/value.{type Value}

pub opaque type ParserLimits {
  ParserLimits(max_bytes: Int, max_depth: Int, number_limits: NumberLimits)
}

pub type LimitsError {
  MaxBytesMustBePositive
  MaxDepthMustBePositive
}

pub fn parser_limits(
  max_bytes: Int,
  max_depth: Int,
  number_limits: NumberLimits,
) -> Result(ParserLimits, LimitsError) {
  case max_bytes > 0, max_depth > 0 {
    False, _ -> Error(MaxBytesMustBePositive)
    _, False -> Error(MaxDepthMustBePositive)
    True, True -> Ok(ParserLimits(max_bytes, max_depth, number_limits))
  }
}

pub fn default_limits() -> ParserLimits {
  let assert Ok(num_limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(limits) = parser_limits(10_485_760, 128, num_limits)
  limits
}

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

type State {
  State(
    chars: List(String),
    offset: Int,
    line: Int,
    column: Int,
    depth: Int,
    limits: ParserLimits,
  )
}

pub fn parse_value(
  limits: ParserLimits,
  bytes: BitArray,
) -> Result(Value, ParseError) {
  let ParserLimits(max_bytes, _, _) = limits
  let byte_size = bit_array.byte_size(bytes)
  case byte_size > max_bytes {
    True -> Error(ParseError(Location(0, 1, 1), ByteLimitExceeded(max_bytes)))
    False ->
      case bit_array.is_utf8(bytes) {
        False ->
          Error(ParseError(find_invalid_utf8(bytes, 0, 1, 1), InvalidUtf8))
        True -> {
          let assert Ok(source) = bit_array.to_string(bytes)
          parse_value_from_string(limits, source)
        }
      }
  }
}

pub fn parse_value_from_string(
  limits: ParserLimits,
  source: String,
) -> Result(Value, ParseError) {
  let ParserLimits(max_bytes, _, _) = limits
  let byte_size = string.byte_size(source)
  case byte_size > max_bytes {
    True -> Error(ParseError(Location(0, 1, 1), ByteLimitExceeded(max_bytes)))
    False -> {
      let chars = string.to_graphemes(source)
      let initial_state = State(chars, 0, 1, 1, 0, limits)
      let state = skip_whitespace(initial_state)
      case state.chars {
        [] -> Error(ParseError(current_location(state), UnexpectedEndOfInput))
        _ ->
          case parse_any_value(state) {
            Error(error) -> Error(error)
            Ok(#(val, state_after)) -> {
              let final_state = skip_whitespace(state_after)
              case final_state.chars {
                [] -> Ok(val)
                _ ->
                  Error(ParseError(
                    current_location(final_state),
                    TrailingContent,
                  ))
              }
            }
          }
      }
    }
  }
}

fn current_location(state: State) -> Location {
  Location(state.offset, state.line, state.column)
}

fn advance_char(state: State, char: String, rest: List(String)) -> State {
  let byte_len = string.byte_size(char)
  case char {
    "\n" | "\r\n" | "\r" ->
      State(
        ..state,
        chars: rest,
        offset: state.offset + byte_len,
        line: state.line + 1,
        column: 1,
      )
    _ ->
      State(
        ..state,
        chars: rest,
        offset: state.offset + byte_len,
        column: state.column + 1,
      )
  }
}

fn skip_whitespace(state: State) -> State {
  case state.chars {
    [" ", ..rest] -> skip_whitespace(advance_char(state, " ", rest))
    ["\t", ..rest] -> skip_whitespace(advance_char(state, "\t", rest))
    ["\r\n", ..rest] -> skip_whitespace(advance_char(state, "\r\n", rest))
    ["\r", ..rest] -> skip_whitespace(advance_char(state, "\r", rest))
    ["\n", ..rest] -> skip_whitespace(advance_char(state, "\n", rest))
    _ -> state
  }
}

fn parse_any_value(state: State) -> Result(#(Value, State), ParseError) {
  let loc = current_location(state)
  case state.chars {
    [] -> Error(ParseError(loc, UnexpectedEndOfInput))
    ["n", "u", "l", "l", ..rest] -> {
      let s1 = advance_char(state, "n", ["u", "l", "l", ..rest])
      let s2 = advance_char(s1, "u", ["l", "l", ..rest])
      let s3 = advance_char(s2, "l", ["l", ..rest])
      let s4 = advance_char(s3, "l", rest)
      Ok(#(value.Null, s4))
    }
    ["t", "r", "u", "e", ..rest] -> {
      let s1 = advance_char(state, "t", ["r", "u", "e", ..rest])
      let s2 = advance_char(s1, "r", ["u", "e", ..rest])
      let s3 = advance_char(s2, "u", ["e", ..rest])
      let s4 = advance_char(s3, "e", rest)
      Ok(#(value.Bool(True), s4))
    }
    ["f", "a", "l", "s", "e", ..rest] -> {
      let s1 = advance_char(state, "f", ["a", "l", "s", "e", ..rest])
      let s2 = advance_char(s1, "a", ["l", "s", "e", ..rest])
      let s3 = advance_char(s2, "l", ["s", "e", ..rest])
      let s4 = advance_char(s3, "s", ["e", ..rest])
      let s5 = advance_char(s4, "e", rest)
      Ok(#(value.Bool(False), s5))
    }
    ["\"", ..] -> parse_string_literal(state)
    ["[", ..] -> parse_array_literal(state)
    ["{", ..] -> parse_object_literal(state)
    ["-", ..]
    | ["0", ..]
    | ["1", ..]
    | ["2", ..]
    | ["3", ..]
    | ["4", ..]
    | ["5", ..]
    | ["6", ..]
    | ["7", ..]
    | ["8", ..]
    | ["9", ..] -> parse_number_literal(state)
    [ch, ..] -> Error(ParseError(loc, UnexpectedByte(ch)))
  }
}

fn parse_number_literal(state: State) -> Result(#(Value, State), ParseError) {
  let loc = current_location(state)
  let #(token_chars, state_after) = scan_number_chars(state, [])
  let token = string.concat(list.reverse(token_chars))
  let ParserLimits(_, _, num_limits) = state.limits
  case number.parse_number(num_limits, token) {
    Error(err) -> Error(ParseError(loc, InvalidNumberToken(err)))
    Ok(num) -> Ok(#(value.Number(num), state_after))
  }
}

fn scan_number_chars(
  state: State,
  acc: List(String),
) -> #(List(String), State) {
  case state.chars {
    [ch, ..rest]
      if ch == "0"
      || ch == "1"
      || ch == "2"
      || ch == "3"
      || ch == "4"
      || ch == "5"
      || ch == "6"
      || ch == "7"
      || ch == "8"
      || ch == "9"
      || ch == "-"
      || ch == "+"
      || ch == "."
      || ch == "e"
      || ch == "E"
    -> scan_number_chars(advance_char(state, ch, rest), [ch, ..acc])
    _ -> #(acc, state)
  }
}

fn parse_string_literal(state: State) -> Result(#(Value, State), ParseError) {
  let loc = current_location(state)
  case state.chars {
    ["\"", ..rest] -> {
      let state_in_str = advance_char(state, "\"", rest)
      case scan_string_contents(state_in_str, loc, []) {
        Error(err) -> Error(err)
        Ok(#(content, state_after_quote)) ->
          Ok(#(value.String(content), state_after_quote))
      }
    }
    _ -> Error(ParseError(loc, UnexpectedByte("expected \"")))
  }
}

fn scan_string_contents(
  state: State,
  start_loc: Location,
  acc: List(String),
) -> Result(#(String, State), ParseError) {
  let loc = current_location(state)
  case state.chars {
    [] -> Error(ParseError(start_loc, UnterminatedString))
    ["\"", ..rest] -> {
      let state_after = advance_char(state, "\"", rest)
      Ok(#(string.concat(list.reverse(acc)), state_after))
    }
    ["\\", ..rest] -> {
      let esc_loc = loc
      let state_esc = advance_char(state, "\\", rest)
      case state_esc.chars {
        [] -> Error(ParseError(start_loc, UnterminatedString))
        ["\"", ..r] ->
          scan_string_contents(advance_char(state_esc, "\"", r), start_loc, [
            "\"",
            ..acc
          ])
        ["\\", ..r] ->
          scan_string_contents(advance_char(state_esc, "\\", r), start_loc, [
            "\\",
            ..acc
          ])
        ["/", ..r] ->
          scan_string_contents(advance_char(state_esc, "/", r), start_loc, [
            "/",
            ..acc
          ])
        ["b", ..r] ->
          scan_string_contents(advance_char(state_esc, "b", r), start_loc, [
            "\u{0008}",
            ..acc
          ])
        ["f", ..r] ->
          scan_string_contents(advance_char(state_esc, "f", r), start_loc, [
            "\u{000C}",
            ..acc
          ])
        ["n", ..r] ->
          scan_string_contents(advance_char(state_esc, "n", r), start_loc, [
            "\n",
            ..acc
          ])
        ["r", ..r] ->
          scan_string_contents(advance_char(state_esc, "r", r), start_loc, [
            "\r",
            ..acc
          ])
        ["t", ..r] ->
          scan_string_contents(advance_char(state_esc, "t", r), start_loc, [
            "\t",
            ..acc
          ])
        ["u", ..r] ->
          case parse_unicode_escape(advance_char(state_esc, "u", r), esc_loc) {
            Error(err) -> Error(err)
            Ok(#(decoded_char, state_after_unicode)) ->
              scan_string_contents(state_after_unicode, start_loc, [
                decoded_char,
                ..acc
              ])
          }
        [_invalid, ..] -> Error(ParseError(esc_loc, InvalidEscapeSequence))
      }
    }
    [ch, ..rest] ->
      case is_control_char(ch) {
        True -> Error(ParseError(loc, UnexpectedByte(ch)))
        False ->
          scan_string_contents(advance_char(state, ch, rest), start_loc, [
            ch,
            ..acc
          ])
      }
  }
}

fn is_control_char(ch: String) -> Bool {
  case ch {
    "\r\n"
    | "\u{0000}"
    | "\u{0001}"
    | "\u{0002}"
    | "\u{0003}"
    | "\u{0004}"
    | "\u{0005}"
    | "\u{0006}"
    | "\u{0007}"
    | "\u{0008}"
    | "\t"
    | "\n"
    | "\u{000B}"
    | "\u{000C}"
    | "\r"
    | "\u{000E}"
    | "\u{000F}"
    | "\u{0010}"
    | "\u{0011}"
    | "\u{0012}"
    | "\u{0013}"
    | "\u{0014}"
    | "\u{0015}"
    | "\u{0016}"
    | "\u{0017}"
    | "\u{0018}"
    | "\u{0019}"
    | "\u{001A}"
    | "\u{001B}"
    | "\u{001C}"
    | "\u{001D}"
    | "\u{001E}"
    | "\u{001F}" -> True
    _ -> False
  }
}

fn parse_unicode_escape(
  state: State,
  esc_loc: Location,
) -> Result(#(String, State), ParseError) {
  case parse_hex4(state) {
    Error(Nil) -> Error(ParseError(esc_loc, InvalidUnicodeEscape))
    Ok(#(code1, s1)) ->
      case code1 >= 0xD800 && code1 <= 0xDBFF {
        False ->
          case string.utf_codepoint(code1) {
            Error(Nil) -> Error(ParseError(esc_loc, InvalidUnicodeEscape))
            Ok(cp) -> Ok(#(string.from_utf_codepoints([cp]), s1))
          }
        True ->
          // High surrogate: expect \uDC00..\uDFFF
          case s1.chars {
            ["\\", "u", ..r] -> {
              let s_esc =
                advance_char(advance_char(s1, "\\", ["u", ..r]), "u", r)
              case parse_hex4(s_esc) {
                Error(Nil) -> Error(ParseError(esc_loc, InvalidUnicodeEscape))
                Ok(#(code2, s2)) ->
                  case code2 >= 0xDC00 && code2 <= 0xDFFF {
                    False -> Error(ParseError(esc_loc, InvalidUnicodeEscape))
                    True -> {
                      let full_codepoint =
                        0x10000 + { code1 - 0xD800 } * 1024 + { code2 - 0xDC00 }
                      case string.utf_codepoint(full_codepoint) {
                        Error(Nil) ->
                          Error(ParseError(esc_loc, InvalidUnicodeEscape))
                        Ok(cp) -> Ok(#(string.from_utf_codepoints([cp]), s2))
                      }
                    }
                  }
              }
            }
            _ -> Error(ParseError(esc_loc, InvalidUnicodeEscape))
          }
      }
  }
}

fn parse_hex4(state: State) -> Result(#(Int, State), Nil) {
  case state.chars {
    [c1, c2, c3, c4, ..rest] ->
      case hex_val(c1), hex_val(c2), hex_val(c3), hex_val(c4) {
        Ok(v1), Ok(v2), Ok(v3), Ok(v4) -> {
          let code = v1 * 4096 + v2 * 256 + v3 * 16 + v4
          let s1 = advance_char(state, c1, [c2, c3, c4, ..rest])
          let s2 = advance_char(s1, c2, [c3, c4, ..rest])
          let s3 = advance_char(s2, c3, [c4, ..rest])
          let s4 = advance_char(s3, c4, rest)
          Ok(#(code, s4))
        }
        _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn hex_val(c: String) -> Result(Int, Nil) {
  case c {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    "a" | "A" -> Ok(10)
    "b" | "B" -> Ok(11)
    "c" | "C" -> Ok(12)
    "d" | "D" -> Ok(13)
    "e" | "E" -> Ok(14)
    "f" | "F" -> Ok(15)
    _ -> Error(Nil)
  }
}

fn parse_array_literal(state: State) -> Result(#(Value, State), ParseError) {
  let loc = current_location(state)
  let ParserLimits(_, max_depth, _) = state.limits
  case state.depth + 1 > max_depth {
    True -> Error(ParseError(loc, DepthLimitExceeded(max_depth)))
    False ->
      case state.chars {
        ["[", ..rest] -> {
          let state_in_arr =
            State(..advance_char(state, "[", rest), depth: state.depth + 1)
          let state_ws = skip_whitespace(state_in_arr)
          case state_ws.chars {
            [] ->
              Error(ParseError(current_location(state_ws), UnexpectedEndOfInput))
            ["]", ..r] -> {
              let state_after =
                State(..advance_char(state_ws, "]", r), depth: state.depth)
              Ok(#(value.Array([]), state_after))
            }
            _ -> parse_array_elements(state_ws, [])
          }
        }
        _ -> Error(ParseError(loc, UnexpectedByte("expected [")))
      }
  }
}

fn parse_array_elements(
  state: State,
  acc: List(Value),
) -> Result(#(Value, State), ParseError) {
  case parse_any_value(state) {
    Error(err) -> Error(err)
    Ok(#(elem, state_after_elem)) -> {
      let state_ws = skip_whitespace(state_after_elem)
      case state_ws.chars {
        [] ->
          Error(ParseError(current_location(state_ws), UnexpectedEndOfInput))
        [",", ..rest] -> {
          let state_after_comma =
            skip_whitespace(advance_char(state_ws, ",", rest))
          case state_after_comma.chars {
            ["]", ..] ->
              Error(ParseError(
                current_location(state_after_comma),
                UnexpectedByte("]"),
              ))
            _ -> parse_array_elements(state_after_comma, [elem, ..acc])
          }
        }
        ["]", ..rest] -> {
          let state_after =
            State(..advance_char(state_ws, "]", rest), depth: state.depth - 1)
          Ok(#(value.Array(list.reverse([elem, ..acc])), state_after))
        }
        [ch, ..] ->
          Error(ParseError(current_location(state_ws), UnexpectedByte(ch)))
      }
    }
  }
}

fn parse_object_literal(state: State) -> Result(#(Value, State), ParseError) {
  let loc = current_location(state)
  let ParserLimits(_, max_depth, _) = state.limits
  case state.depth + 1 > max_depth {
    True -> Error(ParseError(loc, DepthLimitExceeded(max_depth)))
    False ->
      case state.chars {
        ["{", ..rest] -> {
          let state_in_obj =
            State(..advance_char(state, "{", rest), depth: state.depth + 1)
          let state_ws = skip_whitespace(state_in_obj)
          case state_ws.chars {
            [] ->
              Error(ParseError(current_location(state_ws), UnexpectedEndOfInput))
            ["}", ..r] -> {
              let state_after =
                State(..advance_char(state_ws, "}", r), depth: state.depth)
              Ok(#(value.Object([]), state_after))
            }
            _ -> parse_object_members(state_ws, dict.new(), [])
          }
        }
        _ -> Error(ParseError(loc, UnexpectedByte("expected {")))
      }
  }
}

fn parse_object_members(
  state: State,
  seen_keys: dict.Dict(String, Nil),
  acc: List(#(String, Value)),
) -> Result(#(Value, State), ParseError) {
  let key_loc = current_location(state)
  case state.chars {
    ["\"", ..] ->
      case parse_string_literal(state) {
        Error(err) -> Error(err)
        Ok(#(value.String(key), state_after_key)) ->
          case dict.has_key(seen_keys, key) {
            True -> Error(ParseError(key_loc, DuplicateObjectKey(key)))
            False -> {
              let state_ws = skip_whitespace(state_after_key)
              case state_ws.chars {
                [":", ..rest] -> {
                  let state_after_colon =
                    skip_whitespace(advance_char(state_ws, ":", rest))
                  case parse_any_value(state_after_colon) {
                    Error(err) -> Error(err)
                    Ok(#(val, state_after_val)) -> {
                      let state_delim = skip_whitespace(state_after_val)
                      case state_delim.chars {
                        [] ->
                          Error(ParseError(
                            current_location(state_delim),
                            UnexpectedEndOfInput,
                          ))
                        [",", ..r] -> {
                          let state_after_comma =
                            skip_whitespace(advance_char(state_delim, ",", r))
                          case state_after_comma.chars {
                            ["}", ..] ->
                              Error(ParseError(
                                current_location(state_after_comma),
                                UnexpectedByte("}"),
                              ))
                            _ ->
                              parse_object_members(
                                state_after_comma,
                                dict.insert(seen_keys, key, Nil),
                                [#(key, val), ..acc],
                              )
                          }
                        }
                        ["}", ..r] -> {
                          let state_after =
                            State(
                              ..advance_char(state_delim, "}", r),
                              depth: state.depth - 1,
                            )
                          Ok(#(
                            value.Object(list.reverse([#(key, val), ..acc])),
                            state_after,
                          ))
                        }
                        [ch, ..] ->
                          Error(ParseError(
                            current_location(state_delim),
                            UnexpectedByte(ch),
                          ))
                      }
                    }
                  }
                }
                [ch, ..] ->
                  Error(ParseError(
                    current_location(state_ws),
                    UnexpectedByte(ch),
                  ))
                [] ->
                  Error(ParseError(
                    current_location(state_ws),
                    UnexpectedEndOfInput,
                  ))
              }
            }
          }
        _ -> Error(ParseError(key_loc, UnexpectedByte("expected string key")))
      }
    [ch, ..] -> Error(ParseError(key_loc, UnexpectedByte(ch)))
    [] -> Error(ParseError(key_loc, UnexpectedEndOfInput))
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
