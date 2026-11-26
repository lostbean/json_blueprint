//// Rendering observations only: `value.to_string` on deep and wide values.
//// Run with `gleam run -m render_benchmark_runner --target erlang|javascript`.
//// Each case prints the median and range of five timed runs.

import gleam/int
import gleam/io
import gleam/list
import gleam/string
import json/blueprint/number
import json/blueprint/value

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
fn monotonic_nanos() -> Int

@external(erlang, "bench_ffi", "target_runtime")
@external(javascript, "./bench_ffi.mjs", "target_runtime")
fn target_runtime() -> String

@external(erlang, "bench_ffi", "consume")
@external(javascript, "./bench_ffi.mjs", "consume")
fn consume(item: a) -> Nil

fn nested(depth: Int, inner: value.Value) -> value.Value {
  case depth {
    0 -> inner
    _ -> nested(depth - 1, value.Array([inner]))
  }
}

fn nested_objects(depth: Int, inner: value.Value) -> value.Value {
  case depth {
    0 -> inner
    _ -> nested_objects(depth - 1, value.Object([#("k", inner)]))
  }
}

fn wide_array(count: Int) -> value.Value {
  let assert Ok(one) = number.from_int(1)
  value.Array(list.repeat(value.Number(one), count))
}

fn wide_object(count: Int) -> value.Value {
  int.range(from: 0, to: count, with: [], run: fn(members, index) {
    [#("member" <> int.to_string(index), value.String("text")), ..members]
  })
  |> value.Object
}

fn timed(item: value.Value) -> Int {
  let start = monotonic_nanos()
  consume(string.byte_size(value.to_string(item)))
  monotonic_nanos() - start
}

fn observe(name: String, item: value.Value) -> Nil {
  // One untimed run first, then five timed runs.
  let _ = timed(item)
  let runs =
    [timed(item), timed(item), timed(item), timed(item), timed(item)]
    |> list.sort(int.compare)
  let assert [low, _, median, _, high] = runs
  io.println(
    name
    <> ": median "
    <> micros(median)
    <> " (range "
    <> micros(low)
    <> " to "
    <> micros(high)
    <> ")",
  )
}

fn micros(nanos: Int) -> String {
  int.to_string(nanos / 1000) <> " µs"
}

pub fn main() -> Nil {
  io.println("value.to_string on " <> target_runtime())
  let runtime_is_erlang = string.starts_with(target_runtime(), "Erlang")
  // JavaScript rendering recurses on the host stack, so its deep cases are
  // shallower than Erlang's.
  let depths = case runtime_is_erlang {
    True -> [12_500, 25_000, 50_000, 100_000]
    False -> [500, 1000, 2000, 4000]
  }
  list.each(depths, fn(depth) {
    observe(
      "nested arrays, depth " <> int.to_string(depth),
      nested(depth, value.Null),
    )
  })
  // Objects stop one doubling earlier: before linear rendering their deepest
  // case alone took minutes.
  list.each(list.take(depths, 3), fn(depth) {
    observe(
      "nested objects, depth " <> int.to_string(depth),
      nested_objects(depth, value.Null),
    )
  })
  observe("array of 250,000 integers", wide_array(250_000))
  observe("object of 50,000 string members", wide_object(50_000))
}
