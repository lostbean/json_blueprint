// THROWAWAY: matched complete typed decoding and one-operation process RSS.
import generated/order_codec
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import json/blueprint/codec
import materialize_fixtures
import vanilla_order

@external(erlang, "parser_benchmark_ffi", "setting")
@external(javascript, "./parser_benchmark_ffi.mjs", "setting")
fn setting(name: String) -> String

@external(erlang, "parser_benchmark_ffi", "read_text")
@external(javascript, "./parser_benchmark_ffi.mjs", "read_text")
fn read_text(path: String) -> String

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
fn monotonic_nanos() -> Int

@external(erlang, "bench_ffi", "consume")
@external(javascript, "./bench_ffi.mjs", "consume")
fn consume(item: a) -> Nil

fn repeat(count: Int, work: fn() -> Nil) -> Nil {
  case count {
    0 -> Nil
    _ -> {
      work()
      repeat(count - 1, work)
    }
  }
}

pub fn main() -> Nil {
  let source = read_text(setting("PROTOTYPE_INPUT"))
  let assert Ok(count) = int.parse(setting("PROTOTYPE_COUNT"))
  let decode = case setting("PROTOTYPE_DECODER") {
    "generated" -> {
      let decoder = codec.list(order_codec.order_codec())
      fn() {
        let assert Ok(rows) = codec.decode_json(decoder, source)
        rows
      }
    }
    "runtime" -> {
      let decoder = codec.list(materialize_fixtures.build_order_codec())
      fn() {
        let assert Ok(rows) = codec.decode_json(decoder, source)
        rows
      }
    }
    "vanilla" -> {
      let decoder = decode.list(vanilla_order.decoder())
      fn() {
        let assert Ok(rows) = json.parse(source, decoder)
        rows
      }
    }
    _ -> panic as "unknown decoder"
  }
  let work = fn() {
    let rows = decode()
    let assert True = list.length(rows) == count
    let assert Ok(first) = list.first(rows)
    let assert True = first.order_id == 42
    let assert True = first.items == [#("apple", 2), #("雪", 3)]
    consume(rows)
  }
  case setting("PROTOTYPE_MODE") {
    "memory" -> {
      work()
      io.println("{\"accepted\":true}")
    }
    _ -> {
      let assert Ok(iterations) = int.parse(setting("PROTOTYPE_ITERATIONS"))
      repeat(iterations, work)
      let samples =
        list.map(list.repeat(Nil, 5), fn(_) {
          let start = monotonic_nanos()
          repeat(iterations, work)
          { monotonic_nanos() - start } / iterations
        })
      io.println(
        "{\"samples_ns\":["
        <> string.join(list.map(samples, int.to_string), ",")
        <> "]}",
      )
    }
  }
}
