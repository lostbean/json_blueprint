import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import json/blueprint as legacy
import json/blueprint/codec
import json/blueprint/migration
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/runtime
import json/blueprint/value

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

// --- Snippet 1: Schema-Aware Core Pipeline ---

pub type Task {
  Task(id: Int, title: String)
}

pub fn run_task_pipeline() -> Result(Task, String) {
  // 1. Build bidirectional codec with bounded integer range
  use id_codec <- result.try(
    codec.integer_between(1, 100_000)
    |> result.map_error(fn(_) { "Invalid id range" }),
  )
  use task_props <- result.try(
    codec.combine(
      codec.required("id", id_codec),
      codec.required("title", codec.string()),
    )
    |> result.map_error(fn(_) { "Invalid properties combination" }),
  )
  let task_codec =
    codec.imap(
      codec.object(task_props),
      fn(pair: #(Int, String)) { Task(pair.0, pair.1) },
      fn(task: Task) { #(task.id, task.title) },
    )

  // 2. Parse untrusted JSON bytes with bounded parser limits
  let limits = parser.default_limits()
  let input_bytes =
    bit_array.from_string("{\"id\": 42, \"title\": \"Verify Blueprint\"}")

  use parsed_val <- result.try(
    parser.parse_value(limits, input_bytes)
    |> result.map_error(fn(_) { "JSON parse error" }),
  )

  // 3. Derive Draft 2020-12 runtime contract and validate
  use schema <- result.try(
    codec.schema(task_codec)
    |> result.map_error(fn(_) { "Unknown schema" }),
  )
  use contract <- result.try(
    runtime.from_schema(schema)
    |> result.map_error(fn(_) { "Invalid schema contract" }),
  )
  use _validated <- result.try(
    runtime.validate(contract, parsed_val)
    |> result.map_error(fn(_) { "Schema validation failure" }),
  )

  // 4. Decode into typed domain record
  codec.decode(task_codec, parsed_val)
  |> result.map_error(fn(_) { "Decoding failure" })
}

// --- Snippet 2: Legacy 1.7.1 Migration ---

pub type MyRecord {
  MyRecord(name: String, count: Int)
}

pub fn example() {
  let legacy_decoder =
    legacy.decode2(
      MyRecord,
      legacy.field("name", legacy.string()),
      legacy.field("count", legacy.int()),
    )

  let my_encoder = fn(record: MyRecord) {
    case number.from_int(record.count) {
      Error(_) ->
        Error(
          codec.CannotEncode(codec.CustomEncodeReason("Safe integer overflow")),
        )
      Ok(count_num) ->
        Ok(
          value.Object([
            #("name", value.String(record.name)),
            #("count", value.Number(count_num)),
          ]),
        )
    }
  }

  // Adapts legacy decoder with explicit encoder; reports codec.UnknownSchema
  let modern_codec = migration.adapt(legacy_decoder, my_encoder)
  modern_codec
}

// --- Runnable Tests ---

pub fn readme_pipeline_execution_test() {
  run_task_pipeline()
  |> should.equal(Ok(Task(42, "Verify Blueprint")))
}

pub fn readme_migration_execution_test() {
  let modern_codec = example()
  codec.schema(modern_codec)
  |> should.equal(Error(codec.UnknownSchema))

  let record = MyRecord("test", 100)
  let assert Ok(encoded) = codec.encode(modern_codec, record)
  let assert Ok(decoded) = codec.decode(modern_codec, encoded)
  decoded |> should.equal(record)
}

pub fn readme_snippets_exact_match_test() {
  let assert Ok(readme_str) = read_file_to_string("README.md")
  let assert Ok(test_source_str) =
    read_file_to_string("test/readme_example_test.gleam")

  let normalized_source = string.replace(test_source_str, "\r\n", "\n")
  let snippets = extract_gleam_snippets(readme_str)

  // We require the primary schema-aware snippet and migration snippet to match verbatim
  let modern_snippets = list.take(snippets, 2)
  list.length(modern_snippets) |> should.equal(2)

  list.each(modern_snippets, fn(snippet) {
    let normalized_snippet = string.replace(snippet, "\r\n", "\n")
    case string.contains(normalized_source, normalized_snippet) {
      True -> Nil
      False ->
        panic as {
          "README snippet not found verbatim in test/readme_example_test.gleam:\n"
          <> normalized_snippet
        }
    }
  })
}

fn extract_gleam_snippets(markdown: String) -> List(String) {
  let normalized = string.replace(markdown, "\r\n", "\n")
  extract_snippets_loop(normalized, [])
}

fn extract_snippets_loop(remaining: String, acc: List(String)) -> List(String) {
  case string.split_once(remaining, "```gleam\n") {
    Error(Nil) -> list.reverse(acc)
    Ok(#(_before, rest)) -> {
      case string.split_once(rest, "\n```") {
        Error(Nil) -> list.reverse(acc)
        Ok(#(snippet, after)) ->
          extract_snippets_loop(after, [string.trim(snippet), ..acc])
      }
    }
  }
}
