//// THROWAWAY: native parse followed by typed decoding without a Value tree.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string as strings
import json/blueprint/codec
import json/blueprint/internal/text

pub type Decoder(a) =
  fn(Dynamic) -> Result(a, codec.DecodeError)

pub type Error {
  NativeSyntax(json.DecodeError)
  Typed(codec.DecodeError)
  ByteLimitExceeded
  InvalidUnicodeScalar
}

@external(erlang, "native_direct_ffi", "keys")
@external(javascript, "./native_direct_ffi.mjs", "keys")
fn keys(raw: Dynamic) -> Result(List(String), Nil)

@external(erlang, "native_direct_ffi", "field")
@external(javascript, "./native_direct_ffi.mjs", "field")
fn field(raw: Dynamic, name: String) -> Result(Dynamic, Nil)

@external(erlang, "native_direct_ffi", "integer")
@external(javascript, "./native_direct_ffi.mjs", "integer")
fn integer(raw: Dynamic) -> Result(Int, Nil)

@external(erlang, "native_direct_ffi", "floating")
@external(javascript, "./native_direct_ffi.mjs", "floating")
fn floating(raw: Dynamic) -> Result(Float, Nil)

@external(erlang, "native_direct_ffi", "numeric")
@external(javascript, "./native_direct_ffi.mjs", "numeric")
fn numeric(raw: Dynamic) -> Bool

@external(erlang, "native_direct_ffi", "is_null")
@external(javascript, "./native_direct_ffi.mjs", "is_null")
fn is_null(raw: Dynamic) -> Bool

@external(erlang, "native_direct_ffi", "array_decode")
@external(javascript, "./native_direct_ffi.mjs", "array_decode")
fn array_decode(
  raw: Dynamic,
  inner: fn(Dynamic, Int) -> Result(a, codec.DecodeError),
  mismatch: codec.DecodeError,
) -> Result(List(a), codec.DecodeError)

fn fail(reason: codec.Reason) -> codec.DecodeError {
  codec.DecodeError([], reason)
}

fn at(
  x: Result(a, codec.DecodeError),
  part: codec.PathSegment,
) -> Result(a, codec.DecodeError) {
  result.map_error(x, fn(e) { codec.DecodeError([part, ..e.path], e.reason) })
}

pub fn int() -> Decoder(Int) {
  fn(raw) {
    integer(raw) |> result.map_error(fn(_) { fail(codec.ExpectedInt) })
  }
}

pub fn float() -> Decoder(Float) {
  fn(raw) {
    floating(raw)
    |> result.map_error(fn(_) {
      fail(case numeric(raw) {
        True -> codec.FloatOutOfRange
        False -> codec.ExpectedNumber
      })
    })
  }
}

pub fn string() -> Decoder(String) {
  fn(raw) {
    decode.run(raw, decode.string)
    |> result.map_error(fn(_) { fail(codec.ExpectedString) })
  }
}

pub fn bool() -> Decoder(Bool) {
  fn(raw) {
    decode.run(raw, decode.bool)
    |> result.map_error(fn(_) { fail(codec.ExpectedBool) })
  }
}

pub fn list(inner: Decoder(a)) -> Decoder(List(a)) {
  fn(raw) {
    array_decode(
      raw,
      fn(x, i) { at(inner(x), codec.Index(i)) },
      fail(codec.ExpectedArray),
    )
  }
}

pub fn nullable(inner: Decoder(a)) -> Decoder(Option(a)) {
  fn(raw) {
    case is_null(raw) {
      True -> Ok(None)
      False -> result.map(inner(raw), Some)
    }
  }
}

fn member(
  raw: Dynamic,
  name: String,
  decoder: Decoder(a),
) -> Result(a, codec.DecodeError) {
  case field(raw, name) {
    Error(_) ->
      Error(codec.DecodeError([codec.Field(name)], codec.MissingField))
    Ok(x) -> at(decoder(x), codec.Field(name))
  }
}

fn object(raw: Dynamic) -> Result(List(String), codec.DecodeError) {
  keys(raw) |> result.map_error(fn(_) { fail(codec.ExpectedObject) })
}

fn closed(
  keys: List(String),
  allowed: List(String),
) -> Result(Nil, codec.DecodeError) {
  case list.find(keys, fn(k) { !list.contains(allowed, k) }) {
    Ok(k) -> Error(codec.DecodeError([codec.Field(k)], codec.UnknownField))
    Error(_) -> Ok(Nil)
  }
}

pub fn record3() -> Decoder(#(Int, String, Bool)) {
  fn(raw) {
    use names <- result.try(object(raw))
    use id <- result.try(member(raw, "id", int()))
    use name <- result.try(member(raw, "name", string()))
    use active <- result.try(member(raw, "active", bool()))
    use _ <- result.map(closed(names, ["id", "name", "active"]))
    #(id, name, active)
  }
}

pub fn response() -> Decoder(List(#(Int, String, Bool))) {
  fn(raw) {
    use names <- result.try(object(raw))
    use items <- result.try(member(raw, "items", list(record3())))
    use _ <- result.map(closed(names, ["items"]))
    items
  }
}

pub fn optional_record() -> Decoder(Option(Option(String))) {
  fn(raw) {
    use names <- result.try(object(raw))
    use x <- result.try(case field(raw, "note") {
      Error(_) -> Ok(None)
      Ok(x) ->
        at(nullable(string())(x), codec.Field("note")) |> result.map(Some)
    })
    use _ <- result.map(closed(names, ["note"]))
    x
  }
}

pub fn decode_json(source: String, decoder: Decoder(a)) -> Result(a, Error) {
  case text.exceeds_byte_limit(source, 1_048_576) {
    True -> Error(ByteLimitExceeded)
    False -> {
      // Keep malformed raw host strings out before the native parser runs.
      use _ <- result.try(
        text.validate_scalars(source)
        |> result.map_error(fn(_) { InvalidUnicodeScalar }),
      )
      use raw <- result.try(
        json.parse(source, decode.dynamic) |> result.map_error(NativeSyntax),
      )
      decoder(raw) |> result.map_error(Typed)
    }
  }
}

pub fn check() -> Nil {
  let assert Ok(#(42, "Ada", True)) =
    decode_json("{\"active\":true,\"name\":\"Ada\",\"id\":42}", record3())
  let assert Error(Typed(codec.DecodeError(
    [codec.Field("id")],
    codec.MissingField,
  ))) = decode_json("{}", record3())
  let assert Error(Typed(codec.DecodeError(
    [codec.Field("extra")],
    codec.UnknownField,
  ))) =
    decode_json(
      "{\"id\":1,\"name\":\"A\",\"active\":true,\"extra\":0}",
      record3(),
    )
  let assert Ok(None) = decode_json("{}", optional_record())
  let assert Ok(Some(None)) = decode_json("{\"note\":null}", optional_record())
  let assert Ok(Some(Some("yes"))) =
    decode_json("{\"note\":\"yes\"}", optional_record())
  let assert Ok([1, 2]) = decode_json("[1,2]", list(int()))
  let assert Error(Typed(codec.DecodeError([codec.Index(1)], codec.ExpectedInt))) =
    decode_json("[1,false,3]", list(int()))
  let assert Ok(duplicate_winner) =
    decode_json("{\"note\":1,\"note\":2}", fn(raw) {
      member(raw, "note", int())
    })
  let assert True = duplicate_winner == duplicate_expected()
  let assert Error(NativeSyntax(_)) = decode_json("[false,?]", list(int()))
  let assert Ok(1) = decode_json("1.0", int())
  let assert Ok(1) = decode_json("1e0", int())
  // Native rounding makes this non-integral lexeme indistinguishable from 1.
  let assert Ok(1) = decode_json("1.00000000000000001", int())
  let assert Ok(Nil) =
    decode_json(
      strings.repeat("[", 65) <> "0" <> strings.repeat("]", 65),
      fn(_) { Ok(Nil) },
    )
  let assert Ok(Nil) =
    decode_json("[" <> strings.repeat("0,", 262_143) <> "0]", fn(_) { Ok(Nil) })
  let assert Error(ByteLimitExceeded) =
    decode_json(strings.repeat(" ", 1_048_577), int())
  // Native parsing has neither the strict numeric-token nor exponent bound.
  let assert Ok(0.0) = decode_json("0." <> strings.repeat("0", 1024), float())
  let assert Ok(0.0) = decode_json("1e-1201", float())
  let unknown = "{\"id\":1,\"name\":\"A\",\"active\":true,\"z\":0,\"a\":0}"
  let assert Error(Typed(codec.DecodeError(
    [codec.Field(unknown_name)],
    codec.UnknownField,
  ))) = decode_json(unknown, record3())
  let assert True = unknown_name == first_unknown()
  platform_check()
  Nil
}

@target(erlang)
fn duplicate_expected() -> Int {
  1
}

@target(javascript)
fn duplicate_expected() -> Int {
  2
}

@target(erlang)
fn platform_check() -> Nil {
  let assert Error(NativeSyntax(_)) = decode_json("\"\\ud800\"", string())
  let assert Ok(9_007_199_254_740_993) = decode_json("9007199254740993", int())
  let assert Error(NativeSyntax(_)) = decode_json("1e400", float())
  Nil
}

@target(javascript)
fn platform_check() -> Nil {
  let assert Ok(lone) = decode_json("\"\\ud800\"", string())
  let assert True = lone == utf16_unit(0xD800)
  let assert Error(InvalidUnicodeScalar) =
    decode_json("\"" <> utf16_unit(0xD800) <> "\"", string())
  let assert Error(Typed(codec.DecodeError([], codec.ExpectedInt))) =
    decode_json("9007199254740993", int())
  let assert Error(Typed(codec.DecodeError([], codec.FloatOutOfRange))) =
    decode_json("1e400", float())
  Nil
}

@target(erlang)
fn first_unknown() -> String {
  "a"
}

@target(javascript)
fn first_unknown() -> String {
  "z"
}

@target(javascript)
@external(javascript, "./host_string_test_ffi.mjs", "utf16_unit")
fn utf16_unit(unit: Int) -> String
