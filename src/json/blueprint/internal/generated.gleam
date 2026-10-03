//// Helpers called by modules that `json_blueprint_codegen` generates.
////
//// Generated modules live in application repositories, so the names and
//// signatures here stay stable within a major version of json_blueprint,
//// although the module is internal. Application code uses
//// `json/blueprint/codec` instead.
////
//// The `encode_*` and `decode_*` functions mirror the codec combinators over
//// `Value`; the `*_native_*` functions do the same over `gleam/json` values
//// and the `Dynamic` data that `json.parse` produces.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import json/blueprint/codec.{
  type DecodeError, type EncodeError, DecodeError, EncodeError, Field, Index,
}
import json/blueprint/internal/schema_tree.{type Tree}
import json/blueprint/internal/text
import json/blueprint/number.{type Number}
import json/blueprint/value.{type Value}

type Members =
  List(#(String, Value))

/// The schema that a generated module declares as a `const` tree.
pub fn schema(tree: Tree) -> codec.Schema {
  codec.from_tree(tree)
}

type NativeMembers =
  List(#(String, json.Json))

fn fail(reason: codec.Reason) -> Result(a, DecodeError) {
  Error(DecodeError([], reason))
}

fn refuse(reason: codec.Reason) -> Result(a, EncodeError) {
  Error(EncodeError([], reason))
}

fn at_encode(
  outcome: Result(a, EncodeError),
  segment,
) -> Result(a, EncodeError) {
  result.map_error(outcome, fn(error) {
    EncodeError([segment, ..error.path], error.reason)
  })
}

fn at_decode(
  outcome: Result(a, DecodeError),
  segment,
) -> Result(a, DecodeError) {
  result.map_error(outcome, fn(error) {
    DecodeError([segment, ..error.path], error.reason)
  })
}

// --- errors for generated enum arms -------------------------------------------

pub fn unknown_enum_value() -> Result(a, EncodeError) {
  refuse(codec.UnknownEnumValue)
}

pub fn unknown_enum_label() -> Result(a, DecodeError) {
  fail(codec.UnknownEnumLabel)
}

pub fn expected_string() -> Result(a, DecodeError) {
  fail(codec.ExpectedString)
}

/// A placeholder `Number` for generated codecs.
pub fn zero_number() -> Number {
  let assert Ok(zero) = number.from_int(0)
  zero
}

// --- Value ---------------------------------------------------------------------

pub fn encode_string(item: String) -> Result(Value, EncodeError) {
  Ok(value.String(item))
}

pub fn decode_string(raw: Value) -> Result(String, DecodeError) {
  case raw {
    value.String(item) -> Ok(item)
    _ -> fail(codec.ExpectedString)
  }
}

pub fn encode_int(item: Int) -> Result(Value, EncodeError) {
  case number.from_int(item) {
    Ok(parsed) -> Ok(value.Number(parsed))
    Error(_) -> refuse(codec.UnsafeInteger)
  }
}

/// The same 24-digit projection as `codec.int()`.
pub fn decode_int(raw: Value) -> Result(Int, DecodeError) {
  case raw {
    value.Number(item) ->
      number.to_int(item, 24)
      |> result.replace_error(DecodeError([], codec.ExpectedInt))
    _ -> fail(codec.ExpectedInt)
  }
}

pub fn encode_number(item: Number) -> Result(Value, EncodeError) {
  Ok(value.Number(item))
}

pub fn decode_number(raw: Value) -> Result(Number, DecodeError) {
  case raw {
    value.Number(item) -> Ok(item)
    _ -> fail(codec.ExpectedNumber)
  }
}

pub fn encode_bool(item: Bool) -> Result(Value, EncodeError) {
  Ok(value.Bool(item))
}

pub fn decode_bool(raw: Value) -> Result(Bool, DecodeError) {
  case raw {
    value.Bool(item) -> Ok(item)
    _ -> fail(codec.ExpectedBool)
  }
}

pub fn encode_integer_between(
  minimum: Int,
  maximum: Int,
  item: Int,
) -> Result(Value, EncodeError) {
  case item >= minimum && item <= maximum {
    True -> encode_int(item)
    False -> refuse(codec.IntegerOutsideRange(minimum, maximum))
  }
}

pub fn decode_integer_between(
  minimum: Int,
  maximum: Int,
  raw: Value,
) -> Result(Int, DecodeError) {
  case raw {
    value.Number(item) ->
      case
        number.is_integer(item),
        number.from_int(minimum),
        number.from_int(maximum)
      {
        False, _, _ -> fail(codec.ExpectedInt)
        True, Ok(lower), Ok(upper) ->
          case
            number.compare(item, lower) != order.Lt
            && number.compare(item, upper) != order.Gt
          {
            True ->
              number.to_int(item, 2000)
              |> result.replace_error(DecodeError([], codec.ExpectedInt))
            False -> fail(codec.IntegerOutsideRange(minimum, maximum))
          }
        True, _, _ -> fail(codec.IntegerOutsideRange(minimum, maximum))
      }
    _ -> fail(codec.ExpectedInt)
  }
}

pub fn encode_pair(
  encode_left: fn(a) -> Result(Value, EncodeError),
  encode_right: fn(b) -> Result(Value, EncodeError),
  item: #(a, b),
) -> Result(Value, EncodeError) {
  use left <- result.try(encode_left(item.0) |> at_encode(Index(0)))
  use right <- result.map(encode_right(item.1) |> at_encode(Index(1)))
  value.Array([left, right])
}

pub fn decode_pair(
  decode_left: fn(Value) -> Result(a, DecodeError),
  decode_right: fn(Value) -> Result(b, DecodeError),
  raw: Value,
) -> Result(#(a, b), DecodeError) {
  case raw {
    value.Array([left, right]) -> {
      use left <- result.try(decode_left(left) |> at_decode(Index(0)))
      use right <- result.map(decode_right(right) |> at_decode(Index(1)))
      #(left, right)
    }
    value.Array(items) -> fail(codec.WrongLength(2, list.length(items)))
    _ -> fail(codec.ExpectedArray)
  }
}

pub fn encode_list(
  encode_item: fn(a) -> Result(Value, EncodeError),
  items: List(a),
) -> Result(Value, EncodeError) {
  list.index_map(items, fn(item, index) { #(index, item) })
  |> list.try_map(fn(pair) { encode_item(pair.1) |> at_encode(Index(pair.0)) })
  |> result.map(value.Array)
}

pub fn decode_list(
  decode_item: fn(Value) -> Result(a, DecodeError),
  raw: Value,
) -> Result(List(a), DecodeError) {
  case raw {
    value.Array(items) ->
      list.index_map(items, fn(item, index) { #(index, item) })
      |> list.try_map(fn(pair) {
        decode_item(pair.1) |> at_decode(Index(pair.0))
      })
    _ -> fail(codec.ExpectedArray)
  }
}

pub fn encode_nullable(
  encode_inner: fn(a) -> Result(Value, EncodeError),
  item: Option(a),
) -> Result(Value, EncodeError) {
  case item {
    None -> Ok(value.Null)
    Some(item) ->
      case encode_inner(item) {
        Ok(value.Null) -> refuse(codec.NullInsideNullable)
        other -> other
      }
  }
}

pub fn decode_nullable(
  decode_inner: fn(Value) -> Result(a, DecodeError),
  raw: Value,
) -> Result(Option(a), DecodeError) {
  case raw {
    value.Null -> Ok(None)
    _ -> decode_inner(raw) |> result.map(Some)
  }
}

pub fn encode_required(
  name: String,
  encode_item: fn(a) -> Result(Value, EncodeError),
  item: a,
) -> Result(Members, EncodeError) {
  use encoded <- result.map(encode_item(item) |> at_encode(Field(name)))
  [#(name, encoded)]
}

pub fn encode_optional(
  name: String,
  encode_item: fn(a) -> Result(Value, EncodeError),
  item: Option(a),
) -> Result(Members, EncodeError) {
  case item {
    None -> Ok([])
    Some(item) -> encode_required(name, encode_item, item)
  }
}

pub fn decode_required(
  name: String,
  members: Members,
  decode_item: fn(Value) -> Result(a, DecodeError),
) -> Result(a, DecodeError) {
  case list.key_find(members, name) {
    Error(Nil) -> Error(DecodeError([Field(name)], codec.MissingField))
    Ok(raw) -> decode_item(raw) |> at_decode(Field(name))
  }
}

pub fn decode_optional(
  name: String,
  members: Members,
  decode_item: fn(Value) -> Result(a, DecodeError),
) -> Result(Option(a), DecodeError) {
  case list.key_find(members, name) {
    Error(Nil) -> Ok(None)
    Ok(raw) -> decode_item(raw) |> at_decode(Field(name)) |> result.map(Some)
  }
}

pub fn encode_fields_pair(
  encode_left: fn(a) -> Result(Members, EncodeError),
  encode_right: fn(b) -> Result(Members, EncodeError),
  item: #(a, b),
) -> Result(Members, EncodeError) {
  use left <- result.try(encode_left(item.0))
  use right <- result.map(encode_right(item.1))
  list.append(left, right)
}

pub fn decode_fields_pair(
  decode_left: fn(Members) -> Result(a, DecodeError),
  decode_right: fn(Members) -> Result(b, DecodeError),
  members: Members,
) -> Result(#(a, b), DecodeError) {
  use left <- result.try(decode_left(members))
  use right <- result.map(decode_right(members))
  #(left, right)
}

pub fn encode_object(
  encode_fields: fn(a) -> Result(Members, EncodeError),
  item: a,
) -> Result(Value, EncodeError) {
  encode_fields(item) |> result.map(value.Object)
}

/// Decode a closed object: an unknown or repeated key fails before any field
/// decodes.
pub fn decode_object(
  names: List(String),
  decode_fields: fn(Members) -> Result(a, DecodeError),
  raw: Value,
) -> Result(a, DecodeError) {
  case raw {
    value.Object(members) -> {
      use Nil <- result.try(
        check_members(list.map(members, fn(member) { member.0 }), names, []),
      )
      decode_fields(members)
    }
    _ -> fail(codec.ExpectedObject)
  }
}

fn check_members(
  keys: List(String),
  names: List(String),
  seen: List(String),
) -> Result(Nil, DecodeError) {
  case keys {
    [] -> Ok(Nil)
    [key, ..rest] ->
      case list.contains(seen, key), list.contains(names, key) {
        True, _ -> Error(DecodeError([Field(key)], codec.DuplicateField))
        _, False -> Error(DecodeError([Field(key)], codec.UnknownField))
        False, True -> check_members(rest, names, [key, ..seen])
      }
  }
}

pub fn encode_mapped(
  encode_inner: fn(a) -> Result(Value, EncodeError),
  to_inner: fn(b) -> a,
  item: b,
) -> Result(Value, EncodeError) {
  encode_inner(to_inner(item))
}

pub fn decode_mapped(
  decode_inner: fn(Value) -> Result(a, DecodeError),
  from_inner: fn(a) -> b,
  raw: Value,
) -> Result(b, DecodeError) {
  decode_inner(raw) |> result.map(from_inner)
}

// --- gleam/json ----------------------------------------------------------------

pub fn encode_native_int(item: Int) -> Result(json.Json, EncodeError) {
  case number.from_int(item) {
    Ok(_) -> Ok(json.int(item))
    Error(_) -> refuse(codec.UnsafeInteger)
  }
}

pub fn encode_native_integer_between(
  minimum: Int,
  maximum: Int,
  item: Int,
) -> Result(json.Json, EncodeError) {
  case item >= minimum && item <= maximum {
    True -> encode_native_int(item)
    False -> refuse(codec.IntegerOutsideRange(minimum, maximum))
  }
}

pub fn encode_native_pair(
  encode_left: fn(a) -> Result(json.Json, EncodeError),
  encode_right: fn(b) -> Result(json.Json, EncodeError),
  item: #(a, b),
) -> Result(json.Json, EncodeError) {
  use left <- result.try(encode_left(item.0) |> at_encode(Index(0)))
  use right <- result.map(encode_right(item.1) |> at_encode(Index(1)))
  json.preprocessed_array([left, right])
}

pub fn encode_native_list(
  encode_item: fn(a) -> Result(json.Json, EncodeError),
  items: List(a),
) -> Result(json.Json, EncodeError) {
  list.index_map(items, fn(item, index) { #(index, item) })
  |> list.try_map(fn(pair) { encode_item(pair.1) |> at_encode(Index(pair.0)) })
  |> result.map(json.preprocessed_array)
}

pub fn encode_native_nullable(
  encode_inner: fn(a) -> Result(json.Json, EncodeError),
  item: Option(a),
) -> Result(json.Json, EncodeError) {
  case item {
    None -> Ok(json.null())
    Some(item) -> {
      use encoded <- result.try(encode_inner(item))
      case encoded == json.null() {
        True -> refuse(codec.NullInsideNullable)
        False -> Ok(encoded)
      }
    }
  }
}

pub fn encode_native_required(
  name: String,
  encode_item: fn(a) -> Result(json.Json, EncodeError),
  item: a,
) -> Result(NativeMembers, EncodeError) {
  use encoded <- result.map(encode_item(item) |> at_encode(Field(name)))
  [#(name, encoded)]
}

pub fn encode_native_optional(
  name: String,
  encode_item: fn(a) -> Result(json.Json, EncodeError),
  item: Option(a),
) -> Result(NativeMembers, EncodeError) {
  case item {
    None -> Ok([])
    Some(item) -> encode_native_required(name, encode_item, item)
  }
}

pub fn encode_native_fields_pair(
  encode_left: fn(a) -> Result(NativeMembers, EncodeError),
  encode_right: fn(b) -> Result(NativeMembers, EncodeError),
  item: #(a, b),
) -> Result(NativeMembers, EncodeError) {
  use left <- result.try(encode_left(item.0))
  use right <- result.map(encode_right(item.1))
  list.append(left, right)
}

pub fn encode_native_object(
  encode_fields: fn(a) -> Result(NativeMembers, EncodeError),
  item: a,
) -> Result(json.Json, EncodeError) {
  encode_fields(item) |> result.map(json.object)
}

pub fn decode_native_string(raw: Dynamic) -> Result(String, DecodeError) {
  decode.run(raw, decode.string)
  |> result.replace_error(DecodeError([], codec.ExpectedString))
}

/// Decode a native JSON number with the same exact 24-digit projection as
/// `codec.int()`. The native parser normalizes number tokens first; on
/// JavaScript it may round a fractional token to an integer.
pub fn decode_native_int(raw: Dynamic) -> Result(Int, DecodeError) {
  case native_number(raw) {
    Ok(item) ->
      number.to_int(item, 24)
      |> result.replace_error(DecodeError([], codec.ExpectedInt))
    Error(Nil) -> fail(codec.ExpectedInt)
  }
}

/// Decode a native JSON number with the same range check and projection as
/// `decode_integer_between`, so every integer within the bounds decodes, even
/// one longer than `codec.int()` accepts.
pub fn decode_native_integer_between(
  minimum: Int,
  maximum: Int,
  raw: Dynamic,
) -> Result(Int, DecodeError) {
  case native_number(raw) {
    Ok(item) -> decode_integer_between(minimum, maximum, value.Number(item))
    Error(Nil) -> fail(codec.ExpectedInt)
  }
}

/// The exact number of a native integer or float. Fails for other data, and
/// on JavaScript for an integer outside the safe range.
fn native_number(raw: Dynamic) -> Result(Number, Nil) {
  case decode.run(raw, decode.int) {
    Ok(item) -> number.from_int(item) |> result.replace_error(Nil)
    Error(_) ->
      case decode.run(raw, decode.float) {
        Ok(item) -> number.from_float(item) |> result.replace_error(Nil)
        Error(_) -> Error(Nil)
      }
  }
}

pub fn decode_native_bool(raw: Dynamic) -> Result(Bool, DecodeError) {
  decode.run(raw, decode.bool)
  |> result.replace_error(DecodeError([], codec.ExpectedBool))
}

pub fn decode_native_pair(
  decode_left: fn(Dynamic) -> Result(a, DecodeError),
  decode_right: fn(Dynamic) -> Result(b, DecodeError),
  raw: Dynamic,
) -> Result(#(a, b), DecodeError) {
  case decode.run(raw, decode.list(decode.dynamic)) {
    Error(_) -> fail(codec.ExpectedArray)
    Ok([left, right]) -> {
      use left <- result.try(decode_left(left) |> at_decode(Index(0)))
      use right <- result.map(decode_right(right) |> at_decode(Index(1)))
      #(left, right)
    }
    Ok(items) -> fail(codec.WrongLength(2, list.length(items)))
  }
}

pub fn decode_native_list(
  decode_item: fn(Dynamic) -> Result(a, DecodeError),
  raw: Dynamic,
) -> Result(List(a), DecodeError) {
  case decode.run(raw, decode.list(decode.dynamic)) {
    Error(_) -> fail(codec.ExpectedArray)
    Ok(items) ->
      list.index_map(items, fn(item, index) { #(index, item) })
      |> list.try_map(fn(pair) {
        decode_item(pair.1) |> at_decode(Index(pair.0))
      })
  }
}

pub fn decode_native_nullable(
  decode_inner: fn(Dynamic) -> Result(a, DecodeError),
  raw: Dynamic,
) -> Result(Option(a), DecodeError) {
  case decode.run(raw, decode.optional(decode.dynamic)) {
    Ok(None) -> Ok(None)
    Ok(Some(inner)) -> decode_inner(inner) |> result.map(Some)
    Error(_) -> decode_inner(raw) |> result.map(Some)
  }
}

pub fn decode_native_required(
  name: String,
  members: Dict(String, Dynamic),
  decode_item: fn(Dynamic) -> Result(a, DecodeError),
) -> Result(a, DecodeError) {
  case dict.get(members, name) {
    Error(Nil) -> Error(DecodeError([Field(name)], codec.MissingField))
    Ok(raw) -> decode_item(raw) |> at_decode(Field(name))
  }
}

pub fn decode_native_optional(
  name: String,
  members: Dict(String, Dynamic),
  decode_item: fn(Dynamic) -> Result(a, DecodeError),
) -> Result(Option(a), DecodeError) {
  case dict.get(members, name) {
    Error(Nil) -> Ok(None)
    Ok(raw) -> decode_item(raw) |> at_decode(Field(name)) |> result.map(Some)
  }
}

pub fn decode_native_fields_pair(
  decode_left: fn(Dict(String, Dynamic)) -> Result(a, DecodeError),
  decode_right: fn(Dict(String, Dynamic)) -> Result(b, DecodeError),
  members: Dict(String, Dynamic),
) -> Result(#(a, b), DecodeError) {
  use left <- result.try(decode_left(members))
  use right <- result.map(decode_right(members))
  #(left, right)
}

pub fn decode_native_object(
  names: List(String),
  decode_fields: fn(Dict(String, Dynamic)) -> Result(a, DecodeError),
  raw: Dynamic,
) -> Result(a, DecodeError) {
  case decode.run(raw, decode.dict(decode.string, decode.dynamic)) {
    Error(_) -> fail(codec.ExpectedObject)
    Ok(members) ->
      case
        list.find(dict.keys(members), fn(key) { !list.contains(names, key) })
      {
        Ok(key) -> Error(DecodeError([Field(key)], codec.UnknownField))
        Error(Nil) -> decode_fields(members)
      }
  }
}

/// A `gleam/dynamic/decode` decoder from a generated native decoder. A
/// failure's `expected` is the `codec.describe_decode_error` text.
pub fn native_decoder(
  decode_native: fn(Dynamic) -> Result(a, DecodeError),
  placeholder: a,
) -> decode.Decoder(a) {
  decode.dynamic
  |> decode.then(fn(raw) {
    case decode_native(raw) {
      Ok(item) -> decode.success(item)
      Error(error) ->
        decode.failure(placeholder, codec.describe_decode_error(error))
    }
  })
}

/// Parse text with `gleam/json` and decode it natively. Text above 1 MiB is
/// rejected before parsing, with one error naming the limit.
pub fn decode_json_native(
  source: String,
  decode_native: fn(Dynamic) -> Result(a, DecodeError),
  placeholder: a,
) -> Result(a, json.DecodeError) {
  let limit = text.default_max_bytes
  case text.exceeds_byte_limit(source, limit) {
    True ->
      Error(
        json.UnableToDecode([
          decode.DecodeError(
            expected: "JSON text of at most "
              <> int.to_string(limit)
              <> " bytes",
            found: "more than " <> int.to_string(limit) <> " bytes",
            path: [],
          ),
        ]),
      )
    False -> json.parse(source, native_decoder(decode_native, placeholder))
  }
}
