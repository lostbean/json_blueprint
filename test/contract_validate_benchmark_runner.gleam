//// Validation observations only: `contract.validate` on arrays whose items
//// are checked against a large enum or a large tagged union, with an
//// ordinary record list and a `contract.decode` call as controls. Run with
//// `gleam run -m contract_validate_benchmark_runner --target erlang|javascript`.
//// Each row prints the median and range of five timed runs.

import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import json/blueprint/codec.{type Codec}
import json/blueprint/contract
import json/blueprint/internal/schema_tree as tree
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

/// `count` distinct names of equal length, so the last one sorts last.
fn names(count: Int) -> List(String) {
  int.range(from: 0, to: count, with: [], run: fn(done, index) {
    [
      "name-" <> string.pad_start(int.to_string(index), to: 6, with: "0"),
      ..done
    ]
  })
  |> list.reverse
}

fn last(items: List(String)) -> String {
  let assert Ok(found) = list.last(items)
  found
}

fn contract_of(schema: tree.Tree) -> contract.Contract {
  contract.from_schema(codec.from_tree(schema))
}

fn person_codec() -> Codec(#(String, Int)) {
  use name <- codec.field("name", codec.string(), get: fn(p: #(String, Int)) {
    p.0
  })
  use age <- codec.field("age", codec.int(), get: fn(p: #(String, Int)) { p.1 })
  codec.success(#(name, age))
}

fn person() -> Value {
  let assert Ok(age) = number.from_int(36)
  value.Object([#("name", value.String("Ada")), #("age", value.Number(age))])
}

fn timed(repeats: Int, work: fn() -> Nil) -> Int {
  let start = monotonic_nanos()
  repeat(repeats, work)
  { monotonic_nanos() - start } / repeats
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

fn observe(name: String, repeats: Int, work: fn() -> Nil) -> Nil {
  // One untimed run first, then five timed runs.
  let _ = timed(repeats, work)
  let runs =
    list.repeat(Nil, 5)
    |> list.map(fn(_) { timed(repeats, work) })
    |> list.sort(int.compare)
  let assert [low, _, median, _, high] = runs
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

fn validating(accepted: contract.Contract, item: Value) -> fn() -> Nil {
  fn() {
    let outcome = contract.validate(accepted, item)
    let assert True = result.is_ok(outcome)
    consume(outcome)
  }
}

pub fn main() -> Nil {
  io.println("contract.validate on " <> target_runtime())
  let items = 20_000
  list.each([1000, 2000, 4000, 8000], fn(count) {
    let labels = names(count)
    let accepted = contract_of(tree.ListSchema(tree.StringEnumSchema(labels)))
    let item = value.Array(list.repeat(value.String(last(labels)), items))
    observe(
      "20,000 strings against an enum of " <> int.to_string(count) <> " labels",
      1,
      validating(accepted, item),
    )
  })
  list.each([1000, 2000, 4000, 8000], fn(count) {
    let tags = names(count)
    let accepted =
      contract_of(
        tree.ListSchema(
          tree.UnionSchema(list.map(tags, tree.VariantSchema(_, None))),
        ),
      )
    let tagged = value.Object([#("tag", value.String(last(tags)))])
    observe(
      "20,000 values against a union of " <> int.to_string(count) <> " tags",
      1,
      validating(accepted, value.Array(list.repeat(tagged, items))),
    )
  })
  // Controls: no large enum or union.
  let assert Ok(people) = contract.from_codec(codec.list(person_codec()))
  let crowd = value.Array(list.repeat(person(), items))
  observe("20,000 two-field records", 5, validating(people, crowd))
  let assert Ok(small) =
    contract.from_codec(
      codec.list(codec.string_enum([#("a", 1), #("b", 2), #("c", 3)])),
    )
  observe(
    "20,000 strings against an enum of 3 labels",
    5,
    validating(small, value.Array(list.repeat(value.String("c"), items))),
  )
  let assert Ok(one) = contract.from_codec(person_codec())
  let assert Ok(validated) = contract.validate(one, person())
  let decoding = person_codec()
  observe("1,000 contract.decode calls of a two-field record", 5, fn() {
    repeat(1000, fn() {
      let outcome = contract.decode(decoding, validated)
      let assert True = result.is_ok(outcome)
      consume(outcome)
    })
  })
}
