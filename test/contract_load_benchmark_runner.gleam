//// Loading observations only: `contract.load` on deeply nested schema
//// documents. Run with
//// `gleam run -m contract_load_benchmark_runner --target erlang|javascript`.
//// Each row prints the median and range of five timed loads.

import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import json/blueprint/contract
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

/// `{"type":"array","items":…}` nested `depth` times around a string schema.
fn nested_lists(depth: Int, inner: value.Value) -> value.Value {
  case depth {
    0 -> inner
    _ ->
      nested_lists(
        depth - 1,
        value.Object([#("type", value.String("array")), #("items", inner)]),
      )
  }
}

fn document(depth: Int) -> value.Value {
  let assert value.Object(members) =
    nested_lists(depth, value.Object([#("type", value.String("string"))]))
  value.Object([
    #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
    ..members
  ])
}

fn timed(schema: value.Value) -> Int {
  let start = monotonic_nanos()
  let outcome = contract.load(schema)
  let elapsed = monotonic_nanos() - start
  let assert True = result.is_ok(outcome)
  consume(outcome)
  elapsed
}

fn observe(depth: Int) -> Nil {
  let schema = document(depth)
  // One untimed load first, then five timed loads.
  let _ = timed(schema)
  let runs =
    [timed(schema), timed(schema), timed(schema), timed(schema), timed(schema)]
    |> list.sort(int.compare)
  let assert [low, _, median, _, high] = runs
  io.println(
    "list schemas nested "
    <> int.to_string(depth)
    <> " deep: median "
    <> int.to_string(median / 1000)
    <> " µs (range "
    <> int.to_string(low / 1000)
    <> " to "
    <> int.to_string(high / 1000)
    <> ")",
  )
}

pub fn main() -> Nil {
  io.println("contract.load on " <> target_runtime())
  // JavaScript loading recurses on the host stack, so its cases are shallower.
  let depths = case string.starts_with(target_runtime(), "Erlang") {
    True -> [2500, 5000, 10_000, 20_000]
    False -> [125, 250, 500, 1000]
  }
  list.each(depths, observe)
}
