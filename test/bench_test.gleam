import gleam/int
import gleam/io
import gleam/list
import gleeunit/should
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/runtime
import json/blueprint/value

@external(erlang, "bench_ffi", "monotonic_nanos")
@external(javascript, "./bench_ffi.mjs", "monotonic_nanos")
pub fn monotonic_nanos() -> Int

@external(erlang, "bench_ffi", "target_runtime")
@external(javascript, "./bench_ffi.mjs", "target_runtime")
pub fn target_runtime() -> String

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
  let assert Ok(num_limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(p_limits) = parser.parser_limits(100_000, 32, num_limits)

  // 1. Number parse and canonicalize benchmark (7 tokens per batch)
  let number_tokens = [
    "0", "1", "1.2300e2", "123.45", "-0.5", "9007199254740992", "1e400",
  ]
  let bench_number =
    run_benchmark("number_parse_canonical_7_token_batch", 200, 5, 200, fn() {
      list.each(number_tokens, fn(token) {
        let assert Ok(num) = number.parse_number(num_limits, token)
        let _ = number.number_text(num)
        Nil
      })
    })

  // 2. Parser byte admission benchmark
  let sample_json =
    "{\"title\": \"bench\", \"count\": 42, \"items\": [1, 2, 3], \"active\": true, \"note\": null}"
  let bench_parser =
    run_benchmark("parser_document_admission", 200, 5, 200, fn() {
      let assert Ok(_val) =
        parser.parse_value_from_string(p_limits, sample_json)
      Nil
    })

  // 3. Runtime contract validation benchmark
  let user_schema =
    codec.ObjectSchema([
      codec.PropertySchema("name", True, codec.StringSchema),
      codec.PropertySchema("age", True, codec.IntegerRangeSchema(0, 120)),
      codec.PropertySchema("tags", True, codec.ListSchema(codec.StringSchema)),
    ])
  let assert Ok(contract) = runtime.from_schema(user_schema)
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
      let assert Ok(_validated) = runtime.validate(contract, sample_user_val)
      Nil
    })

  // 4. Codec roundtrip benchmark
  let assert Ok(user_props) =
    codec.combine(
      codec.required("name", codec.string()),
      codec.required("age", codec.int()),
    )
  let assert Ok(full_props) =
    codec.combine(
      user_props,
      codec.required("tags", codec.list(codec.string())),
    )
  let user_codec =
    codec.imap(
      codec.object(full_props),
      fn(raw: #(#(String, Int), List(String))) {
        BenchUser(raw.0.0, raw.0.1, raw.1)
      },
      fn(u: BenchUser) { #(#(u.name, u.age), u.tags) },
    )
  let user_instance = BenchUser("Ada Lovelace", 36, ["computing", "math"])
  let bench_codec =
    run_benchmark("codec_encode_decode_roundtrip", 200, 5, 200, fn() {
      let assert Ok(encoded) = codec.encode(user_codec, user_instance)
      let assert Ok(_decoded) = codec.decode(user_codec, encoded)
      Nil
    })

  [bench_number, bench_parser, bench_runtime, bench_codec]
}

pub fn print_benchmark_report(results: List(BenchResult)) -> Nil {
  io.println("\n--- json_blueprint Benchmark Suite Results ---")
  list.each(results, fn(r) {
    io.println(
      r.name
      <> " ["
      <> r.runtime_name
      <> "]: "
      <> int.to_string(r.sample_iterations)
      <> " samples, "
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
  list.length(results) |> should.equal(4)

  list.each(results, fn(res) {
    should.equal(res.sample_iterations, 1000)
    should.be_true(res.elapsed_nanos > 0)
    should.be_true(res.mean_nanos_per_op > 0)
    should.be_true(res.ops_per_second > 0)
  })

  print_benchmark_report(results)
}

pub fn main() -> Nil {
  let results = run_all_benchmarks()
  print_benchmark_report(results)
}
