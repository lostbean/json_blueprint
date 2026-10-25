//// THROWAWAY: compare supported numeric projections across decimal tokens.

import gleam/io
import gleam/list
import gleam/string
import json/blueprint/codec
import native_bounded as native

@external(erlang, "parser_benchmark_ffi", "setting")
@external(javascript, "./parser_benchmark_ffi.mjs", "setting")
fn setting(name: String) -> String

@external(erlang, "parser_benchmark_ffi", "read_text")
@external(javascript, "./parser_benchmark_ffi.mjs", "read_text")
fn read_text(path: String) -> String

@external(erlang, "native_numeric_probe_ffi", "debug")
fn debug(_value: a) -> Nil {
  Nil
}

fn compare(c: codec.Codec(a), d: native.Decoder(a), source: String) -> Nil {
  let expected = codec.decode_json(c, source)
  let actual = case native.decode_json(source, d) {
    Ok(x) -> Ok(x)
    Error(native.Typed(error)) -> Error(error)
    _ -> panic as "Unexpected native parser failure in numeric comparison"
  }
  case expected == actual {
    True -> Nil
    False -> {
      io.println(source)
      let _ = debug(expected)
      let _ = debug(actual)
      panic as "Numeric projection mismatch"
    }
  }
}

pub fn main() -> Nil {
  read_text(setting("BLUEPRINT_PARSER_INPUT"))
  |> string.split("\n")
  |> list.filter(fn(s) { s != "" })
  |> list.each(fn(s) {
    compare(codec.number(), native.number(), s)
    compare(codec.int(), native.int(), s)
    compare(codec.float(), native.float(), s)
  })
  io.println("Numeric projection parity passed")
}
