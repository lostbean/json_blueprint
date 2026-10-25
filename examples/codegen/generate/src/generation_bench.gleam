import generate_order
import gleam/float
import gleam/int
import gleam/io
import json/blueprint/codegen/schema as schema_codegen
import json/blueprint/contract

@external(erlang, "schema_generate_ffi", "monotonic_nanos")
@external(javascript, "./schema_generate_ffi.mjs", "monotonic_nanos")
fn now() -> Int

@external(erlang, "schema_generate_ffi", "consume")
@external(javascript, "./schema_generate_ffi.mjs", "consume")
fn consume(value: a) -> Nil

pub fn main() {
  let schema = contract.schema(generate_order.order_schema())
  let work = fn() {
    consume(schema_codegen.compile("commerce/order", "order", schema))
  }
  repeat(20, work)
  let start = now()
  repeat(200, work)
  let elapsed = now() - start
  io.println(
    "{\"name\":\"order\",\"operation\":\"generate_source\",\"iterations\":200,\"elapsed_ns\":"
    <> int.to_string(elapsed)
    <> ",\"ns_per_op\":"
    <> float.to_string(int.to_float(elapsed) /. 200.0)
    <> "}",
  )
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
