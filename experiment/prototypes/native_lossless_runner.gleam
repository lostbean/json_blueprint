//// THROWAWAY: native direct decoding versus optimized strict typed decoding.

import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import json/blueprint/codec
import native_direct as native
import native_lossless as exact

@external(erlang, "parser_benchmark_ffi", "setting")
@external(javascript, "./parser_benchmark_ffi.mjs", "setting")
fn setting(name: String) -> String

@external(erlang, "parser_benchmark_ffi", "read_text")
@external(javascript, "./parser_benchmark_ffi.mjs", "read_text")
fn read_text(path: String) -> String

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
fn now() -> Int

@external(erlang, "bench_ffi", "consume")
@external(javascript, "./bench_ffi.mjs", "consume")
fn consume(x: a) -> Nil

@external(erlang, "selective_ffi", "snapshot")
@external(javascript, "./selective_ffi.mjs", "snapshot")
fn snapshot() -> String

fn record() -> codec.Codec(#(Int, String, Bool)) {
  use id <- codec.field("id", codec.int(), get: fn(x) { x.0 })
  use name <- codec.field("name", codec.string(), get: fn(x) { x.1 })
  use active <- codec.field("active", codec.bool(), get: fn(x) { x.2 })
  codec.success(#(id, name, active))
}

fn optional() -> codec.Codec(option.Option(option.Option(String))) {
  use note <- codec.optional_field(
    "note",
    codec.nullable(codec.string()),
    get: fn(x) { x },
  )
  codec.success(note)
}

fn repeat(n: Int, work: fn() -> Nil) -> Nil {
  case n {
    0 -> Nil
    _ -> {
      work()
      repeat(n - 1, work)
    }
  }
}

fn bench(c: codec.Codec(a), d: native.Decoder(a), e: exact.Decoder(a)) -> Nil {
  let source = read_text(setting("BLUEPRINT_PARSER_INPUT"))
  let work = case setting("BLUEPRINT_PARSER_BACKEND") {
    "strict" -> fn() {
      let assert Ok(x) = codec.decode_json(c, source)
      consume(x)
    }
    "native" -> fn() {
      let assert Ok(x) = native.decode_json(source, d)
      consume(x)
    }
    _ -> fn() {
      let assert Ok(x) = exact.decode_json(source, e)
      consume(x)
    }
  }
  case setting("BLUEPRINT_PARSER_MODE") {
    "verify" -> {
      let assert Ok(expected) = codec.decode_json(c, source)
      let assert Ok(c) = exact.decode_json(source, e)
      let assert True = expected == c
      case setting("SELECTIVE_CASE") {
        "exact_numbers" -> Nil
        _ -> {
          let assert Ok(a) = native.decode_json(source, d)
          let assert True = expected == a
          Nil
        }
      }
      io.println("true")
    }
    "memory" -> {
      work()
      io.println(snapshot())
    }
    _ -> {
      let assert Ok(n) = int.parse(setting("BLUEPRINT_PARSER_ITERATIONS"))
      repeat(n, work)
      let samples =
        list.map(list.repeat(Nil, 5), fn(_) {
          let start = now()
          repeat(n, work)
          { now() - start } / n
        })
      io.println(json.to_string(json.array(samples, json.int)))
    }
  }
}

fn parity(c: codec.Codec(a), d: native.Decoder(a), source: String) -> Nil {
  let expected = codec.decode_json(c, source)
  let actual = case native.decode_json(source, d) {
    Ok(x) -> Ok(x)
    Error(native.Typed(e)) -> Error(e)
    _ -> panic as "Unexpected native syntax error in typed parity fixture"
  }
  let assert True = expected == actual
  Nil
}

fn typed_checks() -> Nil {
  list.each(
    [
      "{}",
      "null",
      "[]",
      "{\"id\":false}",
      "{\"id\":1,\"name\":2,\"active\":true}",
      "{\"id\":1,\"name\":\"A\",\"active\":true,\"extra\":0}",
    ],
    fn(source) { parity(record(), native.record3(), source) },
  )
  list.each(
    [
      "{}",
      "{\"note\":null}",
      "{\"note\":\"yes\"}",
      "{\"note\":false}",
      "{\"extra\":0}",
    ],
    fn(source) { parity(optional(), native.optional_record(), source) },
  )
  list.each(["[]", "[1,2]", "[false]", "[1,false,2]", "null"], fn(source) {
    parity(codec.list(codec.int()), native.list(native.int()), source)
  })
}

pub fn main() -> Nil {
  case setting("SELECTIVE_CASE") {
    "check" -> {
      native.check()
      typed_checks()
      let _ = exact.check()
      io.println("{\"correctness\":true}")
    }
    "record" -> bench(record(), native.record3(), exact.record3())
    "records" ->
      bench(
        codec.list(record()),
        native.list(native.record3()),
        exact.list(exact.record3()),
      )
    "response" -> {
      let c = {
        use items <- codec.field("items", codec.list(record()), get: fn(x) { x })
        codec.success(items)
      }
      bench(c, native.response(), exact.response())
    }
    "nested" ->
      bench(
        codec.list(codec.list(codec.int())),
        native.list(native.list(native.int())),
        exact.list(exact.list(exact.int())),
      )
    "exact_numbers" ->
      bench(
        codec.list(codec.number()),
        fn(_) { panic as "No precision-preserving plain native comparator" },
        exact.list(exact.number()),
      )
    "floats" ->
      bench(
        codec.list(codec.float()),
        native.list(native.float()),
        exact.list(exact.float()),
      )
    "strings" ->
      bench(
        codec.list(codec.string()),
        native.list(native.string()),
        exact.list(exact.string()),
      )
    "optional" ->
      bench(
        codec.list(optional()),
        native.list(native.optional_record()),
        exact.list(exact.optional_record()),
      )
    _ ->
      bench(
        codec.list(codec.int()),
        native.list(native.int()),
        exact.list(exact.int()),
      )
  }
}
