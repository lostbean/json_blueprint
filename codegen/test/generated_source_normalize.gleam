import gleam/list
import gleam/string
import gleeunit/should

/// Removes formatting whitespace and Gleam formatter-inserted optional
/// trailing commas while preserving strings, comments, and all other tokens.
pub fn normalize(source: String) -> String {
  normalize_characters(string.to_graphemes(source), Code, False, "", [])
}

type Mode {
  Code
  StringLiteral
  LineComment
}

fn normalize_characters(
  characters: List(String),
  mode: Mode,
  pending_space: Bool,
  previous_character: String,
  acc: List(String),
) -> String {
  case mode, characters {
    _, [] -> string.join(list.reverse(acc), "")
    StringLiteral, ["\\", escaped, ..rest] ->
      normalize_characters(rest, StringLiteral, False, "", [
        escaped,
        "\\",
        ..acc
      ])
    StringLiteral, ["\"", ..rest] ->
      normalize_characters(rest, Code, False, "\"", ["\"", ..acc])
    StringLiteral, [character, ..rest] ->
      normalize_characters(rest, StringLiteral, False, "", [character, ..acc])
    LineComment, ["\r", "\n", ..rest] ->
      normalize_characters(rest, Code, False, "", ["\n", "\r", ..acc])
    LineComment, ["\n", ..rest] ->
      normalize_characters(rest, Code, False, "", ["\n", ..acc])
    LineComment, ["\r", ..rest] ->
      normalize_characters(rest, Code, False, "", ["\r", ..acc])
    LineComment, [character, ..rest] ->
      normalize_characters(rest, LineComment, False, "", [character, ..acc])
    Code, ["/", "/", ..rest] ->
      normalize_characters(rest, LineComment, False, "", ["/", "/", ..acc])
    Code, [",", ..rest] ->
      case comma_precedes_closing_delimiter(rest) {
        True -> normalize_characters(rest, Code, False, ",", acc)
        False -> normalize_characters(rest, Code, False, ",", [",", ..acc])
      }
    Code, ["\"", ..rest] ->
      normalize_characters(rest, StringLiteral, False, "", ["\"", ..acc])
    Code, [character, ..rest] -> {
      case is_whitespace(character) {
        True -> normalize_characters(rest, Code, True, previous_character, acc)
        False -> {
          let next_acc = case
            pending_space && requires_separator(previous_character, character)
          {
            True -> [character, " ", ..acc]
            False -> [character, ..acc]
          }
          normalize_characters(rest, Code, False, character, next_acc)
        }
      }
    }
  }
}

fn comma_precedes_closing_delimiter(characters: List(String)) -> Bool {
  case characters {
    [")", ..] -> True
    ["]", ..] -> True
    ["}", ..] -> True
    [character, ..rest] ->
      case is_whitespace(character) {
        True -> comma_precedes_closing_delimiter(rest)
        False -> False
      }
    [] -> False
  }
}

fn is_whitespace(character: String) -> Bool {
  character == " "
  || character == "\t"
  || character == "\n"
  || character == "\r"
}

fn is_word_character(character: String) -> Bool {
  case string.to_utf_codepoints(character) {
    [codepoint] -> {
      let value = string.utf_codepoint_to_int(codepoint)
      character == "_"
      || value >= 97
      && value <= 122
      || value >= 65
      && value <= 90
      || value >= 48
      && value <= 57
    }
    _ -> False
  }
}

fn requires_separator(previous: String, current: String) -> Bool {
  is_word_character(previous)
  && is_word_character(current)
  || is_operator_character(previous)
  && is_operator_character(current)
}

fn is_operator_character(character: String) -> Bool {
  string.byte_size(character) == 1
  && {
    character == "+"
    || character == "-"
    || character == "*"
    || character == "/"
    || character == "="
    || character == "<"
    || character == ">"
    || character == "&"
    || character == "|"
    || character == "^"
    || character == "%"
    || character == "!"
    || character == "~"
    || character == "?"
    || character == "."
  }
}

pub fn normalization_preserves_string_contents_and_escapes_test() {
  let escaped = "\"a  b\\\"c\\\\d\""
  normalize(escaped) |> should.equal(escaped)
  normalize("\"a  b\"") |> should.not_equal("\"a b\"")
  normalize("\"comma , and close ]\"")
  |> should.equal("\"comma , and close ]\"")
}

pub fn normalization_preserves_comments_test() {
  let source = "// keep  comment spacing\npub fn value() {\n  1\n}"
  normalize(source)
  |> should.equal("// keep  comment spacing\npub fn value(){1}")
  normalize("// comma , and close )\nvalue")
  |> should.equal("// comma , and close )\nvalue")
}

pub fn normalization_preserves_identifier_boundaries_test() {
  normalize("pub   fn value() {\n  let answer = 42\n  answer\n}")
  |> should.equal("pub fn value(){let answer=42 answer}")
}

pub fn normalization_preserves_operator_boundaries_test() {
  normalize("a - -b\nx . . y")
  |> should.equal("a- -b x. .y")
}

pub fn normalization_ignores_only_optional_trailing_commas_test() {
  normalize("call(first, second,)\n[list_item,]\n{field: value,}")
  |> should.equal("call(first,second)[list_item]{field:value}")
  normalize("call(first, second)")
  |> should.equal("call(first,second)")
}
