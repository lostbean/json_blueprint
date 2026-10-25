//// Parser observations only. The Python runner owns fixtures and fresh VMs.

import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import json/blueprint/value

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

fn normalized(item: value.Value) -> value.Value {
  case item {
    value.Object(members) ->
      members
      |> list.map(fn(member) { #(member.0, normalized(member.1)) })
      |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
      |> value.Object
    value.Array(items) -> value.Array(list.map(items, normalized))
    _ -> item
  }
}

pub fn main() -> Nil {
  let source = read_text(setting("BLUEPRINT_PARSER_INPUT"))
  let accepted = setting("BLUEPRINT_PARSER_ACCEPTED") == "true"
  let strict = setting("BLUEPRINT_PARSER_BACKEND") == "strict"
  let limits = value.default_limits()
  let work = case strict {
    True -> fn() {
      let outcome = value.parse(source, limits)
      let assert True = result.is_ok(outcome) == accepted
      consume(outcome)
    }
    False -> fn() {
      let outcome = json.parse(source, decode.dynamic)
      let assert True = result.is_ok(outcome) == accepted
      consume(outcome)
    }
  }
  // Memory mode runs only the chosen parser once, with no other parser's
  // allocations contaminating its process high-water RSS.
  case setting("BLUEPRINT_PARSER_MODE") {
    "memory" -> {
      work()
      io.println(
        "{\"accepted\":"
        <> case accepted {
          True -> "true"
          False -> "false"
        }
        <> "}",
      )
    }
    _ -> {
      // These fixtures have native-representable numbers; agreement is checked
      // before timing, including actual values, not just successful parsing.
      case accepted {
        True -> {
          let assert Ok(exact) = value.parse(source, limits)
          let assert Ok(native) = json.parse(source, value.decoder())
          let assert True = normalized(exact) == normalized(native)
          Nil
        }
        False -> {
          let assert Error(_) = value.parse(source, limits)
          let assert Error(_) = json.parse(source, decode.dynamic)
          Nil
        }
      }
      let assert Ok(iterations) =
        int.parse(setting("BLUEPRINT_PARSER_ITERATIONS"))
      let assert True = iterations > 0
      repeat(iterations, work)
      let samples =
        list.map(list.repeat(Nil, 5), fn(_) {
          let start = monotonic_nanos()
          repeat(iterations, work)
          { monotonic_nanos() - start } / iterations
        })
      io.println(json.to_string(json.array(samples, json.int)))
    }
  }
}
