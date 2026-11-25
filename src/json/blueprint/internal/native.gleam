//// Native JSON parsing and checked access to its internal values.
////
//// Erlang keeps exact native integers and decimal source tokens until a
//// numeric projection is requested. Parsing rejects duplicate object keys
//// and applies the caller's byte bound and, when the caller sets them, a
//// nesting-depth and a value-count bound. Callers choose their own limits for
//// already-decoded structure. JavaScript retains source tokens with the
//// native parser reviver and scans the original names and escaped Unicode.

import gleam/option.{type Option, None, Some}
import gleam/result
import json/blueprint/internal/text
import json/blueprint/number

/// Values produced by this parser, or children obtained through its accessors.
/// The representation belongs to the backend and is not an application API.
pub type Raw

pub type ParseError {
  Syntax(String)
  DuplicateKey(String)
  ByteLimitExceeded
  DepthLimit
  ValueLimit
  InvalidUnicodeScalar
  UnsupportedRuntime
  RuntimeCapacity
  NumberRepresentation
}

pub type NumericError {
  NotNumber
  Unrepresentable
  ProjectionCapacity
}

pub type Kind {
  Null
  Bool
  String
  Number
  Array
  Object
}

// exported only from this internal module for JS FFI constructors.
pub type NumberInput {
  Integer(Int)
  Decimal(String)
  Other
}

@target(erlang)
pub fn supported() -> Bool {
  True
}

@target(javascript)
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "supported")
pub fn supported() -> Bool

@external(erlang, "json_blueprint_native_ffi", "parse")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "parse")
fn parse_native(_source: String) -> Result(Raw, ParseError) {
  Error(UnsupportedRuntime)
}

@external(erlang, "json_blueprint_native_ffi", "parse_bounded")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "parse_bounded")
fn parse_native_bounded(
  _source: String,
  _max_depth: Int,
  _max_values: Int,
) -> Result(Raw, ParseError) {
  Error(UnsupportedRuntime)
}

/// Stands for an absent structural bound when only the other one is set. No
/// admitted text has this many levels or values, and both targets hold it
/// exactly.
const unbounded = 9_007_199_254_740_991

/// The byte check occurs before native parsing and tree allocation.
/// Full syntax admission finishes before any typed decoder is invoked.
pub fn parse(source: String, max_bytes: Int) -> Result(Raw, ParseError) {
  parse_within(source, max_bytes, None, None)
}

/// `parse` with optional bounds on nesting depth and on the number of values.
/// A scalar root has depth 0 and every array or object adds one level; every
/// value counts, the root and containers included. Without either bound this
/// is `parse` and does no structural accounting.
pub fn parse_within(
  source: String,
  max_bytes: Int,
  max_depth: Option(Int),
  max_values: Option(Int),
) -> Result(Raw, ParseError) {
  case text.exceeds_byte_limit(source, max_bytes) {
    True -> Error(ByteLimitExceeded)
    False -> {
      use _ <- result.try(
        text.validate_scalars(source)
        |> result.map_error(fn(_) { InvalidUnicodeScalar }),
      )
      case max_depth, max_values {
        None, None -> parse_native(source)
        // The root value is at depth 0, so a negative bound admits nothing.
        Some(depth), _ if depth < 0 -> Error(DepthLimit)
        _, _ ->
          parse_native_bounded(
            source,
            option.unwrap(max_depth, unbounded),
            option.unwrap(max_values, unbounded),
          )
      }
    }
  }
}

@external(erlang, "json_blueprint_native_ffi", "kind")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "kind")
pub fn kind(_raw: Raw) -> Kind {
  panic as "Native JSON is unavailable on this target"
}

@external(erlang, "json_blueprint_native_ffi", "string")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "string")
pub fn string(_raw: Raw) -> Result(String, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "boolean")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "boolean")
pub fn bool(_raw: Raw) -> Result(Bool, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "is_null")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "is_null")
pub fn is_null(_raw: Raw) -> Bool {
  False
}

@external(erlang, "json_blueprint_native_ffi", "keys")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "keys")
pub fn keys(_raw: Raw) -> Result(List(String), Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "field")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "field")
pub fn field(_raw: Raw, _name: String) -> Result(Raw, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "array_items")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "array_items")
pub fn array_items(_raw: Raw) -> Result(List(Raw), Nil) {
  Error(Nil)
}

/// Decode an array without constructing a second untyped list. The callback
/// is invoked in array order and stops at the first typed failure.
@external(erlang, "json_blueprint_native_ffi", "array_decode")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "array_decode")
pub fn array_decode(
  _raw: Raw,
  _decode: fn(Raw, Int) -> Result(a, e),
  mismatch: e,
) -> Result(List(a), e) {
  Error(mismatch)
}

@external(erlang, "json_blueprint_native_ffi", "number_input")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "number_input")
fn number_input(_raw: Raw) -> NumberInput {
  Other
}

@target(erlang)
@external(erlang, "json_blueprint_native_ffi", "integer")
fn native_integer(_raw: Raw) -> Result(Int, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "floating")
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "floating")
fn native_float(_raw: Raw) -> Result(Float, Nil) {
  Error(Nil)
}

@target(erlang)
/// Exact integer projection retains the codec's 24-digit native contract.
pub fn int(raw: Raw) -> Result(Int, NumericError) {
  case number_input(raw) {
    Other -> Error(NotNumber)
    Integer(_) ->
      native_integer(raw) |> result.map_error(fn(_) { Unrepresentable })
    Decimal(token) -> {
      use exact <- result.try(
        number.from_json_token(token)
        |> result.map_error(fn(_) { Unrepresentable }),
      )
      number.to_int(exact, 24) |> result.map_error(fn(_) { Unrepresentable })
    }
  }
}

// Only pure numeric projection is protected, never callbacks.
@target(javascript)
@external(javascript, "../../../json_blueprint_native_ffi.mjs", "with_projection_capacity")
fn with_projection_capacity(
  work: fn() -> Result(a, NumericError),
  _refusal: NumericError,
) -> Result(a, NumericError) {
  work()
}

@target(javascript)
pub fn int(raw: Raw) -> Result(Int, NumericError) {
  with_projection_capacity(
    fn() {
      case number_input(raw) {
        Other -> Error(NotNumber)
        Integer(value) -> Ok(value)
        Decimal(token) -> {
          use exact <- result.try(
            number.from_json_token(token)
            |> result.map_error(fn(_) { Unrepresentable }),
          )
          number.to_int(exact, 24)
          |> result.map_error(fn(_) { Unrepresentable })
        }
      }
    },
    ProjectionCapacity,
  )
}

/// Float projection deliberately rounds, rejecting values beyond its range.
/// Mathematical zero is normalized; signed underflow of nonzero values is
/// retained to agree with the exact number kernel's rounded projection.
pub fn float(raw: Raw) -> Result(Float, NumericError) {
  case number_input(raw) {
    Other -> Error(NotNumber)
    Integer(_) | Decimal(_) ->
      native_float(raw) |> result.map_error(fn(_) { Unrepresentable })
  }
}

@target(erlang)
/// Build an exact Number only when a codec or a Value fallback requests one.
/// The native parser has already validated the token's JSON grammar.
pub fn number(raw: Raw) -> Result(number.Number, NumericError) {
  case number_input(raw) {
    Integer(value) ->
      number.from_int(value) |> result.map_error(fn(_) { Unrepresentable })
    Decimal(token) ->
      number.from_json_token(token)
      |> result.map_error(fn(_) { Unrepresentable })
    Other -> Error(NotNumber)
  }
}

@target(javascript)
pub fn number(raw: Raw) -> Result(number.Number, NumericError) {
  with_projection_capacity(
    fn() {
      case number_input(raw) {
        Integer(value) ->
          number.from_int(value) |> result.map_error(fn(_) { Unrepresentable })
        Decimal(token) ->
          number.from_json_token(token)
          |> result.map_error(fn(_) { Unrepresentable })
        Other -> Error(NotNumber)
      }
    },
    ProjectionCapacity,
  )
}
