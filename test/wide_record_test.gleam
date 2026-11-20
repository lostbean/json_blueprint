//// A field name repeated after more than sixteen distinct fields still panics
//// during conversion, as a field repeated early does.

import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import json/blueprint/codec.{type Codec}

@external(erlang, "codec_test_ffi", "panic_message")
@external(javascript, "./codec_test_ffi.mjs", "panic_message")
fn panic_message(run: fn() -> a) -> Result(String, Nil)

fn nth(items: List(Int), index: Int) -> Int {
  let assert [item, ..] = list.drop(items, index)
  item
}

fn fields(
  names: List(String),
  index: Int,
  done: List(Int),
) -> Codec(List(Int)) {
  case names {
    [] -> codec.success(list.reverse(done))
    [name, ..rest] -> {
      use item <- codec.field(name, codec.int(), get: fn(items) {
        nth(items, index)
      })
      fields(rest, index + 1, [item, ..done])
    }
  }
}

fn names() -> List(String) {
  list.append(list.map(upto(20), fn(i) { "f" <> int.to_string(i) }), ["f3"])
}

pub fn a_late_repeated_field_panics_on_encode_test() {
  let wide = fields(names(), 0, [])
  let values = upto(21)
  let assert Ok(message) =
    panic_message(fn() { codec.encode_json(wide, values) })
  string.contains(message, "field \"f3\" appears twice") |> should.be_true
}

pub fn a_late_repeated_field_panics_on_decode_test() {
  let wide = fields(names(), 0, [])
  let text =
    "{"
    <> string.join(
      list.map(upto(20), fn(i) {
        "\"f" <> int.to_string(i) <> "\":" <> int.to_string(i)
      }),
      ",",
    )
    <> "}"
  let assert Ok(message) = panic_message(fn() { codec.decode_json(wide, text) })
  string.contains(message, "field \"f3\" appears twice") |> should.be_true
}

/// 0 up to `count - 1`.
fn upto(count: Int) -> List(Int) {
  int.range(0, count, [], fn(done, i) { [i, ..done] }) |> list.reverse
}
