import json/blueprint/document.{type DocumentError}
import json/blueprint/internal/parser_core
import json/blueprint/number.{type NumberError, type NumberLimits}
import json/blueprint/parser_limits
import json/blueprint/runtime.{type RuntimeContract}
import json/blueprint/value.{type Value}

pub type ParserLimits =
  parser_limits.ParserLimits

pub type LimitsError {
  MaxBytesMustBePositive
  MaxDepthMustBePositive
}

pub fn parser_limits(
  max_bytes: Int,
  max_depth: Int,
  number_limits: NumberLimits,
) -> Result(ParserLimits, LimitsError) {
  case parser_limits.new(max_bytes, max_depth, number_limits) {
    Error(parser_limits.MaxBytesMustBePositive) -> Error(MaxBytesMustBePositive)
    Error(parser_limits.MaxDepthMustBePositive) -> Error(MaxDepthMustBePositive)
    Ok(limits) -> Ok(limits)
  }
}

pub fn default_limits() -> ParserLimits {
  parser_limits.default()
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

pub type AdmissionError {
  ParseAdmissionError(ParseError)
  DocumentAdmissionError(DocumentError)
}

pub fn parse_value(
  limits: ParserLimits,
  bytes: BitArray,
) -> Result(Value, ParseError) {
  case parser_core.parse_value(limits, bytes) {
    Ok(parsed) -> Ok(parsed)
    Error(error) -> Error(translate_parse_error(error))
  }
}

pub fn parse_value_from_string(
  limits: ParserLimits,
  source: String,
) -> Result(Value, ParseError) {
  case parser_core.parse_value_from_string(limits, source) {
    Ok(parsed) -> Ok(parsed)
    Error(error) -> Error(translate_parse_error(error))
  }
}

pub fn parse_schema_document(
  limits: ParserLimits,
  bytes: BitArray,
) -> Result(RuntimeContract, AdmissionError) {
  case parse_value(limits, bytes) {
    Error(parse_error) -> Error(ParseAdmissionError(parse_error))
    Ok(parsed) ->
      case document.load(parsed) {
        Error(document_error) -> Error(DocumentAdmissionError(document_error))
        Ok(contract) -> Ok(contract)
      }
  }
}

pub fn parse_schema_document_from_string(
  limits: ParserLimits,
  source: String,
) -> Result(RuntimeContract, AdmissionError) {
  case parse_value_from_string(limits, source) {
    Error(parse_error) -> Error(ParseAdmissionError(parse_error))
    Ok(parsed) ->
      case document.load(parsed) {
        Error(document_error) -> Error(DocumentAdmissionError(document_error))
        Ok(contract) -> Ok(contract)
      }
  }
}

fn translate_parse_error(error: parser_core.ParseError) -> ParseError {
  let parser_core.ParseError(location, kind) = error
  let parser_core.Location(byte_offset, line, column) = location
  ParseError(
    Location(byte_offset, line, column),
    translate_parse_error_kind(kind),
  )
}

fn translate_parse_error_kind(
  kind: parser_core.ParseErrorKind,
) -> ParseErrorKind {
  case kind {
    parser_core.UnexpectedByte(byte) -> UnexpectedByte(byte)
    parser_core.UnexpectedEndOfInput -> UnexpectedEndOfInput
    parser_core.InvalidUtf8 -> InvalidUtf8
    parser_core.ByteLimitExceeded(max) -> ByteLimitExceeded(max)
    parser_core.DepthLimitExceeded(max) -> DepthLimitExceeded(max)
    parser_core.InvalidNumberToken(error) -> InvalidNumberToken(error)
    parser_core.DuplicateObjectKey(key) -> DuplicateObjectKey(key)
    parser_core.UnterminatedString -> UnterminatedString
    parser_core.InvalidEscapeSequence -> InvalidEscapeSequence
    parser_core.InvalidUnicodeEscape -> InvalidUnicodeEscape
    parser_core.TrailingContent -> TrailingContent
  }
}
