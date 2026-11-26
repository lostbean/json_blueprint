//// Helpers called by modules that `json/blueprint/codegen` generates.
////
//// Generated modules live in application repositories, so the names and
//// signatures here stay stable within a major version of json_blueprint,
//// although the module is internal. Application code uses
//// `json/blueprint/codec` instead.
////
//// The `encode_*` and `decode_*` functions mirror the codec combinators over
//// `Value`; the `encode_native_*` functions encode to `gleam/json` values.
//// Text is decoded only by the shared strict parser, behind
//// `codec.decode_json`: the `decode_strict_*` helpers consume its retained
//// native evidence, preserving its limits, exact numbers and duplicate-key
//// rejection without a Value conversion.

import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import json/blueprint/codec.{
  type DecodeError, type EncodeError, DecodeError, EncodeError, Field, Index,
}
import json/blueprint/internal/native
import json/blueprint/internal/schema_tree.{type Tree}
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
  use encoded <- result.try(encode_safe_int(item))
  use Nil <- result.map(check_int_digits(item))
  encoded
}

fn check_int_digits(item: Int) -> Result(Nil, EncodeError) {
  case digit_count(item) <= 24 {
    True -> Ok(Nil)
    False -> refuse(codec.ExpectedInt)
  }
}

fn digit_count(item: Int) -> Int {
  string.length(int.to_string(int.absolute_value(item)))
}

fn encode_safe_int(item: Int) -> Result(Value, EncodeError) {
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
    True -> encode_safe_int(item)
    False -> refuse(codec.IntegerOutsideRange(minimum, maximum))
  }
}

pub fn decode_integer_between(
  minimum: Int,
  maximum: Int,
  raw: Value,
) -> Result(Int, DecodeError) {
  case raw {
    value.Number(item) -> decode_bounded_integer(minimum, maximum, item)
    _ -> fail(codec.ExpectedInt)
  }
}

fn decode_bounded_integer(
  minimum: Int,
  maximum: Int,
  item: Number,
) -> Result(Int, DecodeError) {
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
          number.to_int(
            item,
            int.max(digit_count(minimum), digit_count(maximum)),
          )
          |> result.replace_error(DecodeError([], codec.ExpectedInt))
        False -> fail(codec.IntegerOutsideRange(minimum, maximum))
      }
    True, _, _ -> fail(codec.IntegerOutsideRange(minimum, maximum))
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

/// Decode fields before rejecting unknown or repeated keys, matching runtime
/// record error precedence.
pub fn decode_object(
  names: List(String),
  decode_fields: fn(Members) -> Result(a, DecodeError),
  raw: Value,
) -> Result(a, DecodeError) {
  case raw {
    value.Object(members) -> {
      use decoded <- result.try(decode_fields(members))
      check_members(list.map(members, fn(member) { member.0 }), names, [])
      |> result.replace(decoded)
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
  use encoded <- result.try(encode_native_safe_int(item))
  use Nil <- result.map(check_int_digits(item))
  encoded
}

fn encode_native_safe_int(item: Int) -> Result(json.Json, EncodeError) {
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
    True -> encode_native_safe_int(item)
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

// Strict decoder helpers consume evidence admitted by the shared parser.
// They never parse source or weaken duplicate-key and numeric guarantees.
fn strict_numeric_failure(
  error: native.NumericError,
  reason: codec.Reason,
) -> DecodeError {
  case error {
    native.ProjectionCapacity ->
      DecodeError(
        [],
        codec.InvalidJson(value.ParseError(
          value.Location(0, 0, 0),
          value.RuntimeCapacityExceeded,
        )),
      )
    _ -> DecodeError([], reason)
  }
}

pub fn decode_strict_string(raw: native.Raw) -> Result(String, DecodeError) {
  native.string(raw)
  |> result.replace_error(DecodeError([], codec.ExpectedString))
}

pub fn decode_strict_int(raw: native.Raw) -> Result(Int, DecodeError) {
  native.int(raw)
  |> result.map_error(fn(error) {
    strict_numeric_failure(error, codec.ExpectedInt)
  })
}

pub fn decode_strict_integer_between(
  minimum: Int,
  maximum: Int,
  raw: native.Raw,
) -> Result(Int, DecodeError) {
  // Most bounded values are representable native integers. Their exact
  // projection has already checked token integrality, so bounds need no
  // temporary Number values. Wider integers/fractions retain exact fallback.
  case native.int(raw) {
    Ok(item) ->
      case item >= minimum && item <= maximum {
        True -> Ok(item)
        False -> fail(codec.IntegerOutsideRange(minimum, maximum))
      }
    Error(_) -> {
      use item <- result.try(
        native.number(raw)
        |> result.map_error(fn(error) {
          strict_numeric_failure(error, codec.ExpectedInt)
        }),
      )
      decode_bounded_integer(minimum, maximum, item)
    }
  }
}

pub fn decode_strict_bool(raw: native.Raw) -> Result(Bool, DecodeError) {
  native.bool(raw) |> result.replace_error(DecodeError([], codec.ExpectedBool))
}

pub fn decode_strict_pair(
  left: fn(native.Raw) -> Result(a, DecodeError),
  right: fn(native.Raw) -> Result(b, DecodeError),
  raw: native.Raw,
) -> Result(#(a, b), DecodeError) {
  case native.array_items(raw) {
    Error(_) -> fail(codec.ExpectedArray)
    Ok([a, b]) -> {
      use a <- result.try(left(a) |> at_decode(Index(0)))
      use b <- result.map(right(b) |> at_decode(Index(1)))
      #(a, b)
    }
    Ok(items) -> fail(codec.WrongLength(2, list.length(items)))
  }
}

pub fn decode_strict_list(
  decode_item: fn(native.Raw) -> Result(a, DecodeError),
  raw: native.Raw,
) -> Result(List(a), DecodeError) {
  native.array_decode(
    raw,
    fn(item, index) { decode_item(item) |> at_decode(Index(index)) },
    DecodeError([], codec.ExpectedArray),
  )
}

pub fn decode_strict_nullable(
  decode_inner: fn(native.Raw) -> Result(a, DecodeError),
  raw: native.Raw,
) -> Result(Option(a), DecodeError) {
  case native.is_null(raw) {
    True -> Ok(None)
    False -> decode_inner(raw) |> result.map(Some)
  }
}

pub fn decode_strict_required(
  name: String,
  members: native.Raw,
  decode_item: fn(native.Raw) -> Result(a, DecodeError),
) -> Result(a, DecodeError) {
  case native.field(members, name) {
    Error(_) -> Error(DecodeError([Field(name)], codec.MissingField))
    Ok(raw) -> decode_item(raw) |> at_decode(Field(name))
  }
}

pub fn decode_strict_optional(
  name: String,
  members: native.Raw,
  decode_item: fn(native.Raw) -> Result(a, DecodeError),
) -> Result(Option(a), DecodeError) {
  case native.field(members, name) {
    Error(_) -> Ok(None)
    Ok(raw) -> decode_item(raw) |> at_decode(Field(name)) |> result.map(Some)
  }
}

pub fn decode_strict_fields_pair(
  left: fn(native.Raw) -> Result(a, DecodeError),
  right: fn(native.Raw) -> Result(b, DecodeError),
  raw: native.Raw,
) -> Result(#(a, b), DecodeError) {
  use a <- result.try(left(raw))
  use b <- result.map(right(raw))
  #(a, b)
}

pub fn decode_strict_object(
  names: List(String),
  decode_fields: fn(native.Raw) -> Result(a, DecodeError),
  raw: native.Raw,
) -> Result(a, DecodeError) {
  case native.keys(raw) {
    Error(_) -> fail(codec.ExpectedObject)
    Ok(keys) -> {
      use item <- result.try(decode_fields(raw))
      // Raw comes only from the strict parser, which has already rejected
      // duplicate decoded names. Retain field-first unknown-key diagnostics.
      check_strict_keys(keys, names) |> result.replace(item)
    }
  }
}

fn check_strict_keys(
  keys: List(String),
  names: List(String),
) -> Result(Nil, DecodeError) {
  case keys {
    [] -> Ok(Nil)
    [key, ..rest] ->
      case list.contains(names, key) {
        True -> check_strict_keys(rest, names)
        False -> Error(DecodeError([Field(key)], codec.UnknownField))
      }
  }
}
