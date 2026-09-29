import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import json/blueprint/internal/parser_core
import json/blueprint/json_text
import json/blueprint/number.{type Number, type NumberError}
import json/blueprint/parser_limits
import json/blueprint/value.{type Value}

pub type EncodeReason {
  EncodeUnknownEnumLabel(String)
  EncodeUnknownEnumValue(String)
  EncodeUnknownTag(String)
  EncodeUnknownProperty(String)
  EncodeWrongTupleLength(expected: Int, actual: Int)
  EncodeInvalidNativeValue(String)
  EncodeIntegerOutsideRange(minimum: Int, maximum: Int, actual: Int)
  EncodeNumberOutsideRange(minimum: Number, maximum: Number, actual: Number)
  CustomEncodeReason(String)
}

pub type EncodeError {
  CannotEncode(reason: EncodeReason)
  EncodeAtField(field: String, inner: EncodeError)
  EncodeAtIndex(index: Int, inner: EncodeError)
}

pub type DecodeReason {
  DecodeExpectedString
  DecodeExpectedInt
  DecodeExpectedNumber
  DecodeExpectedBool
  DecodeExpectedArray
  DecodeExpectedObject
  DecodeUnknownEnumLabel(String)
  DecodeUnknownTag(String)
  DecodeMissingTag
  DecodeMissingTagPayload(String)
  DecodeExpectedTaggedObject
  DecodeMissingProperty(String)
  DecodeUnknownProperty(String)
  DecodeDuplicateProperty(String)
  DecodeWrongTupleLength(expected: Int, actual: Int)
  DecodeInvalidWireValue(String)
  DecodeIntegerOutsideRange(minimum: Int, maximum: Int, actual: Int)
  DecodeNumberOutsideRange(minimum: Number, maximum: Number, actual: Number)
  CustomDecodeReason(String)
}

pub type DecodeError {
  CannotDecode(reason: DecodeReason)
  DecodeAtField(field: String, inner: DecodeError)
  DecodeAtIndex(index: Int, inner: DecodeError)
}

pub type JsonDecodeError {
  BlueprintParserFailure(BlueprintJsonParseFailure)
  NativeJsonFailure(json.DecodeError)
  TypedCodecFailure(DecodeError)
}

pub type BlueprintJsonParseFailure {
  BlueprintJsonParseFailure(
    location: BlueprintJsonLocation,
    reason: BlueprintJsonParseReason,
  )
}

pub type BlueprintJsonLocation {
  BlueprintJsonLocation(byte_offset: Int, line: Int, column: Int)
}

pub type BlueprintJsonParseReason {
  BlueprintUnexpectedByte(String)
  BlueprintUnexpectedEndOfInput
  BlueprintInvalidUtf8
  BlueprintByteLimitExceeded(max: Int)
  BlueprintDepthLimitExceeded(max: Int)
  BlueprintInvalidNumberToken(NumberError)
  BlueprintDuplicateObjectKey(key: String)
  BlueprintUnterminatedString
  BlueprintInvalidEscapeSequence
  BlueprintInvalidUnicodeEscape
  BlueprintTrailingContent
}

pub type SchemaError {
  UnknownSchema
}

pub type Schema {
  DescribedSchema(description: String, inner: Schema)
  StringSchema
  StringEnumSchema(List(String))
  IntSchema
  NumberSchema
  BoolSchema
  PairSchema(Schema, Schema)
  FieldSchema(String, Schema)
  ListSchema(Schema)
  NullableSchema(Schema)
  ObjectSchema(List(PropertySchema))
  TaggedSchema(String, Schema, String, Schema)
  IntegerRangeSchema(Int, Int)
  NumberRangeSchema(Number, Number)
}

pub type PropertySchema {
  PropertySchema(name: String, required: Bool, schema: Schema)
}

pub opaque type Codec(a) {
  Codec(
    encoder: fn(a) -> Result(Value, EncodeError),
    decoder: fn(Value) -> Result(a, DecodeError),
    json_encoder: fn(a) -> Result(String, EncodeError),
    json_decoder: fn(String) -> Result(a, JsonDecodeError),
    schema: Result(Schema, SchemaError),
  )
}

pub fn new(
  encode: fn(a) -> Result(Value, EncodeError),
  decode: fn(Value) -> Result(a, DecodeError),
) -> Codec(a) {
  runtime_codec(encode, decode, Error(UnknownSchema))
}

pub fn from_parts(
  encode: fn(a) -> Result(Value, EncodeError),
  decode: fn(Value) -> Result(a, DecodeError),
  schema: Schema,
) -> Codec(a) {
  runtime_codec(encode, decode, Ok(schema))
}

/// Construct a codec with native JSON text operations. Ordinary decoding uses
/// Blueprint's strict parser; the supplied decoder is available through
/// `decode_json_native` when its native parsing behavior is desired.
pub fn from_json_parts(
  value_encode: fn(a) -> Result(Value, EncodeError),
  value_decode: fn(Value) -> Result(a, DecodeError),
  json_encode: fn(a) -> Result(String, EncodeError),
  json_decode: fn(String) -> Result(a, JsonDecodeError),
  schema: Schema,
) -> Codec(a) {
  Codec(value_encode, value_decode, json_encode, json_decode, Ok(schema))
}

fn runtime_codec(
  value_encode: fn(a) -> Result(Value, EncodeError),
  value_decode: fn(Value) -> Result(a, DecodeError),
  schema: Result(Schema, SchemaError),
) -> Codec(a) {
  Codec(
    value_encode,
    value_decode,
    fn(item) { encode_json_with(value_encode, item) },
    fn(source) {
      decode_json_with(value_decode, parser_limits.default(), source)
    },
    schema,
  )
}

/// Encode JSON text using this codec's backend.
///
/// Runtime codecs render Blueprint Values; native-backed codecs call their
/// supplied JSON encoder directly.
pub fn encode_json(codec: Codec(a), item: a) -> Result(String, EncodeError) {
  codec.json_encoder(item)
}

/// Decode JSON text with Blueprint's strict parser.
///
/// All codecs use Blueprint's parser, including duplicate-key rejection and
/// exact number admission.
pub fn decode_json(
  codec: Codec(a),
  source: String,
) -> Result(a, JsonDecodeError) {
  decode_json_with_limits(codec, parser_limits.default(), source)
}

/// Decode using caller-supplied parser limits. `parser.ParserLimits` is an
/// alias of the shared limit type accepted here.
pub fn decode_json_with_limits(
  codec: Codec(a),
  limits: parser_limits.ParserLimits,
  source: String,
) -> Result(a, JsonDecodeError) {
  decode_json_with(codec.decoder, limits, source)
}

/// Use a codec's native JSON parser when its distinct performance and parser
/// semantics are explicitly required. Generated codecs use `gleam/json` here.
pub fn decode_json_native(
  codec: Codec(a),
  source: String,
) -> Result(a, JsonDecodeError) {
  codec.json_decoder(source)
}

fn encode_json_with(
  value_encode: fn(a) -> Result(Value, EncodeError),
  item: a,
) -> Result(String, EncodeError) {
  case value_encode(item) {
    Ok(encoded) -> Ok(json_text.render_value(encoded))
    Error(error) -> Error(error)
  }
}

fn decode_json_with(
  value_decode: fn(Value) -> Result(a, DecodeError),
  limits: parser_limits.ParserLimits,
  source: String,
) -> Result(a, JsonDecodeError) {
  case parser_core.parse_value_from_string(limits, source) {
    Error(error) ->
      Error(BlueprintParserFailure(translate_json_parse_error(error)))
    Ok(parsed) ->
      case value_decode(parsed) {
        Ok(item) -> Ok(item)
        Error(error) -> Error(TypedCodecFailure(error))
      }
  }
}

fn translate_json_parse_error(
  error: parser_core.ParseError,
) -> BlueprintJsonParseFailure {
  let parser_core.ParseError(location, reason) = error
  let parser_core.Location(byte_offset, line, column) = location
  BlueprintJsonParseFailure(
    BlueprintJsonLocation(byte_offset, line, column),
    translate_json_parse_reason(reason),
  )
}

fn translate_json_parse_reason(
  reason: parser_core.ParseErrorKind,
) -> BlueprintJsonParseReason {
  case reason {
    parser_core.UnexpectedByte(byte) -> BlueprintUnexpectedByte(byte)
    parser_core.UnexpectedEndOfInput -> BlueprintUnexpectedEndOfInput
    parser_core.InvalidUtf8 -> BlueprintInvalidUtf8
    parser_core.ByteLimitExceeded(max) -> BlueprintByteLimitExceeded(max)
    parser_core.DepthLimitExceeded(max) -> BlueprintDepthLimitExceeded(max)
    parser_core.InvalidNumberToken(error) -> BlueprintInvalidNumberToken(error)
    parser_core.DuplicateObjectKey(key) -> BlueprintDuplicateObjectKey(key)
    parser_core.UnterminatedString -> BlueprintUnterminatedString
    parser_core.InvalidEscapeSequence -> BlueprintInvalidEscapeSequence
    parser_core.InvalidUnicodeEscape -> BlueprintInvalidUnicodeEscape
    parser_core.TrailingContent -> BlueprintTrailingContent
  }
}

pub fn encode(codec: Codec(a), item: a) -> Result(Value, EncodeError) {
  codec.encoder(item)
}

pub fn decode(codec: Codec(a), item: Value) -> Result(a, DecodeError) {
  codec.decoder(item)
}

pub fn schema(codec: Codec(a)) -> Result(Schema, SchemaError) {
  codec.schema
}

/// Add a JSON Schema description without changing encoding or decoding.
/// A description applied twice at the same node uses the latest text.
pub fn describe(codec: Codec(a), description: String) -> Codec(a) {
  let described = case codec.schema {
    Ok(DescribedSchema(_, inner)) -> Ok(DescribedSchema(description, inner))
    Ok(schema) -> Ok(DescribedSchema(description, schema))
    Error(error) -> Error(error)
  }
  Codec(..codec, schema: described)
}

/// Render a JSON decoding error for human-readable feedback.
///
/// Input values and custom reason text are omitted. Paths can still contain
/// names supplied by a custom decoder, so callers decide whether to expose the
/// result to an external audience.
pub fn render_json_decode_error(error: JsonDecodeError) -> String {
  case error {
    BlueprintParserFailure(BlueprintJsonParseFailure(location, reason)) ->
      "invalid JSON at line "
      <> int.to_string(location.line)
      <> ", column "
      <> int.to_string(location.column)
      <> ": "
      <> render_parse_reason(reason)
    NativeJsonFailure(_) -> "invalid JSON"
    TypedCodecFailure(error) -> render_decode_error_at(error, "$")
  }
}

fn render_decode_error_at(error: DecodeError, path: String) -> String {
  case error {
    DecodeAtField(_, CannotDecode(DecodeUnknownProperty(_))) ->
      path <> ": unknown property"
    DecodeAtField(_, CannotDecode(DecodeDuplicateProperty(_))) ->
      path <> ": duplicate property"
    DecodeAtField(field, inner) ->
      render_decode_error_at(
        inner,
        path <> "[" <> json_text.render_value(value.String(field)) <> "]",
      )
    DecodeAtIndex(index, inner) ->
      render_decode_error_at(inner, path <> "[" <> int.to_string(index) <> "]")
    CannotDecode(reason) -> path <> ": " <> render_decode_reason(reason)
  }
}

fn render_decode_reason(reason: DecodeReason) -> String {
  case reason {
    DecodeExpectedString -> "expected a string"
    DecodeExpectedInt -> "expected an integer"
    DecodeExpectedNumber -> "expected a number"
    DecodeExpectedBool -> "expected a boolean"
    DecodeExpectedArray -> "expected an array"
    DecodeExpectedObject -> "expected an object"
    DecodeUnknownEnumLabel(_) -> "unknown enum label"
    DecodeUnknownTag(_) -> "unknown tag"
    DecodeMissingTag -> "missing tag"
    DecodeMissingTagPayload(_) -> "missing tag payload"
    DecodeExpectedTaggedObject -> "expected a tagged object"
    DecodeMissingProperty(_) -> "missing required property"
    DecodeUnknownProperty(_) -> "unknown property"
    DecodeDuplicateProperty(_) -> "duplicate property"
    DecodeWrongTupleLength(expected, _) ->
      "expected exactly " <> int.to_string(expected) <> " items"
    DecodeInvalidWireValue(_) -> "invalid wire value"
    DecodeIntegerOutsideRange(minimum, maximum, _) ->
      "integer outside range "
      <> int.to_string(minimum)
      <> " to "
      <> int.to_string(maximum)
    DecodeNumberOutsideRange(minimum, maximum, _) ->
      "number outside range "
      <> number.number_text(minimum)
      <> " to "
      <> number.number_text(maximum)
    CustomDecodeReason(_) -> "custom validation failed"
  }
}

fn render_parse_reason(reason: BlueprintJsonParseReason) -> String {
  case reason {
    BlueprintUnexpectedByte(_) -> "unexpected byte"
    BlueprintUnexpectedEndOfInput -> "unexpected end of input"
    BlueprintInvalidUtf8 -> "invalid UTF-8"
    BlueprintByteLimitExceeded(max) ->
      "byte limit exceeded (" <> int.to_string(max) <> ")"
    BlueprintDepthLimitExceeded(max) ->
      "depth limit exceeded (" <> int.to_string(max) <> ")"
    BlueprintInvalidNumberToken(_) -> "invalid number token"
    BlueprintDuplicateObjectKey(_) -> "duplicate object key"
    BlueprintUnterminatedString -> "unterminated string"
    BlueprintInvalidEscapeSequence -> "invalid escape sequence"
    BlueprintInvalidUnicodeEscape -> "invalid Unicode escape"
    BlueprintTrailingContent -> "trailing content"
  }
}

/// Render the codec's complete Draft 2020-12 schema document as exact JSON.
///
/// Codecs without a known schema return `UnknownSchema`.
pub fn schema_json(codec: Codec(a)) -> Result(String, SchemaError) {
  case schema(codec) {
    Ok(description) ->
      Ok(description |> schema_document |> json_text.render_value)
    Error(error) -> Error(error)
  }
}

// These operations are the allocation-light targets used by generated codecs.
// They mirror the corresponding runtime combinators but accept functions rather
// than already-constructed Codec values.
pub fn encode_string_value(item: String) -> Result(Value, EncodeError) {
  Ok(value.String(item))
}

pub fn decode_string_value(raw: Value) -> Result(String, DecodeError) {
  case raw {
    value.String(item) -> Ok(item)
    _ -> Error(CannotDecode(DecodeExpectedString))
  }
}

pub fn encode_int_value(item: Int) -> Result(Value, EncodeError) {
  case native_integer_number(item) {
    Ok(num) -> Ok(value.Number(num))
    Error(error) -> Error(error)
  }
}

pub fn encode_native_int(item: Int) -> Result(json.Json, EncodeError) {
  case native_integer_number(item) {
    Ok(_) -> Ok(json.int(item))
    Error(error) -> Error(error)
  }
}

fn native_integer_number(item: Int) -> Result(Number, EncodeError) {
  case number.from_int(item) {
    Ok(num) -> Ok(num)
    Error(number.NonFiniteInteger) ->
      Error(CannotEncode(EncodeInvalidNativeValue("NonFiniteInteger")))
    Error(number.NonIntegerValue) ->
      Error(CannotEncode(EncodeInvalidNativeValue("NonIntegerValue")))
    Error(number.UnsafeNativeInteger) ->
      Error(CannotEncode(EncodeInvalidNativeValue("UnsafeNativeInteger")))
  }
}

pub fn decode_int_value(raw: Value) -> Result(Int, DecodeError) {
  case raw {
    value.Number(num) -> {
      let assert Ok(limit) = number.integer_projection_limit(24)
      case number.to_int_exact(num, limit) {
        Ok(item) -> Ok(item)
        Error(_) -> Error(CannotDecode(DecodeExpectedInt))
      }
    }
    _ -> Error(CannotDecode(DecodeExpectedInt))
  }
}

pub fn encode_number_value(item: Number) -> Result(Value, EncodeError) {
  Ok(value.Number(item))
}

pub fn decode_number_value(raw: Value) -> Result(Number, DecodeError) {
  case raw {
    value.Number(item) -> Ok(item)
    _ -> Error(CannotDecode(DecodeExpectedNumber))
  }
}

pub fn encode_bool_value(item: Bool) -> Result(Value, EncodeError) {
  Ok(value.Bool(item))
}

pub fn decode_bool_value(raw: Value) -> Result(Bool, DecodeError) {
  case raw {
    value.Bool(item) -> Ok(item)
    _ -> Error(CannotDecode(DecodeExpectedBool))
  }
}

pub fn encode_integer_between_value(
  min: Int,
  max: Int,
  item: Int,
) -> Result(Value, EncodeError) {
  case item >= min && item <= max {
    True ->
      case number.from_int(item) {
        Ok(num) -> Ok(value.Number(num))
        Error(_) ->
          Error(CannotEncode(EncodeIntegerOutsideRange(min, max, item)))
      }
    False -> Error(CannotEncode(EncodeIntegerOutsideRange(min, max, item)))
  }
}

pub fn encode_native_integer_between(
  min: Int,
  max: Int,
  item: Int,
) -> Result(json.Json, EncodeError) {
  case item >= min && item <= max {
    True ->
      case native_integer_number(item) {
        Ok(_) -> Ok(json.int(item))
        Error(_) ->
          Error(CannotEncode(EncodeIntegerOutsideRange(min, max, item)))
      }
    False -> Error(CannotEncode(EncodeIntegerOutsideRange(min, max, item)))
  }
}

pub fn decode_integer_between_value(
  min: Int,
  max: Int,
  raw: Value,
) -> Result(Int, DecodeError) {
  case raw {
    value.Number(num) -> {
      let limit = number.integer_projection_limit_for_range_value(num, min, max)
      case number.to_int_exact(num, limit) {
        Ok(item) if item >= min && item <= max -> Ok(item)
        Ok(item) ->
          Error(CannotDecode(DecodeIntegerOutsideRange(min, max, item)))
        Error(_) -> Error(CannotDecode(DecodeExpectedInt))
      }
    }
    _ -> Error(CannotDecode(DecodeExpectedInt))
  }
}

pub fn encode_pair_with(
  encode_left: fn(a) -> Result(Value, EncodeError),
  encode_right: fn(b) -> Result(Value, EncodeError),
  pair: #(a, b),
) -> Result(Value, EncodeError) {
  case encode_left(pair.0) {
    Error(error) -> Error(EncodeAtIndex(0, error))
    Ok(left) ->
      case encode_right(pair.1) {
        Error(error) -> Error(EncodeAtIndex(1, error))
        Ok(right) -> Ok(value.Array([left, right]))
      }
  }
}

pub fn decode_pair_with(
  decode_left: fn(Value) -> Result(a, DecodeError),
  decode_right: fn(Value) -> Result(b, DecodeError),
  raw: Value,
) -> Result(#(a, b), DecodeError) {
  case raw {
    value.Array([left, right]) ->
      case decode_left(left) {
        Error(error) -> Error(DecodeAtIndex(0, error))
        Ok(left) ->
          case decode_right(right) {
            Error(error) -> Error(DecodeAtIndex(1, error))
            Ok(right) -> Ok(#(left, right))
          }
      }
    value.Array(items) ->
      Error(CannotDecode(DecodeWrongTupleLength(2, list.length(items))))
    _ -> Error(CannotDecode(DecodeExpectedArray))
  }
}

pub fn encode_list_with(
  encode_item: fn(a) -> Result(Value, EncodeError),
  items: List(a),
) -> Result(Value, EncodeError) {
  case encode_list_values(encode_item, items, 0) {
    Ok(values) -> Ok(value.Array(values))
    Error(error) -> Error(error)
  }
}

fn encode_list_values(
  encode_item: fn(a) -> Result(Value, EncodeError),
  items: List(a),
  index: Int,
) -> Result(List(Value), EncodeError) {
  case items {
    [] -> Ok([])
    [item, ..rest] ->
      case encode_item(item) {
        Error(error) -> Error(EncodeAtIndex(index, error))
        Ok(raw) ->
          case encode_list_values(encode_item, rest, index + 1) {
            Ok(encoded_rest) -> Ok([raw, ..encoded_rest])
            Error(error) -> Error(error)
          }
      }
  }
}

pub fn decode_list_with(
  decode_item: fn(Value) -> Result(a, DecodeError),
  raw: Value,
) -> Result(List(a), DecodeError) {
  case raw {
    value.Array(items) -> decode_list_values(decode_item, items, 0)
    _ -> Error(CannotDecode(DecodeExpectedArray))
  }
}

fn decode_list_values(
  decode_item: fn(Value) -> Result(a, DecodeError),
  items: List(Value),
  index: Int,
) -> Result(List(a), DecodeError) {
  case items {
    [] -> Ok([])
    [item, ..rest] ->
      case decode_item(item) {
        Error(error) -> Error(DecodeAtIndex(index, error))
        Ok(decoded) ->
          case decode_list_values(decode_item, rest, index + 1) {
            Ok(decoded_rest) -> Ok([decoded, ..decoded_rest])
            Error(error) -> Error(error)
          }
      }
  }
}

pub fn encode_nullable_with(
  encode_inner: fn(a) -> Result(Value, EncodeError),
  item: Nullable(a),
) -> Result(Value, EncodeError) {
  case item {
    Null -> Ok(value.Null)
    NonNull(item) ->
      case encode_inner(item) {
        Ok(value.Null) ->
          Error(
            CannotEncode(CustomEncodeReason(
              "NonNull must encode a non-null value",
            )),
          )
        other -> other
      }
  }
}

pub fn decode_nullable_with(
  decode_inner: fn(Value) -> Result(a, DecodeError),
  raw: Value,
) -> Result(Nullable(a), DecodeError) {
  case raw {
    value.Null -> Ok(Null)
    _ ->
      case decode_inner(raw) {
        Ok(item) -> Ok(NonNull(item))
        Error(error) -> Error(error)
      }
  }
}

pub fn encode_required_property_with(
  name: String,
  encode_item: fn(a) -> Result(Value, EncodeError),
  item: a,
) -> Result(List(#(String, Value)), EncodeError) {
  case encode_item(item) {
    Ok(raw) -> Ok([#(name, raw)])
    Error(error) -> Error(EncodeAtField(name, error))
  }
}

pub fn encode_optional_property_with(
  name: String,
  encode_item: fn(a) -> Result(Value, EncodeError),
  item: Optional(a),
) -> Result(List(#(String, Value)), EncodeError) {
  case item {
    Missing -> Ok([])
    Present(item) -> encode_required_property_with(name, encode_item, item)
  }
}

pub fn decode_required_property_with(
  name: String,
  fields: List(#(String, Value)),
  decode_item: fn(Value) -> Result(a, DecodeError),
) -> Result(a, DecodeError) {
  case lookup(fields, name) {
    Missing ->
      Error(DecodeAtField(name, CannotDecode(DecodeMissingProperty(name))))
    Present(raw) ->
      case decode_item(raw) {
        Ok(item) -> Ok(item)
        Error(error) -> Error(DecodeAtField(name, error))
      }
  }
}

pub fn decode_optional_property_with(
  name: String,
  fields: List(#(String, Value)),
  decode_item: fn(Value) -> Result(a, DecodeError),
) -> Result(Optional(a), DecodeError) {
  case lookup(fields, name) {
    Missing -> Ok(Missing)
    Present(raw) ->
      case decode_item(raw) {
        Ok(item) -> Ok(Present(item))
        Error(error) -> Error(DecodeAtField(name, error))
      }
  }
}

pub fn encode_properties_pair_with(
  encode_left: fn(a) -> Result(List(#(String, Value)), EncodeError),
  encode_right: fn(b) -> Result(List(#(String, Value)), EncodeError),
  items: #(a, b),
) -> Result(List(#(String, Value)), EncodeError) {
  case encode_left(items.0) {
    Error(error) -> Error(error)
    Ok(left) ->
      case encode_right(items.1) {
        Error(error) -> Error(error)
        Ok(right) -> Ok(list.append(left, right))
      }
  }
}

pub fn decode_properties_pair_with(
  decode_left: fn(List(#(String, Value))) -> Result(a, DecodeError),
  decode_right: fn(List(#(String, Value))) -> Result(b, DecodeError),
  fields: List(#(String, Value)),
) -> Result(#(a, b), DecodeError) {
  case decode_left(fields) {
    Error(error) -> Error(error)
    Ok(left) ->
      case decode_right(fields) {
        Error(error) -> Error(error)
        Ok(right) -> Ok(#(left, right))
      }
  }
}

pub fn encode_object_with(
  encode_fields: fn(a) -> Result(List(#(String, Value)), EncodeError),
  item: a,
) -> Result(Value, EncodeError) {
  case encode_fields(item) {
    Ok(fields) -> Ok(value.Object(fields))
    Error(error) -> Error(error)
  }
}

pub fn decode_object_with(
  names: List(String),
  decode_fields: fn(List(#(String, Value))) -> Result(a, DecodeError),
  raw: Value,
) -> Result(a, DecodeError) {
  case raw {
    value.Object(fields) ->
      case check_object_keys(fields, names, []) {
        Ok(Nil) -> decode_fields(fields)
        Error(error) -> Error(error)
      }
    _ -> Error(CannotDecode(DecodeExpectedObject))
  }
}

pub fn encode_native_pair_with(
  encode_left: fn(a) -> Result(json.Json, EncodeError),
  encode_right: fn(b) -> Result(json.Json, EncodeError),
  items: #(a, b),
) -> Result(json.Json, EncodeError) {
  case encode_left(items.0) {
    Error(error) -> Error(EncodeAtIndex(0, error))
    Ok(left) ->
      case encode_right(items.1) {
        Error(error) -> Error(EncodeAtIndex(1, error))
        Ok(right) -> Ok(json.preprocessed_array([left, right]))
      }
  }
}

pub fn encode_native_list_with(
  encode_item: fn(a) -> Result(json.Json, EncodeError),
  items: List(a),
) -> Result(json.Json, EncodeError) {
  case encode_native_list_values(encode_item, items, 0, []) {
    Ok(values) -> Ok(json.preprocessed_array(values))
    Error(error) -> Error(error)
  }
}

fn encode_native_list_values(
  encode_item: fn(a) -> Result(json.Json, EncodeError),
  items: List(a),
  index: Int,
  acc: List(json.Json),
) -> Result(List(json.Json), EncodeError) {
  case items {
    [] -> Ok(list.reverse(acc))
    [item, ..rest] ->
      case encode_item(item) {
        Error(error) -> Error(EncodeAtIndex(index, error))
        Ok(encoded) ->
          encode_native_list_values(encode_item, rest, index + 1, [
            encoded,
            ..acc
          ])
      }
  }
}

pub fn encode_native_nullable_with(
  encode_inner: fn(a) -> Result(json.Json, EncodeError),
  item: Nullable(a),
) -> Result(json.Json, EncodeError) {
  case item {
    Null -> Ok(json.null())
    NonNull(item) ->
      case encode_inner(item) {
        Error(error) -> Error(error)
        Ok(encoded) ->
          case encoded == json.null() {
            True ->
              Error(
                CannotEncode(CustomEncodeReason(
                  "NonNull must encode a non-null value",
                )),
              )
            False -> Ok(encoded)
          }
      }
  }
}

pub fn encode_native_required_property_with(
  name: String,
  encode_item: fn(a) -> Result(json.Json, EncodeError),
  item: a,
) -> Result(List(#(String, json.Json)), EncodeError) {
  case encode_item(item) {
    Ok(raw) -> Ok([#(name, raw)])
    Error(error) -> Error(EncodeAtField(name, error))
  }
}

pub fn encode_native_optional_property_with(
  name: String,
  encode_item: fn(a) -> Result(json.Json, EncodeError),
  item: Optional(a),
) -> Result(List(#(String, json.Json)), EncodeError) {
  case item {
    Missing -> Ok([])
    Present(item) ->
      encode_native_required_property_with(name, encode_item, item)
  }
}

pub fn encode_native_properties_pair_with(
  encode_left: fn(a) -> Result(List(#(String, json.Json)), EncodeError),
  encode_right: fn(b) -> Result(List(#(String, json.Json)), EncodeError),
  items: #(a, b),
) -> Result(List(#(String, json.Json)), EncodeError) {
  case encode_left(items.0) {
    Error(error) -> Error(error)
    Ok(left) ->
      case encode_right(items.1) {
        Error(error) -> Error(error)
        Ok(right) -> Ok(list.append(left, right))
      }
  }
}

pub fn encode_native_object_with(
  encode_fields: fn(a) -> Result(List(#(String, json.Json)), EncodeError),
  item: a,
) -> Result(json.Json, EncodeError) {
  case encode_fields(item) {
    Ok(fields) -> Ok(json.object(fields))
    Error(error) -> Error(error)
  }
}

pub fn decode_native_string(raw: Dynamic) -> Result(String, DecodeError) {
  case decode.run(raw, decode.string) {
    Ok(item) -> Ok(item)
    Error(_) -> Error(CannotDecode(DecodeExpectedString))
  }
}

/// Decode a native JSON number using exact integer projection.
///
/// JSON parsers normalize numeric tokens before this function sees them. In
/// particular, JavaScript may round a fractional token to an integer first, so
/// the original lexical fraction cannot always be recovered here.
pub fn decode_native_int(raw: Dynamic) -> Result(Int, DecodeError) {
  case decode.run(raw, decode.int) {
    Ok(item) -> exact_native_int(item)
    Error(_) ->
      case decode.run(raw, decode.float) {
        Ok(item) ->
          case number.from_float_exact(item) {
            Ok(parsed) -> project_native_int(parsed)
            Error(_) -> Error(CannotDecode(DecodeExpectedInt))
          }
        Error(_) -> Error(CannotDecode(DecodeExpectedInt))
      }
  }
}

fn exact_native_int(item: Int) -> Result(Int, DecodeError) {
  case number.from_int(item) {
    Ok(parsed) -> project_native_int(parsed)
    Error(_) -> Error(CannotDecode(DecodeExpectedInt))
  }
}

fn project_native_int(item: Number) -> Result(Int, DecodeError) {
  let assert Ok(limit) = number.integer_projection_limit(24)
  case number.to_int_exact(item, limit) {
    Ok(projected) -> Ok(projected)
    Error(_) -> Error(CannotDecode(DecodeExpectedInt))
  }
}

pub fn decode_native_bool(raw: Dynamic) -> Result(Bool, DecodeError) {
  case decode.run(raw, decode.bool) {
    Ok(item) -> Ok(item)
    Error(_) -> Error(CannotDecode(DecodeExpectedBool))
  }
}

pub fn decode_native_pair_with(
  decode_left: fn(Dynamic) -> Result(a, DecodeError),
  decode_right: fn(Dynamic) -> Result(b, DecodeError),
  raw: Dynamic,
) -> Result(#(a, b), DecodeError) {
  case decode.run(raw, decode.list(of: decode.dynamic)) {
    Error(_) -> Error(CannotDecode(DecodeExpectedArray))
    Ok([left, right]) ->
      case decode_left(left) {
        Error(error) -> Error(DecodeAtIndex(0, error))
        Ok(left) ->
          case decode_right(right) {
            Error(error) -> Error(DecodeAtIndex(1, error))
            Ok(right) -> Ok(#(left, right))
          }
      }
    Ok(items) ->
      Error(CannotDecode(DecodeWrongTupleLength(2, list.length(items))))
  }
}

pub fn decode_native_list_with(
  decode_item: fn(Dynamic) -> Result(a, DecodeError),
  raw: Dynamic,
) -> Result(List(a), DecodeError) {
  case decode.run(raw, decode.list(of: decode.dynamic)) {
    Error(_) -> Error(CannotDecode(DecodeExpectedArray))
    Ok(items) -> decode_native_list_items(decode_item, items, 0, [])
  }
}

fn decode_native_list_items(
  decode_item: fn(Dynamic) -> Result(a, DecodeError),
  items: List(Dynamic),
  index: Int,
  acc: List(a),
) -> Result(List(a), DecodeError) {
  case items {
    [] -> Ok(list.reverse(acc))
    [item, ..rest] ->
      case decode_item(item) {
        Error(error) -> Error(DecodeAtIndex(index, error))
        Ok(decoded) ->
          decode_native_list_items(decode_item, rest, index + 1, [
            decoded,
            ..acc
          ])
      }
  }
}

pub fn decode_native_nullable_with(
  decode_inner: fn(Dynamic) -> Result(a, DecodeError),
  raw: Dynamic,
) -> Result(Nullable(a), DecodeError) {
  case decode.run(raw, decode.optional(decode.dynamic)) {
    Error(_) ->
      Error(CannotDecode(DecodeInvalidWireValue("invalid nullable value")))
    Ok(None) -> Ok(Null)
    Ok(Some(inner)) ->
      case decode_inner(inner) {
        Ok(item) -> Ok(NonNull(item))
        Error(error) -> Error(error)
      }
  }
}

pub fn decode_native_required_property_with(
  name: String,
  fields: dict.Dict(String, Dynamic),
  decode_item: fn(Dynamic) -> Result(a, DecodeError),
) -> Result(a, DecodeError) {
  case dict.get(fields, name) {
    Error(_) ->
      Error(DecodeAtField(name, CannotDecode(DecodeMissingProperty(name))))
    Ok(raw) ->
      case decode_item(raw) {
        Ok(item) -> Ok(item)
        Error(error) -> Error(DecodeAtField(name, error))
      }
  }
}

pub fn decode_native_optional_property_with(
  name: String,
  fields: dict.Dict(String, Dynamic),
  decode_item: fn(Dynamic) -> Result(a, DecodeError),
) -> Result(Optional(a), DecodeError) {
  case dict.get(fields, name) {
    Error(_) -> Ok(Missing)
    Ok(raw) ->
      case decode_item(raw) {
        Ok(item) -> Ok(Present(item))
        Error(error) -> Error(DecodeAtField(name, error))
      }
  }
}

pub fn decode_native_properties_pair_with(
  decode_left: fn(dict.Dict(String, Dynamic)) -> Result(a, DecodeError),
  decode_right: fn(dict.Dict(String, Dynamic)) -> Result(b, DecodeError),
  fields: dict.Dict(String, Dynamic),
) -> Result(#(a, b), DecodeError) {
  case decode_left(fields) {
    Error(error) -> Error(error)
    Ok(left) ->
      case decode_right(fields) {
        Error(error) -> Error(error)
        Ok(right) -> Ok(#(left, right))
      }
  }
}

pub fn decode_native_object_with(
  names: List(String),
  decode_fields: fn(dict.Dict(String, Dynamic)) -> Result(a, DecodeError),
  raw: Dynamic,
) -> Result(a, DecodeError) {
  case decode.run(raw, decode.dict(decode.string, decode.dynamic)) {
    Error(_) -> Error(CannotDecode(DecodeExpectedObject))
    Ok(fields) ->
      case first_unknown_native_property(dict.keys(fields), names) {
        Some(name) -> Error(CannotDecode(DecodeUnknownProperty(name)))
        None -> decode_fields(fields)
      }
  }
}

fn first_unknown_native_property(
  names: List(String),
  allowed: List(String),
) -> Option(String) {
  case names {
    [] -> None
    [name, ..rest] ->
      case list.contains(allowed, name) {
        True -> first_unknown_native_property(rest, allowed)
        False -> Some(name)
      }
  }
}

pub fn encode_mapped_with(
  encode_inner: fn(a) -> Result(Value, EncodeError),
  to_inner: fn(b) -> a,
  item: b,
) -> Result(Value, EncodeError) {
  encode_inner(to_inner(item))
}

pub fn decode_mapped_with(
  decode_inner: fn(Value) -> Result(a, DecodeError),
  from_inner: fn(a) -> b,
  raw: Value,
) -> Result(b, DecodeError) {
  case decode_inner(raw) {
    Ok(item) -> Ok(from_inner(item))
    Error(error) -> Error(error)
  }
}

pub fn imap(codec: Codec(a), from: fn(a) -> b, to: fn(b) -> a) -> Codec(b) {
  let mapped =
    new(fn(value) { encode_mapped_with(codec.encoder, to, value) }, fn(raw) {
      decode_mapped_with(codec.decoder, from, raw)
    })
  Codec(..mapped, schema: codec.schema)
}

/// Map a codec through fallible application conversions in both directions.
/// Conversion failures use the same located errors as the base codec.
pub fn try_imap(
  codec: Codec(a),
  from: fn(a) -> Result(b, DecodeError),
  to: fn(b) -> Result(a, EncodeError),
) -> Codec(b) {
  let mapped =
    new(
      fn(item) {
        case to(item) {
          Ok(inner) -> codec.encoder(inner)
          Error(error) -> Error(error)
        }
      },
      fn(raw) {
        case codec.decoder(raw) {
          Ok(inner) -> from(inner)
          Error(error) -> Error(error)
        }
      },
    )
  Codec(..mapped, schema: codec.schema)
}

pub fn string() -> Codec(String) {
  let codec = new(encode_string_value, decode_string_value)
  Codec(..codec, schema: Ok(StringSchema))
}

pub fn int() -> Codec(Int) {
  let codec = new(encode_int_value, decode_int_value)
  Codec(..codec, schema: Ok(IntSchema))
}

pub fn number() -> Codec(Number) {
  let codec = new(encode_number_value, decode_number_value)
  Codec(..codec, schema: Ok(NumberSchema))
}

pub fn bool() -> Codec(Bool) {
  let codec = new(encode_bool_value, decode_bool_value)
  Codec(..codec, schema: Ok(BoolSchema))
}

pub fn pair(left: Codec(a), right: Codec(b)) -> Codec(#(a, b)) {
  let paired =
    new(
      fn(items) { encode_pair_with(left.encoder, right.encoder, items) },
      fn(raw) { decode_pair_with(left.decoder, right.decoder, raw) },
    )
  let description = case left.schema, right.schema {
    Ok(a), Ok(b) -> Ok(PairSchema(a, b))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  Codec(..paired, schema: description)
}

pub fn list(inner: Codec(a)) -> Codec(List(a)) {
  let codec =
    new(fn(items) { encode_list_with(inner.encoder, items) }, fn(raw) {
      decode_list_with(inner.decoder, raw)
    })
  let description = case inner.schema {
    Ok(schema) -> Ok(ListSchema(schema))
    Error(error) -> Error(error)
  }
  Codec(..codec, schema: description)
}

pub type Nullable(a) {
  Null
  NonNull(a)
}

pub fn nullable(inner: Codec(a)) -> Codec(Nullable(a)) {
  let codec =
    new(fn(item) { encode_nullable_with(inner.encoder, item) }, fn(raw) {
      decode_nullable_with(inner.decoder, raw)
    })
  let description = case inner.schema {
    Ok(schema) -> Ok(NullableSchema(schema))
    Error(error) -> Error(error)
  }
  Codec(..codec, schema: description)
}

pub type Optional(a) {
  Missing
  Present(a)
}

pub type PropertyError {
  DuplicateProperty(String)
}

pub opaque type Properties(a) {
  Properties(
    encode: fn(a) -> Result(List(#(String, Value)), EncodeError),
    decode: fn(List(#(String, Value))) -> Result(a, DecodeError),
    names: List(String),
    schemas: Result(List(PropertySchema), SchemaError),
  )
}

pub fn empty() -> Properties(Nil) {
  Properties(fn(_) { Ok([]) }, fn(_) { Ok(Nil) }, [], Ok([]))
}

pub fn required(name: String, codec: Codec(a)) -> Properties(a) {
  Properties(
    fn(item) { encode_required_property_with(name, codec.encoder, item) },
    fn(fields) { decode_required_property_with(name, fields, codec.decoder) },
    [name],
    property_description(name, True, codec),
  )
}

pub fn optional(name: String, codec: Codec(a)) -> Properties(Optional(a)) {
  Properties(
    fn(item) { encode_optional_property_with(name, codec.encoder, item) },
    fn(fields) { decode_optional_property_with(name, fields, codec.decoder) },
    [name],
    property_description(name, False, codec),
  )
}

/// Represent an optional property with `gleam/option.Option`. Wrap the inner
/// codec in `nullable` when explicit JSON null must be distinct from absence.
pub fn optional_option(name: String, codec: Codec(a)) -> Properties(Option(a)) {
  let Properties(encode, decode, names, schemas) = optional(name, codec)
  Properties(
    fn(item) {
      case item {
        None -> encode(Missing)
        Some(value) -> encode(Present(value))
      }
    },
    fn(fields) {
      case decode(fields) {
        Ok(Missing) -> Ok(None)
        Ok(Present(value)) -> Ok(Some(value))
        Error(error) -> Error(error)
      }
    },
    names,
    schemas,
  )
}

pub fn combine(
  left: Properties(a),
  right: Properties(b),
) -> Result(Properties(#(a, b)), PropertyError) {
  case overlap(left.names, right.names) {
    Present(name) -> Error(DuplicateProperty(name))
    Missing ->
      Ok(
        Properties(
          fn(items) {
            encode_properties_pair_with(left.encode, right.encode, items)
          },
          fn(fields) {
            decode_properties_pair_with(left.decode, right.decode, fields)
          },
          list.append(left.names, right.names),
          case left.schemas, right.schemas {
            Ok(a), Ok(b) -> Ok(list.append(a, b))
            Error(error), _ -> Error(error)
            _, Error(error) -> Error(error)
          },
        ),
      )
  }
}

pub fn object(properties: Properties(a)) -> Codec(a) {
  runtime_codec(
    fn(item) { encode_object_with(properties.encode, item) },
    fn(raw) { decode_object_with(properties.names, properties.decode, raw) },
    case properties.schemas {
      Ok(props) -> Ok(ObjectSchema(props))
      Error(error) -> Error(error)
    },
  )
}

/// Build a two-property native record codec without tuple mapping at the call site.
///
/// Each property may be `required` or `optional`. Property order is preserved,
/// and duplicate names return `DuplicateProperty` before a codec is created.
pub fn record2(
  first: Properties(a),
  second: Properties(b),
  construct: fn(a, b) -> record,
  first_value: fn(record) -> a,
  second_value: fn(record) -> b,
) -> Result(Codec(record), PropertyError) {
  case combine(first, second) {
    Ok(properties) ->
      Ok(
        imap(
          object(properties),
          fn(items) {
            let #(a, b) = items
            construct(a, b)
          },
          fn(item) { #(first_value(item), second_value(item)) },
        ),
      )
    Error(error) -> Error(error)
  }
}

/// Build a three-property native record codec without nested tuple mapping.
///
/// Each property may be `required` or `optional`. Property order is preserved,
/// and duplicate names return `DuplicateProperty` before a codec is created.
pub fn record3(
  first: Properties(a),
  second: Properties(b),
  third: Properties(c),
  construct: fn(a, b, c) -> record,
  first_value: fn(record) -> a,
  second_value: fn(record) -> b,
  third_value: fn(record) -> c,
) -> Result(Codec(record), PropertyError) {
  case combine(first, second) {
    Error(error) -> Error(error)
    Ok(first_two) ->
      case combine(first_two, third) {
        Error(error) -> Error(error)
        Ok(properties) ->
          Ok(
            imap(
              object(properties),
              fn(items) {
                let #(#(a, b), c) = items
                construct(a, b, c)
              },
              fn(item) {
                #(#(first_value(item), second_value(item)), third_value(item))
              },
            ),
          )
      }
  }
}

pub fn field(name: String, inner: Codec(a)) -> Codec(a) {
  let codec = object(required(name, inner))
  let description = case inner.schema {
    Ok(schema) -> Ok(FieldSchema(name, schema))
    Error(error) -> Error(error)
  }
  Codec(..codec, schema: description)
}

fn property_description(
  name: String,
  required: Bool,
  codec: Codec(a),
) -> Result(List(PropertySchema), SchemaError) {
  case codec.schema {
    Ok(schema) -> Ok([PropertySchema(name, required, schema)])
    Error(error) -> Error(error)
  }
}

fn decode_property(
  name: String,
  codec: Codec(a),
  raw: Value,
) -> Result(a, DecodeError) {
  case decode(codec, raw) {
    Ok(item) -> Ok(item)
    Error(error) -> Error(DecodeAtField(name, error))
  }
}

fn lookup(fields: List(#(String, Value)), name: String) -> Optional(Value) {
  case fields {
    [] -> Missing
    [#(key, raw), ..] if key == name -> Present(raw)
    [_, ..rest] -> lookup(rest, name)
  }
}

fn overlap(left: List(String), right: List(String)) -> Optional(String) {
  case left {
    [] -> Missing
    [head, ..rest] ->
      case list.contains(right, head) {
        True -> Present(head)
        False -> overlap(rest, right)
      }
  }
}

fn check_object_keys(
  fields: List(#(String, Value)),
  names: List(String),
  seen: List(String),
) -> Result(Nil, DecodeError) {
  case fields {
    [] -> Ok(Nil)
    [#(name, _), ..rest] ->
      case list.contains(seen, name), list.contains(names, name) {
        True, _ ->
          Error(DecodeAtField(name, CannotDecode(DecodeDuplicateProperty(name))))
        _, False ->
          Error(DecodeAtField(name, CannotDecode(DecodeUnknownProperty(name))))
        False, True -> check_object_keys(rest, names, [name, ..seen])
      }
  }
}

pub type EnumError {
  EmptyEnum
  DuplicateEnumLabel(String)
  DuplicateEnumValue(first_index: Int, repeated_index: Int)
}

type EnumValueIndex {
  NoEnumValue
  EnumValueAt(Int)
}

pub fn string_enum(
  variants: List(#(String, a)),
) -> Result(Codec(a), EnumError) {
  case validate_enum(variants, 0, [], []) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let labels = enum_labels(variants)
      let codec =
        new(fn(item) { encode_enum(item, variants) }, fn(raw) {
          case raw {
            value.String(label) -> decode_enum(label, variants)
            _ -> Error(CannotDecode(DecodeExpectedString))
          }
        })
      Ok(Codec(..codec, schema: Ok(StringEnumSchema(labels))))
    }
  }
}

fn validate_enum(
  variants: List(#(String, a)),
  index: Int,
  seen_labels: List(String),
  seen_values: List(#(Int, a)),
) -> Result(Nil, EnumError) {
  case variants {
    [] ->
      case index {
        0 -> Error(EmptyEnum)
        _ -> Ok(Nil)
      }
    [#(label, item), ..rest] ->
      case list.contains(seen_labels, label) {
        True -> Error(DuplicateEnumLabel(label))
        False ->
          case enum_value_index(item, seen_values) {
            EnumValueAt(first_index) ->
              Error(DuplicateEnumValue(first_index, index))
            NoEnumValue ->
              validate_enum(rest, index + 1, [label, ..seen_labels], [
                #(index, item),
                ..seen_values
              ])
          }
      }
  }
}

fn enum_value_index(item: a, seen_values: List(#(Int, a))) -> EnumValueIndex {
  case seen_values {
    [] -> NoEnumValue
    [#(index, seen), ..rest] ->
      case item == seen {
        True -> EnumValueAt(index)
        False -> enum_value_index(item, rest)
      }
  }
}

fn enum_labels(variants: List(#(String, a))) -> List(String) {
  case variants {
    [] -> []
    [#(label, _), ..rest] -> [label, ..enum_labels(rest)]
  }
}

fn encode_enum(
  item: a,
  variants: List(#(String, a)),
) -> Result(Value, EncodeError) {
  case variants {
    [] ->
      Error(
        CannotEncode(EncodeUnknownEnumValue("Value is not in the string enum")),
      )
    [#(label, candidate), ..rest] ->
      case item == candidate {
        True -> Ok(value.String(label))
        False -> encode_enum(item, rest)
      }
  }
}

fn decode_enum(
  label: String,
  variants: List(#(String, a)),
) -> Result(a, DecodeError) {
  case variants {
    [] -> Error(CannotDecode(DecodeUnknownEnumLabel(label)))
    [#(candidate, item), ..rest] ->
      case label == candidate {
        True -> Ok(item)
        False -> decode_enum(label, rest)
      }
  }
}

pub type Either(left, right) {
  Left(left)
  Right(right)
}

pub type UnionError {
  DuplicateTag(String)
}

pub fn tagged(
  left_tag: String,
  left: Codec(a),
  right_tag: String,
  right: Codec(b),
) -> Result(Codec(Either(a, b)), UnionError) {
  case left_tag == right_tag {
    True -> Error(DuplicateTag(left_tag))
    False -> {
      let description = case left.schema, right.schema {
        Ok(a), Ok(b) -> Ok(TaggedSchema(left_tag, a, right_tag, b))
        Error(error), _ -> Error(error)
        _, Error(error) -> Error(error)
      }
      Ok(runtime_codec(
        fn(item) {
          case item {
            Left(item) -> encode_tagged(left_tag, left, item)
            Right(item) -> encode_tagged(right_tag, right, item)
          }
        },
        fn(raw) {
          case tagged_parts(raw) {
            Error(error) -> Error(error)
            Ok(#(tag, payload)) ->
              case tag {
                tag if tag == left_tag ->
                  case decode_property("value", left, payload) {
                    Ok(item) -> Ok(Left(item))
                    Error(error) -> Error(error)
                  }
                tag if tag == right_tag ->
                  case decode_property("value", right, payload) {
                    Ok(item) -> Ok(Right(item))
                    Error(error) -> Error(error)
                  }
                _ ->
                  Error(DecodeAtField(
                    "tag",
                    CannotDecode(DecodeUnknownTag(tag)),
                  ))
              }
          }
        },
        description,
      ))
    }
  }
}

fn encode_tagged(
  tag: String,
  codec: Codec(a),
  item: a,
) -> Result(Value, EncodeError) {
  case encode(codec, item) {
    Ok(raw) -> Ok(value.Object([#("tag", value.String(tag)), #("value", raw)]))
    Error(error) -> Error(EncodeAtField("value", error))
  }
}

fn tagged_parts(raw: Value) -> Result(#(String, Value), DecodeError) {
  case raw {
    value.Object(fields) ->
      case check_object_keys(fields, ["tag", "value"], []) {
        Error(error) -> Error(error)
        Ok(Nil) ->
          case lookup(fields, "tag"), lookup(fields, "value") {
            Present(value.String(tag)), Present(payload) -> Ok(#(tag, payload))
            Present(value.String(_)), Missing ->
              Error(DecodeAtField(
                "value",
                CannotDecode(DecodeMissingTagPayload("Missing payload")),
              ))
            Present(_), _ ->
              Error(DecodeAtField("tag", CannotDecode(DecodeExpectedString)))
            Missing, _ ->
              Error(DecodeAtField("tag", CannotDecode(DecodeMissingTag)))
          }
      }
    _ -> Error(CannotDecode(DecodeExpectedTaggedObject))
  }
}

pub type ConstraintError {
  InvalidIntegerBounds(min: Int, max: Int)
  ReversedNumberBounds(min: Number, max: Number)
}

pub fn integer_between(
  min: Int,
  max: Int,
) -> Result(Codec(Int), ConstraintError) {
  case min > max {
    True -> Error(InvalidIntegerBounds(min, max))
    False ->
      case number.from_int(min), number.from_int(max) {
        Ok(_), Ok(_) ->
          Ok(runtime_codec(
            fn(item) { encode_integer_between_value(min, max, item) },
            fn(raw) { decode_integer_between_value(min, max, raw) },
            Ok(IntegerRangeSchema(min, max)),
          ))
        _, _ -> Error(InvalidIntegerBounds(min, max))
      }
  }
}

pub fn number_between(
  min: Number,
  max: Number,
) -> Result(Codec(Number), ConstraintError) {
  case number.compare(min, max) {
    number.GreaterThan -> Error(ReversedNumberBounds(min, max))
    _ ->
      Ok(runtime_codec(
        fn(item) {
          case
            number.compare(item, min) != number.LessThan
            && number.compare(item, max) != number.GreaterThan
          {
            True -> Ok(value.Number(item))
            False ->
              Error(CannotEncode(EncodeNumberOutsideRange(min, max, item)))
          }
        },
        fn(raw) {
          case raw {
            value.Number(item) ->
              case
                number.compare(item, min) != number.LessThan
                && number.compare(item, max) != number.GreaterThan
              {
                True -> Ok(item)
                False ->
                  Error(CannotDecode(DecodeNumberOutsideRange(min, max, item)))
              }
            _ -> Error(CannotDecode(DecodeExpectedNumber))
          }
        },
        Ok(NumberRangeSchema(min, max)),
      ))
  }
}

pub fn schema_value(schema: Schema) -> Value {
  case schema {
    DescribedSchema(description, DescribedSchema(_, inner)) ->
      schema_value(DescribedSchema(description, inner))
    DescribedSchema(description, inner) -> {
      let assert value.Object(fields) = schema_value(inner)
      value.Object([#("description", value.String(description)), ..fields])
    }
    StringSchema -> value.Object([#("type", value.String("string"))])
    StringEnumSchema(labels) ->
      value.Object([
        #("type", value.String("string")),
        #("enum", value.Array(list.map(labels, value.String))),
      ])
    IntSchema -> value.Object([#("type", value.String("integer"))])
    NumberSchema -> value.Object([#("type", value.String("number"))])
    BoolSchema -> value.Object([#("type", value.String("boolean"))])
    PairSchema(a, b) -> {
      let assert Ok(two) = number.from_int(2)
      value.Object([
        #("type", value.String("array")),
        #("prefixItems", value.Array([schema_value(a), schema_value(b)])),
        #("minItems", value.Number(two)),
        #("maxItems", value.Number(two)),
      ])
    }
    FieldSchema(name, inner) ->
      value.Object([
        #("type", value.String("object")),
        #("properties", value.Object([#(name, schema_value(inner))])),
        #("required", value.Array([value.String(name)])),
        #("additionalProperties", value.Bool(False)),
      ])
    ListSchema(inner) ->
      value.Object([
        #("type", value.String("array")),
        #("items", schema_value(inner)),
      ])
    NullableSchema(inner) ->
      value.Object([
        #(
          "anyOf",
          value.Array([
            value.Object([#("type", value.String("null"))]),
            schema_value(inner),
          ]),
        ),
      ])
    ObjectSchema(properties) ->
      value.Object([
        #("type", value.String("object")),
        #("properties", value.Object(property_schemas(properties))),
        #("required", value.Array(required_names(properties))),
        #("additionalProperties", value.Bool(False)),
      ])
    TaggedSchema(left_tag, left, right_tag, right) ->
      value.Object([
        #("type", value.String("object")),
        #(
          "oneOf",
          value.Array([
            tagged_schema(left_tag, left),
            tagged_schema(right_tag, right),
          ]),
        ),
      ])
    IntegerRangeSchema(min, max) -> {
      let assert Ok(min_num) = number.from_int(min)
      let assert Ok(max_num) = number.from_int(max)
      value.Object([
        #("type", value.String("integer")),
        #("minimum", value.Number(min_num)),
        #("maximum", value.Number(max_num)),
      ])
    }
    NumberRangeSchema(min, max) ->
      value.Object([
        #("type", value.String("number")),
        #("minimum", value.Number(min)),
        #("maximum", value.Number(max)),
      ])
  }
}

pub fn schema_document(schema: Schema) -> Value {
  let assert value.Object(fields) = schema_value(schema)
  value.Object([
    #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
    ..fields
  ])
}

fn property_schemas(
  properties: List(PropertySchema),
) -> List(#(String, Value)) {
  case properties {
    [] -> []
    [PropertySchema(name, _, schema), ..rest] -> [
      #(name, schema_value(schema)),
      ..property_schemas(rest)
    ]
  }
}

fn required_names(properties: List(PropertySchema)) -> List(Value) {
  case properties {
    [] -> []
    [PropertySchema(name, True, _), ..rest] -> [
      value.String(name),
      ..required_names(rest)
    ]
    [_, ..rest] -> required_names(rest)
  }
}

fn tagged_schema(tag: String, payload: Schema) -> Value {
  value.Object([
    #("type", value.String("object")),
    #(
      "properties",
      value.Object([
        #("tag", value.Object([#("const", value.String(tag))])),
        #("value", schema_value(payload)),
      ]),
    ),
    #("required", value.Array([value.String("tag"), value.String("value")])),
    #("additionalProperties", value.Bool(False)),
  ])
}
