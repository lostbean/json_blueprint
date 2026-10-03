import generated/order_codec
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value
import materialize_fixtures
import vanilla_order

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
pub fn monotonic_nanos() -> Int

@external(erlang, "bench_ffi", "target_runtime")
@external(javascript, "./bench_ffi.mjs", "target_runtime")
pub fn target_runtime() -> String

@external(erlang, "bench_ffi", "consume")
@external(javascript, "./bench_ffi.mjs", "consume")
fn consume_benchmark_value(value: a) -> Nil

@external(erlang, "bench_ffi", "consumed_count")
@external(javascript, "./bench_ffi.mjs", "consumed_count")
fn benchmark_sink_count() -> Int

pub type BenchResult {
  BenchResult(
    name: String,
    runtime_name: String,
    warmup_iterations: Int,
    sample_iterations: Int,
    elapsed_nanos: Int,
    mean_nanos_per_op: Int,
    ops_per_second: Int,
  )
}

pub fn run_benchmark(
  name: String,
  warmup_count: Int,
  batch_count: Int,
  batch_size: Int,
  work: fn() -> Nil,
) -> BenchResult {
  // 1. Warmup
  run_n_times(warmup_count, work)

  // 2. Timed measurement across batches
  let start_time = monotonic_nanos()
  run_n_times(batch_count * batch_size, work)
  let end_time = monotonic_nanos()

  let elapsed = end_time - start_time
  let total_samples = batch_count * batch_size
  let safe_elapsed = case elapsed <= 0 {
    True -> 1
    False -> elapsed
  }
  let mean_nanos = safe_elapsed / total_samples
  let safe_mean = case mean_nanos <= 0 {
    True -> 1
    False -> mean_nanos
  }
  let ops_per_sec = 1_000_000_000 / safe_mean

  BenchResult(
    name: name,
    runtime_name: target_runtime(),
    warmup_iterations: warmup_count,
    sample_iterations: total_samples,
    elapsed_nanos: safe_elapsed,
    mean_nanos_per_op: safe_mean,
    ops_per_second: ops_per_sec,
  )
}

fn run_n_times(n: Int, work: fn() -> Nil) -> Nil {
  case n <= 0 {
    True -> Nil
    False -> {
      work()
      run_n_times(n - 1, work)
    }
  }
}

pub type BenchUser {
  BenchUser(name: String, age: Int, tags: List(String))
}

pub fn run_all_benchmarks() -> List(BenchResult) {
  let num_limits =
    number.limits(
      max_token_bytes: 1024,
      max_significant_digits: 100,
      max_exponent: 1000,
    )
  let p_limits =
    value.default_limits()
    |> value.with_max_bytes(100_000)
    |> value.with_max_depth(32)
    |> value.with_number_limits(num_limits)

  // 1. Number parse and canonicalize benchmark (7 tokens per batch)
  let number_tokens = [
    "0", "1", "1.2300e2", "123.45", "-0.5", "9007199254740992", "1e400",
  ]
  let bench_number =
    run_benchmark("number_parse_canonical_7_token_batch", 200, 5, 200, fn() {
      list.each(number_tokens, fn(token) {
        let assert Ok(num) = number.parse(token, num_limits)
        let _ = number.to_string(num)
        Nil
      })
    })

  // 2. Parser byte admission benchmark
  let sample_json =
    "{\"title\": \"bench\", \"count\": 42, \"items\": [1, 2, 3], \"active\": true, \"note\": null}"
  let bench_parser =
    run_benchmark("parser_document_admission", 200, 5, 200, fn() {
      let assert Ok(_val) = value.parse(sample_json, p_limits)
      Nil
    })

  // 3. Runtime contract validation benchmark
  let user_codec = {
    use name <- codec.field("name", codec.string(), get: fn(u) { u.0 })
    use age <- codec.field("age", codec.integer_between(0, 120), get: fn(u) {
      u.1
    })
    use tags <- codec.field("tags", codec.list(codec.string()), get: fn(u) {
      u.2
    })
    codec.success(#(name, age, tags))
  }
  let assert Ok(user_contract) = contract.from_codec(user_codec)
  let assert Ok(num36) = number.from_int(36)
  let sample_user_val =
    value.Object([
      #("name", value.String("Ada Lovelace")),
      #("age", value.Number(num36)),
      #(
        "tags",
        value.Array([
          value.String("computing"),
          value.String("mathematician"),
        ]),
      ),
    ])
  let bench_runtime =
    run_benchmark("runtime_contract_validation", 200, 5, 200, fn() {
      let assert Ok(_validated) =
        contract.validate(user_contract, sample_user_val)
      Nil
    })

  // 4. Codec roundtrip benchmark
  let user_codec = {
    use name <- codec.field("name", codec.string(), get: fn(u) { u.name })
    use age <- codec.field("age", codec.int(), get: fn(u) { u.age })
    use tags <- codec.field("tags", codec.list(codec.string()), get: fn(u) {
      u.tags
    })
    codec.success(BenchUser(name:, age:, tags:))
  }
  let user_instance = BenchUser("Ada Lovelace", 36, ["computing", "math"])
  let bench_codec =
    run_benchmark("codec_encode_decode_roundtrip", 200, 5, 200, fn() {
      let assert Ok(encoded) = codec.encode(user_codec, user_instance)
      let assert Ok(_decoded) = codec.decode(user_codec, encoded)
      Nil
    })

  list.append(
    [bench_number, bench_parser, bench_runtime, bench_codec],
    run_order_codec_benchmarks(),
  )
}

pub fn print_benchmark_report(results: List(BenchResult)) -> Nil {
  io.println("\n--- json_blueprint Benchmark Suite Results ---")
  io.println(
    "order_*_complete_text cases include rendering or parsing (generated native_direct cases use gleam/json; strict and wrapper cases use the Blueprint parser); legacy_value_* cases exclude JSON text conversion; native_* diagnostics isolate parser/helper work.",
  )
  list.each(results, fn(r) {
    io.println(
      r.name
      <> " ["
      <> r.runtime_name
      <> "]: warmup "
      <> int.to_string(r.warmup_iterations)
      <> ", "
      <> int.to_string(r.sample_iterations)
      <> " samples, "
      <> int.to_string(r.elapsed_nanos)
      <> " ns elapsed, "
      <> int.to_string(r.mean_nanos_per_op)
      <> " ns/op, "
      <> int.to_string(r.ops_per_second)
      <> " ops/sec",
    )
  })
  io.println("----------------------------------------------\n")
}

pub fn benchmark_suite_test() {
  let results = run_all_benchmarks()
  list.length(results) |> should.equal(25)

  list.each(results, fn(res) {
    should.equal(res.sample_iterations, 1000)
    should.be_true(res.elapsed_nanos > 0)
    should.be_true(res.mean_nanos_per_op > 0)
    should.be_true(res.ops_per_second > 0)
  })

  print_benchmark_report(results)
}

pub fn order_codec_benchmark_inventory_test() {
  let results = run_order_codec_benchmarks()
  let case_names =
    list.map(results, fn(result) {
      let BenchResult(name, _, _, _, _, _, _) = result
      name
    })
  let required_cases = [
    "order_runtime_definition_codec_construction",
    "order_generated_codec_wrapper_construction",
    "order_vanilla_decoder_construction",
    "order_runtime_inline_complete_text_encode",
    "order_runtime_inline_complete_text_decode",
    "order_runtime_reused_complete_text_encode",
    "order_runtime_reused_complete_text_decode",
    "order_generated_native_direct_complete_text_encode",
    "order_generated_native_direct_complete_text_decode",
    "order_generated_strict_direct_complete_text_decode",
    "order_generated_wrapper_complete_text_encode",
    "order_generated_wrapper_complete_text_decode",
    "order_vanilla_complete_text_encode",
    "order_vanilla_complete_text_decode",
    "native_gleam_json_dynamic_parse",
    "native_dynamic_object_dict_materialization",
    "vanilla_parsed_dynamic_typed_decode",
    "legacy_value_runtime_inline_encode",
    "legacy_value_runtime_reused_encode",
    "legacy_value_runtime_inline_decode",
    "legacy_value_runtime_reused_decode",
  ]

  should.equal(list.length(results), 21)
  list.all(required_cases, fn(required) { list.contains(case_names, required) })
  |> should.be_true

  list.each(results, fn(result) {
    let BenchResult(_, runtime_name, warmup, samples, elapsed, ns_per_op, ops) =
      result
    should.be_true(runtime_name != "")
    should.equal(warmup, 200)
    should.equal(samples, 1000)
    should.be_true(elapsed > 0)
    should.be_true(ns_per_op > 0)
    should.be_true(ops > 0)
  })
}

pub fn native_complete_text_backends_match_for_order_variants_test() {
  let runtime = codegen.runtime(materialize_fixtures.order_definition())
  let generated = order_codec.order_codec()
  let vanilla_decoder = vanilla_order.decoder()
  let notes = [None, Some(None), Some(Some("leave\n\r\f\t\\door 🚀"))]
  let statuses = [
    materialize_fixtures.Pending,
    materialize_fixtures.Processing,
    materialize_fixtures.ShippedQuoted,
    materialize_fixtures.DeliveredUnicode,
  ]

  list.each(notes, fn(note) {
    list.each(statuses, fn(status) {
      let order = order_for_text_parity(note, status)
      let assert Ok(wire) = codec.encode_json(runtime, order)
      should.equal(codec.encode_json(generated, order), Ok(wire))
      should.equal(order_codec.encode_order_json(order), Ok(wire))
      let assert Ok(vanilla_value) = vanilla_order.encode(order)
      should.equal(json.to_string(vanilla_value), wire)

      codec.decode_json(runtime, wire)
      |> should.equal(Ok(order))
      codec.decode_json(generated, wire)
      |> should.equal(Ok(order))
      order_codec.decode_order_json(wire)
      |> should.equal(Ok(order))
      order_codec.decode_order_json_native(wire)
      |> should.equal(Ok(order))
      json.parse(from: wire, using: codec.decoder(generated))
      |> should.equal(Ok(order))
      json.parse(from: wire, using: vanilla_decoder)
      |> should.equal(Ok(order))
    })
  })
}

fn order_for_text_parity(
  note: Option(Option(String)),
  status: materialize_fixtures.OrderStatus,
) -> materialize_fixtures.Order {
  materialize_fixtures.Order(
    42,
    [#("widget", 2), #("雪 🚀", 7)],
    note,
    True,
    status,
  )
}

pub fn vanilla_order_baseline_matches_blueprint_wire_shape_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  let candidates = [
    materialize_fixtures.Order(
      42,
      [#("widget", 2), #("雪 🚀", 7)],
      None,
      True,
      materialize_fixtures.Pending,
    ),
    materialize_fixtures.Order(
      42,
      [#("widget", 2), #("雪 🚀", 7)],
      Some(None),
      True,
      materialize_fixtures.Processing,
    ),
    materialize_fixtures.Order(
      42,
      [#("widget", 2), #("雪 🚀", 7)],
      Some(Some("leave at door")),
      True,
      materialize_fixtures.DeliveredUnicode,
    ),
  ]

  list.each(candidates, fn(order) {
    let assert Ok(blueprint_value) = codec.encode(runtime, order)
    let assert Ok(generated_value) = codec.encode(generated, order)
    let assert Ok(vanilla_json) = vanilla_order.encode(order)
    let wire = value.to_string(blueprint_value)
    should.equal(generated_value, blueprint_value)
    should.equal(json.to_string(vanilla_json), wire)

    let assert Ok(blueprint_input) = value.parse(wire, value.default_limits())
    let assert Ok(dynamic_input) = json.parse(from: wire, using: decode.dynamic)
    should.equal(codec.decode(runtime, blueprint_input), Ok(order))
    should.equal(order_codec.decode_order(blueprint_input), Ok(order))
    should.equal(decode.run(dynamic_input, vanilla_order.decoder()), Ok(order))
    should.equal(
      json.parse(from: wire, using: vanilla_order.decoder()),
      Ok(order),
    )
  })

  let outside_range =
    materialize_fixtures.Order(
      1_000_000,
      [#("widget", 2)],
      None,
      True,
      materialize_fixtures.Pending,
    )
  let assert Error(vanilla_encode_error) = vanilla_order.encode(outside_range)
  let assert Error(blueprint_encode_error) =
    codec.encode(runtime, outside_range)
  should.equal(vanilla_encode_error, blueprint_encode_error)

  let assert [valid_order, ..] = candidates
  let assert Ok(valid_value) = codec.encode(runtime, valid_order)
  let valid_wire = value.to_string(valid_value)
  let out_of_range_wire =
    string.replace(
      valid_wire,
      each: "\"order_id\":42",
      with: "\"order_id\":1000000",
    )
  let assert Error(_) =
    json.parse(from: out_of_range_wire, using: vanilla_order.decoder())
}

fn run_order_codec_benchmarks() -> List(BenchResult) {
  let order =
    materialize_fixtures.Order(
      42,
      [#("widget", 2), #("雪 🚀", 7)],
      Some(Some("leave at door")),
      True,
      materialize_fixtures.ShippedQuoted,
    )

  // Reusable artifacts and the legacy Blueprint Value are prepared before
  // timed work. Every complete-text decoder receives this same wire string.
  let runtime_codec = codegen.runtime(materialize_fixtures.order_definition())
  let generated_codec = order_codec.order_codec()
  let vanilla_decoder = vanilla_order.decoder()
  let assert Ok(runtime_json) = codec.encode_json(runtime_codec, order)
  let assert Ok(generated_json) = order_codec.encode_order_json(order)
  let assert Ok(wrapped_json) = codec.encode_json(generated_codec, order)
  let assert Ok(vanilla_json) = vanilla_order.encode(order)
  let vanilla_wire = json.to_string(vanilla_json)
  let assert Ok(parsed_dynamic) =
    json.parse(from: vanilla_wire, using: decode.dynamic)
  should.equal(generated_json, runtime_json)
  should.equal(wrapped_json, runtime_json)
  should.equal(vanilla_wire, runtime_json)
  let wire_json = runtime_json

  codec.decode_json(runtime_codec, wire_json)
  |> should.equal(Ok(order))
  order_codec.decode_order_json(wire_json)
  |> should.equal(Ok(order))
  order_codec.decode_order_json_native(wire_json)
  |> should.equal(Ok(order))
  codec.decode_json(generated_codec, wire_json)
  |> should.equal(Ok(order))
  json.parse(from: wire_json, using: vanilla_decoder)
  |> should.equal(Ok(order))

  let assert Ok(runtime_value) = codec.encode(runtime_codec, order)
  let legacy_wire = value.to_string(runtime_value)
  should.equal(legacy_wire, wire_json)
  let assert Ok(blueprint_input) =
    value.parse(legacy_wire, value.default_limits())
  should.equal(codec.decode(runtime_codec, blueprint_input), Ok(order))
  should.equal(order_codec.decode_order(blueprint_input), Ok(order))

  let construction_benchmarks = [
    run_construction_benchmark(
      "order_runtime_definition_codec_construction",
      fn() { codegen.runtime(materialize_fixtures.order_definition()) },
    ),
    run_construction_benchmark(
      "order_generated_codec_wrapper_construction",
      fn() { order_codec.order_codec() },
    ),
    run_construction_benchmark("order_vanilla_decoder_construction", fn() {
      vanilla_order.decoder()
    }),
  ]

  let legacy_value_benchmarks = [
    run_benchmark("legacy_value_runtime_inline_encode", 200, 5, 200, fn() {
      let assert Ok(_) =
        codec.encode(
          codegen.runtime(materialize_fixtures.order_definition()),
          order,
        )
      Nil
    }),
    run_benchmark("legacy_value_runtime_reused_encode", 200, 5, 200, fn() {
      let assert Ok(_) = codec.encode(runtime_codec, order)
      Nil
    }),
    run_benchmark("legacy_value_runtime_inline_decode", 200, 5, 200, fn() {
      let assert Ok(_) =
        codec.decode(
          codegen.runtime(materialize_fixtures.order_definition()),
          blueprint_input,
        )
      Nil
    }),
    run_benchmark("legacy_value_runtime_reused_decode", 200, 5, 200, fn() {
      let assert Ok(_) = codec.decode(runtime_codec, blueprint_input)
      Nil
    }),
  ]

  let complete_text_benchmarks = [
    run_benchmark(
      "order_runtime_inline_complete_text_encode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) =
          codec.encode_json(
            codegen.runtime(materialize_fixtures.order_definition()),
            order,
          )
        Nil
      },
    ),
    run_benchmark(
      "order_runtime_inline_complete_text_decode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) =
          codec.decode_json(
            codegen.runtime(materialize_fixtures.order_definition()),
            wire_json,
          )
        Nil
      },
    ),
    run_benchmark(
      "order_runtime_reused_complete_text_encode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) = codec.encode_json(runtime_codec, order)
        Nil
      },
    ),
    run_benchmark(
      "order_runtime_reused_complete_text_decode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) = codec.decode_json(runtime_codec, wire_json)
        Nil
      },
    ),
    run_benchmark(
      "order_generated_native_direct_complete_text_encode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) = order_codec.encode_order_json(order)
        Nil
      },
    ),
    run_benchmark(
      "order_generated_native_direct_complete_text_decode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) = order_codec.decode_order_json_native(wire_json)
        Nil
      },
    ),
    run_benchmark(
      "order_generated_strict_direct_complete_text_decode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) = order_codec.decode_order_json(wire_json)
        Nil
      },
    ),
    run_benchmark(
      "order_generated_wrapper_complete_text_encode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) = codec.encode_json(generated_codec, order)
        Nil
      },
    ),
    run_benchmark(
      "order_generated_wrapper_complete_text_decode",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) = codec.decode_json(generated_codec, wire_json)
        Nil
      },
    ),
    run_benchmark("order_vanilla_complete_text_encode", 200, 5, 200, fn() {
      let assert Ok(encoded) = vanilla_order.encode(order)
      let _ = json.to_string(encoded)
      Nil
    }),
    run_benchmark("order_vanilla_complete_text_decode", 200, 5, 200, fn() {
      let assert Ok(_) = json.parse(from: wire_json, using: vanilla_decoder)
      Nil
    }),
  ]

  // These isolate parts of native decoding. JSON parsing creates the
  // Dynamic object once per operation; decode.dict then materializes the
  // object's entries as a Gleam Dict, as generated.decode_native_object
  // does before validating property names and decoding their values. The
  // vanilla typed-only case uses the same parsed Dynamic without JSON parsing.
  let native_decode_diagnostics = [
    run_benchmark("native_gleam_json_dynamic_parse", 200, 5, 200, fn() {
      let assert Ok(_) = json.parse(from: wire_json, using: decode.dynamic)
      Nil
    }),
    run_benchmark(
      "native_dynamic_object_dict_materialization",
      200,
      5,
      200,
      fn() {
        let assert Ok(_) =
          decode.run(parsed_dynamic, decode.dict(decode.string, decode.dynamic))
        Nil
      },
    ),
    run_benchmark("vanilla_parsed_dynamic_typed_decode", 200, 5, 200, fn() {
      let assert Ok(_) = decode.run(parsed_dynamic, vanilla_decoder)
      Nil
    }),
  ]

  list.append(
    construction_benchmarks,
    list.append(
      legacy_value_benchmarks,
      list.append(complete_text_benchmarks, native_decode_diagnostics),
    ),
  )
}

fn run_construction_benchmark(
  name: String,
  construct: fn() -> a,
) -> BenchResult {
  let starting_count = benchmark_sink_count()
  let result =
    run_benchmark(name, 200, 5, 200, fn() {
      let _ = consume_benchmark_value(construct())
      Nil
    })
  should.equal(benchmark_sink_count() - starting_count, 1200)
  result
}

pub fn main() -> Nil {
  let results = run_all_benchmarks()
  print_benchmark_report(results)
}
