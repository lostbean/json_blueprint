//// Focused observations for contract.value_codec; no timing is an assertion.

import generated/order_codec
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/contract
import json/blueprint/value
import materialize_fixtures

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
fn monotonic_nanos() -> Int

@external(erlang, "bench_ffi", "consume")
@external(javascript, "./bench_ffi.mjs", "consume")
fn consume(item: a) -> Nil

@external(erlang, "bench_ffi", "consumed_count")
@external(javascript, "./bench_ffi.mjs", "consumed_count")
fn consumed_count() -> Int

type Fixture {
  Fixture(
    name: String,
    schema: contract.Contract,
    item: value.Value,
    iterations: Int,
  )
}

fn from_typed(
  name: String,
  typed: codec.Codec(a),
  item: a,
  iterations: Int,
) -> Fixture {
  let assert Ok(schema) = contract.from_codec(typed)
  let assert Ok(raw) = codec.encode(typed, item)
  Fixture(name, schema, raw, iterations)
}

fn closed_object(properties: List(#(String, value.Value))) -> value.Value {
  value.Object([
    #("type", value.String("object")),
    #("properties", value.Object(properties)),
    #(
      "required",
      value.Array(
        list.map(properties, fn(property) { value.String(property.0) }),
      ),
    ),
    #("additionalProperties", value.Bool(False)),
  ])
}

fn schema_contract(body: value.Value) -> contract.Contract {
  let assert value.Object(properties) = body
  let document =
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
      ..properties
    ])
  let assert Ok(schema) = contract.load(document)
  schema
}

fn wide_object(width: Int) -> Fixture {
  let names = list.map(positions(width), fn(n) { "field_" <> int.to_string(n) })
  let string_schema = value.Object([#("type", value.String("string"))])
  let schema =
    names
    |> list.map(fn(name) { #(name, string_schema) })
    |> closed_object
    |> schema_contract
  let item =
    value.Object(list.map(names, fn(name) { #(name, value.String("x")) }))
  Fixture("object_width_" <> int.to_string(width), schema, item, 100)
}

fn nested_object(depth: Int) -> Fixture {
  let #(schema, item) =
    list.fold(
      positions(depth),
      #(value.Object([#("type", value.String("string"))]), value.String("leaf")),
      fn(pair, _) {
        #(
          closed_object([#("child", pair.0)]),
          value.Object([#("child", pair.1)]),
        )
      },
    )
  Fixture(
    "object_depth_" <> int.to_string(depth),
    schema_contract(schema),
    item,
    1000,
  )
}

fn record_codec() -> codec.Codec(#(String, String, String, String, String, Int)) {
  use a <- codec.field("a", codec.string(), get: fn(item) { item.0 })
  use b <- codec.field("b", codec.string(), get: fn(item) { item.1 })
  use c <- codec.field("c", codec.string(), get: fn(item) { item.2 })
  use d <- codec.field("d", codec.string(), get: fn(item) { item.3 })
  use e <- codec.field("e", codec.string(), get: fn(item) { item.4 })
  use count <- codec.field("count", codec.integer_between(1, 10), get: fn(item) {
    item.5
  })
  codec.success(#(a, b, c, d, e, count))
}

fn record() -> #(String, String, String, String, String, Int) {
  #("alpha", "beta", "gamma", "delta", "epsilon", 3)
}

fn order() -> materialize_fixtures.Order {
  materialize_fixtures.Order(
    42,
    [#("widget", 2), #("雪 🚀", 7)],
    Some(Some("leave at door")),
    True,
    materialize_fixtures.ShippedQuoted,
  )
}

fn fixtures() -> List(Fixture) {
  let arrays =
    list.flat_map([10, 1000, 10_000], fn(size) {
      let items = list.repeat(3, size)
      let iterations = case size {
        10 -> 5000
        _ -> 100
      }
      [
        from_typed(
          "int_array_" <> int.to_string(size),
          codec.list(codec.int()),
          items,
          iterations,
        ),
        from_typed(
          "bounded_array_" <> int.to_string(size),
          codec.list(codec.integer_between(1, 10)),
          items,
          iterations,
        ),
      ]
    })
  list.append(
    [
      from_typed("int", codec.int(), 3, 100_000),
      from_typed("string", codec.string(), "hello", 100_000),
      from_typed("bounded_int", codec.integer_between(1, 10), 3, 100_000),
      from_typed("record_6_fields", record_codec(), record(), 5000),
      nested_object(8),
      wide_object(10),
      wide_object(100),
      wide_object(500),
      from_typed(
        "records_1000_sparse_bounds",
        codec.list(record_codec()),
        list.repeat(record(), 1000),
        100,
      ),
      from_typed(
        "any_array_10000",
        codec.value(),
        value.Array(list.repeat(value.String("x"), 10_000)),
        100,
      ),
      from_typed(
        "order",
        codegen.runtime(materialize_fixtures.order_definition()),
        order(),
        5000,
      ),
    ],
    arrays,
  )
}

pub fn fixtures_are_valid_and_preserved_test() {
  list.each(fixtures(), fn(fixture) {
    let assert Ok(validated) = contract.validate(fixture.schema, fixture.item)
    contract.value(validated) |> should.equal(fixture.item)
    let adapted = contract.value_codec(fixture.schema)
    codec.decode(adapted, fixture.item) |> should.equal(Ok(fixture.item))
    codec.encode(adapted, fixture.item) |> should.equal(Ok(fixture.item))
    codec.encode_json(adapted, fixture.item)
    |> should.equal(Ok(value.to_string(fixture.item)))
  })
}

pub fn native_and_generated_controls_agree_test() {
  let typed = codegen.runtime(materialize_fixtures.order_definition())
  let generated = order_codec.order_codec()
  codec.encode(typed, order())
  |> should.equal(order_codec.encode_order(order()))
  codec.encode_json(typed, order())
  |> should.equal(order_codec.encode_order_json(order()))
  codec.encode(generated, order()) |> should.equal(codec.encode(typed, order()))
  codec.encode_json(generated, order())
  |> should.equal(codec.encode_json(typed, order()))
}

fn invalid_fixture(late: Bool) -> Fixture {
  let assert Ok(schema) =
    contract.from_codec(codec.list(codec.integer_between(1, 10)))
  let assert Ok(valid) = codec.encode(codec.int(), 3)
  let assert Ok(invalid) = codec.encode(codec.int(), 99)
  let tail = list.repeat(valid, 999)
  let #(name, items) = case late {
    True -> #("invalid_bound_last_1000", list.append(tail, [invalid]))
    False -> #("invalid_bound_first_1000", [invalid, ..tail])
  }
  Fixture(name, schema, value.Array(items), 100)
}

pub fn invalid_fixtures_locate_the_failed_bound_test() {
  list.each([#(False, 0), #(True, 999)], fn(case_) {
    let fixture = invalid_fixture(case_.0)
    contract.validate(fixture.schema, fixture.item)
    |> should.equal(
      Error(contract.ValidationError(
        [codec.Index(case_.1)],
        codec.IntegerOutsideRange(1, 10),
      )),
    )
  })
}

fn run_n_times(remaining: Int, work: fn() -> Nil) -> Nil {
  case remaining <= 0 {
    True -> Nil
    False -> {
      work()
      run_n_times(remaining - 1, work)
    }
  }
}

fn observe(
  name: String,
  operation: String,
  iterations: Int,
  outcome: String,
  work: fn() -> Nil,
) {
  // Construction, semantic checks, and warmup are outside every timed batch.
  let warmup = int.min(iterations, 1000)
  run_n_times(warmup, work)
  list.each(positions(7), fn(batch) {
    let start = monotonic_nanos()
    run_n_times(iterations, work)
    let elapsed = monotonic_nanos() - start
    io.println(
      json.to_string(
        json.object([
          #("case", json.string(name)),
          #("operation", json.string(operation)),
          #("outcome", json.string(outcome)),
          #("batch", json.int(batch)),
          #("warmup", json.int(warmup)),
          #("iterations", json.int(iterations)),
          #("elapsed_ns", json.int(elapsed)),
        ]),
      ),
    )
  })
}

fn dynamic(fixture: Fixture) {
  let adapted = contract.value_codec(fixture.schema)
  let outcome = case codec.encode(adapted, fixture.item) {
    Ok(_) -> "ok"
    Error(_) -> "error"
  }
  observe(fixture.name, "encode", fixture.iterations, outcome, fn() {
    consume(codec.encode(adapted, fixture.item))
  })
  observe(fixture.name, "encode_json", fixture.iterations, outcome, fn() {
    consume(codec.encode_json(adapted, fixture.item))
  })
}

fn controls() {
  let item = order()
  let typed = codegen.runtime(materialize_fixtures.order_definition())
  observe("order", "typed_encode", 5000, "ok", fn() {
    consume(codec.encode(typed, item))
  })
  observe("order", "typed_encode_json", 5000, "ok", fn() {
    consume(codec.encode_json(typed, item))
  })
  observe("order", "generated_encode", 5000, "ok", fn() {
    consume(order_codec.encode_order(item))
  })
  observe("order", "generated_encode_json", 5000, "ok", fn() {
    consume(order_codec.encode_order_json(item))
  })
  let fixture =
    from_typed(
      "records_1000_sparse_bounds",
      codec.list(record_codec()),
      list.repeat(record(), 1000),
      100,
    )
  let adapted = contract.value_codec(fixture.schema)
  observe(fixture.name, "validate_then_encode_json", 100, "ok", fn() {
    let assert Ok(validated) = contract.validate(fixture.schema, fixture.item)
    consume(codec.encode_json(adapted, contract.value(validated)))
  })
  observe(fixture.name, "validate_then_render", 100, "ok", fn() {
    let assert Ok(validated) = contract.validate(fixture.schema, fixture.item)
    consume(value.to_string(contract.value(validated)))
  })
}

pub fn main() {
  fixtures_are_valid_and_preserved_test()
  native_and_generated_controls_agree_test()
  invalid_fixtures_locate_the_failed_bound_test()
  let start_count = consumed_count()
  list.each(fixtures(), dynamic)
  controls()
  dynamic(invalid_fixture(False))
  dynamic(invalid_fixture(True))
  should.be_true(consumed_count() > start_count)
}

fn positions(count: Int) -> List(Int) {
  list.index_map(list.repeat(Nil, count), fn(_, index) { index + 1 })
}
