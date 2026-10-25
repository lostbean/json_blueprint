//// Native JSON parsing and checked access to its internal values.
////
//// Erlang keeps exact native integers and decimal source tokens until a
//// numeric projection is requested. Parsing rejects duplicate object keys
//// and applies only the caller's byte bound. Callers choose their own limits
//// for already-decoded structure. JavaScript callers use the portable parser.

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
  InvalidUnicodeScalar
  UnsupportedRuntime
}

pub type NumericError {
  NotNumber
  Unrepresentable
}

pub type Kind {
  Null
  Bool
  String
  Number
  Array
  Object
}

type NumberInput {
  Integer(Int)
  Decimal(String)
  Other
}

@target(erlang)
pub fn supported() -> Bool {
  True
}

@target(javascript)
pub fn supported() -> Bool {
  False
}

@external(erlang, "json_blueprint_native_ffi", "parse")
fn parse_native(_source: String) -> Result(Raw, ParseError) {
  Error(UnsupportedRuntime)
}

/// The byte check occurs before native parsing and tree allocation.
/// Full syntax admission finishes before any typed decoder is invoked.
pub fn parse(source: String, max_bytes: Int) -> Result(Raw, ParseError) {
  case text.exceeds_byte_limit(source, max_bytes) {
    True -> Error(ByteLimitExceeded)
    False -> {
      use _ <- result.try(
        text.validate_scalars(source)
        |> result.map_error(fn(_) { InvalidUnicodeScalar }),
      )
      parse_native(source)
    }
  }
}

@external(erlang, "json_blueprint_native_ffi", "kind")
pub fn kind(_raw: Raw) -> Kind {
  panic as "Native JSON is unavailable on this target"
}

@external(erlang, "json_blueprint_native_ffi", "string")
pub fn string(_raw: Raw) -> Result(String, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "boolean")
pub fn bool(_raw: Raw) -> Result(Bool, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "is_null")
pub fn is_null(_raw: Raw) -> Bool {
  False
}

@external(erlang, "json_blueprint_native_ffi", "keys")
pub fn keys(_raw: Raw) -> Result(List(String), Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "field")
pub fn field(_raw: Raw, _name: String) -> Result(Raw, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "array_items")
pub fn array_items(_raw: Raw) -> Result(List(Raw), Nil) {
  Error(Nil)
}

/// Decode an array without constructing a second untyped list. The callback
/// is invoked in array order and stops at the first typed failure.
@external(erlang, "json_blueprint_native_ffi", "array_decode")
pub fn array_decode(
  _raw: Raw,
  _decode: fn(Raw, Int) -> Result(a, e),
  mismatch: e,
) -> Result(List(a), e) {
  Error(mismatch)
}

@external(erlang, "json_blueprint_native_ffi", "number_input")
fn number_input(_raw: Raw) -> NumberInput {
  Other
}

@target(erlang)
@external(erlang, "json_blueprint_native_ffi", "integer")
fn native_integer(_raw: Raw) -> Result(Int, Nil) {
  Error(Nil)
}

@external(erlang, "json_blueprint_native_ffi", "floating")
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

@target(javascript)
pub fn int(_raw: Raw) -> Result(Int, NumericError) {
  Error(NotNumber)
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
pub fn number(_raw: Raw) -> Result(number.Number, NumericError) {
  Error(NotNumber)
}
