//// Admission observations only: strict native parsing with and without the
//// optional nesting-depth and value-count bounds.
//// Run with `gleam run -m limit_benchmark_runner --target erlang|javascript`.
//// Each row prints the median and range of seven timed batches.

import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
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

const batch = 5

fn records(count: Int) -> String {
  let record =
    "{\"id\":1234,\"name\":\"a name\",\"tags\":[\"x\",\"y\"],\"ok\":true}"
  "[" <> string.join(list.repeat(record, count), ",") <> "]"
}

fn integers(count: Int) -> String {
  "[" <> string.join(list.repeat("1", count), ",") <> "]"
}

fn chains(count: Int, depth: Int) -> String {
  let chain = string.repeat("[", depth) <> "0" <> string.repeat("]", depth)
  "[" <> string.join(list.repeat(chain, count), ",") <> "]"
}

fn repeat(count: Int, work: fn() -> Nil) -> Nil {
  case count {
    0 -> Nil
    _ -> {
      work()
      repeat(count - 1, work)
    }
  }
}

fn timed(work: fn() -> Nil) -> Int {
  let start = monotonic_nanos()
  repeat(batch, work)
  { monotonic_nanos() - start } / batch
}

fn observe(name: String, source: String, limits: value.Limits) -> Nil {
  let work = fn() {
    let outcome = value.parse_native(source, limits)
    let assert True = result.is_ok(outcome)
    consume(outcome)
  }
  // One untimed batch first.
  let _ = timed(work)
  let runs =
    list.repeat(Nil, 7)
    |> list.map(fn(_) { timed(work) })
    |> list.sort(int.compare)
  let assert [low, _, _, median, _, _, high] = runs
  io.println(
    name
    <> ": median "
    <> int.to_string(median / 1000)
    <> " µs (range "
    <> int.to_string(low / 1000)
    <> " to "
    <> int.to_string(high / 1000)
    <> ")",
  )
}

pub fn main() -> Nil {
  io.println("strict native parse on " <> target_runtime())
  let unbounded = value.default_limits()
  let bounded =
    unbounded
    |> value.with_max_depth(128)
    |> value.with_max_values(262_144)
  let documents = [
    #("15,000 records, 1 MiB", records(15_000)),
    #("250,000 integers, 0.5 MiB", integers(250_000)),
    #("2,000 chains nested 100 deep, 0.4 MiB", chains(2000, 100)),
  ]
  list.each(documents, fn(document) {
    let #(name, source) = document
    observe(name <> ", bytes only", source, unbounded)
    observe(name <> ", depth 128 and 262,144 values", source, bounded)
  })
}
