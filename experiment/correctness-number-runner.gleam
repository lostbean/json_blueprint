//// Disposable benchmark of public standalone number.parse.

import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import json/blueprint/codec
import json/blueprint/number

@external(erlang, "parser_benchmark_ffi", "setting")
@external(javascript, "./parser_benchmark_ffi.mjs", "setting")
fn setting(name: String) -> String

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
fn now() -> Int

@external(erlang, "bench_ffi", "consume")
@external(javascript, "./bench_ffi.mjs", "consume")
fn consume(value: a) -> Nil

fn repeat(count: Int, work: fn() -> Nil) -> Nil {
  case count {
    0 -> Nil
    _ -> {
      work()
      repeat(count - 1, work)
    }
  }
}

fn bench(iterations: Int, work: fn() -> Nil) -> Nil {
  repeat(iterations, work)
  let samples =
    list.map(list.repeat(Nil, 5), fn(_) {
      let start = now()
      repeat(iterations, work)
      { now() - start } / iterations
    })
  io.println(json.to_string(json.array(samples, json.int)))
}

fn fields(index: Int, width: Int, values: List(Int)) -> codec.Codec(List(Int)) {
  case index == width {
    True -> codec.success(list.reverse(values))
    False -> {
      use item <- codec.field(
        "f" <> int.to_string(index),
        codec.int(),
        get: fn(record) {
          list.drop(record, index) |> list.first |> result.unwrap(0)
        },
      )
      fields(index + 1, width, [item, ..values])
    }
  }
}

fn record(width: Int) -> Nil {
  let source =
    list.repeat(Nil, width)
    |> list.index_map(fn(_, index) {
      #("f" <> int.to_string(index), json.int(index))
    })
    |> json.object
    |> json.to_string
  let definition = fields(0, width, [])
  case setting("NUMBER_MODE") {
    "result" -> {
      let assert Ok(parsed) = codec.decode_json(definition, source)
      let assert Ok(encoded) = codec.encode_json(definition, parsed)
      io.println(json.to_string(json.string("Ok:" <> encoded)))
    }
    _ -> bench(500, fn() { consume(codec.decode_json(definition, source)) })
  }
}

fn numeric() -> Nil {
  let token = setting("NUMBER_TOKEN")
  let limits = case setting("NUMBER_LIMITS") {
    "large" -> number.limits(100, 100, 9_007_199_254_740_991)
    _ -> number.default_limits()
  }
  case setting("NUMBER_MODE") {
    "result" -> {
      let result = case number.parse(token, limits) {
        Ok(parsed) -> "Ok:" <> number.to_string(parsed)
        Error(number.ExponentOutOfRange) -> "Error:ExponentOutOfRange"
        Error(_) -> panic as "Unexpected parse failure"
      }
      io.println(json.to_string(json.string(result)))
    }
    _ -> bench(5000, fn() { consume(number.parse(token, limits)) })
  }
}

pub fn main() {
  case setting("NUMBER_TOKEN") {
    "record_20" -> record(20)
    "record_100" -> record(100)
    _ -> numeric()
  }
}
