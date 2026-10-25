//// THROWAWAY: OTP native parsing with duplicate rejection and deferred exact numeric projection.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string as strings
import json/blueprint/codec
import json/blueprint/internal/text
import json/blueprint/number
import json/blueprint/value
import native_direct

pub type Decoder(a) =
  fn(Dynamic) -> Result(a, codec.DecodeError)

pub type Error {
  NativeSyntax(String)
  DuplicateKey(String)
  Numeric(number.NumberError)
  UnsupportedRuntime
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

type NumberInput {
  Integer(Int)
  Decimal(String)
  NotNumber
}

@external(erlang, "native_lossless_ffi", "number_input")
fn number_input(_raw: Dynamic) -> NumberInput {
  NotNumber
}

@external(erlang, "native_lossless_ffi", "native_float")
fn native_float(_raw: Dynamic) -> Result(Float, Nil) {
  Error(Nil)
}

@external(erlang, "native_lossless_ffi", "parse")
fn parse_native(_source: String) -> Result(Dynamic, Error) {
  Error(UnsupportedRuntime)
}

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
    case number_input(raw) {
      Integer(_) -> native_direct.int()(raw)
      Decimal(token) -> {
        use n <- result.try(
          number.parse(token, number.default_limits())
          |> result.map_error(fn(_) { fail(codec.ExpectedInt) }),
        )
        number.to_int(n, 24)
        |> result.map_error(fn(_) { fail(codec.ExpectedInt) })
      }
      NotNumber -> Error(fail(codec.ExpectedInt))
    }
  }
}

pub fn float() -> Decoder(Float) {
  fn(raw) {
    case number_input(raw) {
      NotNumber -> Error(fail(codec.ExpectedNumber))
      _ ->
        native_float(raw)
        |> result.map_error(fn(_) { fail(codec.FloatOutOfRange) })
    }
  }
}

pub fn number() -> Decoder(number.Number) {
  fn(raw) {
    case number_input(raw) {
      Integer(i) ->
        number.from_int(i)
        |> result.map_error(fn(_) { fail(codec.ExpectedNumber) })
      Decimal(token) ->
        number.parse(token, number.default_limits())
        |> result.map_error(fn(_) { fail(codec.ExpectedNumber) })
      NotNumber -> Error(fail(codec.ExpectedNumber))
    }
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
      use _ <- result.try(
        text.validate_scalars(source)
        |> result.map_error(fn(_) { InvalidUnicodeScalar }),
      )
      use raw <- result.try(parse_native(source))
      decoder(raw) |> result.map_error(Typed)
    }
  }
}

@target(erlang)
pub fn check() -> Nil {
  let assert Ok(#(42, "Ada", True)) =
    decode_json("{\"id\":42,\"name\":\"Ada\",\"active\":true}", record3())
  list.each(
    [
      "{\"a\":1,\"a\":2}",
      "{\"a\":1,\"\\u0061\":2}",
      "{\"a\":0.1,\"a\":2}",
      "[0.1,{\"a\":1,\"a\":2}]",
    ],
    fn(source) {
      let assert Error(DuplicateKey("a")) =
        decode_json(source, fn(_) { Ok(Nil) })
    },
  )
  let assert Ok(1) = decode_json("1.0", int())
  let assert Ok(1) = decode_json("1e0", int())
  let assert Error(Typed(codec.DecodeError([], codec.ExpectedInt))) =
    decode_json("1.00000000000000001", int())
  let assert Ok(9_007_199_254_740_993) = decode_json("9007199254740993", int())
  let assert Ok(exact) =
    number.parse("0.10000000000000001", number.default_limits())
  let assert Ok(actual) = decode_json("0.10000000000000001", number())
  let assert True = exact == actual
  let assert Error(Typed(codec.DecodeError([], codec.FloatOutOfRange))) =
    decode_json("1e400", float())
  // Normalize true zero while preserving signed underflow of nonzero values.
  list.each(["-0.0", "-0.000e999", "-1e-400", "-0.0001e-400"], fn(source) {
    let assert Ok(expected) = codec.decode_json(codec.float(), source)
    let assert Ok(actual) = decode_json(source, float())
    let assert True = expected == actual
  })
  let assert Ok(0.0) = decode_json("-0.0e999999999999999999999999", float())
  // Float is explicitly lossy; native underflow returns zero.
  let assert Ok(0.0) = decode_json("1e-1201", float())
  // No global number token limits on this path.
  let long = "0." <> strings.repeat("0", 1024)
  let assert Ok(0.0) = decode_json(long, float())
  let assert Ok(Nil) = decode_json(long, fn(_) { Ok(Nil) })
  let assert Error(value.ParseError(_, value.InvalidNumber(_))) =
    value.parse(long, value.default_limits())
  let assert Error(NativeSyntax(_)) = decode_json("1 trailing", int())
  let assert Error(NativeSyntax(_)) = decode_json("\"\\ud800\"", string())
  let assert Error(NativeSyntax(_)) =
    decode_json("[{\"a\":1,\"a\":2},?]", fn(_) {
      panic as "callback must not run"
    })
  let assert Error(NativeSyntax(_)) =
    decode_json("{\"a\":1,\"a\":?}", fn(_) { Ok(Nil) })
  let assert Ok(None) = decode_json("{}", optional_record())
  let assert Ok(Some(None)) = decode_json("{\"note\":null}", optional_record())
  let assert Ok(Some(Some("yes"))) =
    decode_json("{\"note\":\"yes\"}", optional_record())
  let assert Error(ByteLimitExceeded) =
    decode_json(strings.repeat(" ", 1_048_577), int())
  let assert Ok(Nil) =
    decode_json(
      strings.repeat("[", 65) <> "0" <> strings.repeat("]", 65),
      fn(_) { Ok(Nil) },
    )
  Nil
}

@target(javascript)
pub fn check() -> Nil {
  let _ = value.default_limits()
  let _ = strings.length("")
  Nil
}
