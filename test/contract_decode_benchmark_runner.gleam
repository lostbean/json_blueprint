//// Decoding observations only: `contract.decode` against a function prepared
//// once with `contract.decoder`. Run with
//// `gleam run -m contract_decode_benchmark_runner --target erlang|javascript`.
//// Each row prints the median and range of seven timed batches.

import gleam/int
import gleam/io
import gleam/list
import gleam/result
import json/blueprint/codec.{type Codec}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value.{type Value}

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
fn monotonic_nanos() -> Int

@external(erlang, "bench_ffi", "target_runtime")
@external(javascript, "./bench_ffi.mjs", "target_runtime")
fn target_runtime() -> String

@external(erlang, "bench_ffi", "consume")
@external(javascript, "./bench_ffi.mjs", "consume")
fn consume(item: a) -> Nil

const batch = 2000

fn person_codec() -> Codec(#(String, Int)) {
  use name <- codec.field("name", codec.string(), get: fn(p: #(String, Int)) {
    p.0
  })
  use age <- codec.field("age", codec.int(), get: fn(p: #(String, Int)) { p.1 })
  codec.success(#(name, age))
}

fn labels(count: Int) -> List(#(String, Int)) {
  int.range(from: 0, to: count, with: [], run: fn(done, index) {
    [#("label-" <> int.to_string(index), index), ..done]
  })
}

fn int_value(item: Int) -> Value {
  let assert Ok(parsed) = number.from_int(item)
  value.Number(parsed)
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

fn observe(name: String, work: fn() -> Nil) -> Nil {
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
    <> int.to_string(median)
    <> " ns (range "
    <> int.to_string(low)
    <> " to "
    <> int.to_string(high)
    <> ")",
  )
}

fn compare(name: String, item_codec: Codec(a), item: Value) -> Nil {
  let assert Ok(accepted) = contract.from_codec(item_codec)
  let assert Ok(validated) = contract.validate(accepted, item)
  let assert Ok(prepared) = contract.decoder(item_codec, for: accepted)
  observe(name <> ", contract.decode", fn() {
    let outcome = contract.decode(item_codec, validated)
    let assert True = result.is_ok(outcome)
    consume(outcome)
  })
  observe(name <> ", prepared decoder", fn() {
    let outcome = prepared(validated)
    let assert True = result.is_ok(outcome)
    consume(outcome)
  })
  observe(name <> ", codec.decode alone", fn() {
    let outcome = codec.decode(item_codec, item)
    let assert True = result.is_ok(outcome)
    consume(outcome)
  })
}

pub fn main() -> Nil {
  io.println("decoding a validated value on " <> target_runtime())
  compare(
    "two-field record",
    person_codec(),
    value.Object([#("name", value.String("Ada")), #("age", int_value(36))]),
  )
  compare(
    "list of 20 two-field records",
    codec.list(person_codec()),
    value.Array(list.repeat(
      value.Object([#("name", value.String("Ada")), #("age", int_value(36))]),
      20,
    )),
  )
  compare(
    "enum of 200 labels",
    codec.string_enum(labels(200)),
    value.String("label-100"),
  )
}
