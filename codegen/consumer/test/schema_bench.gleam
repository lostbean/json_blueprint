//// Measurement fixture; no timing assertion participates in consumer tests.

import commerce/order
import consumer_support as fixture
import gleam/int
import gleam/list
import json/blueprint/codec
import json/blueprint/contract

pub type Workload {
  Workload(
    name: String,
    operation: String,
    iterations: Int,
    prepare: fn() -> fn() -> Nil,
  )
}

@external(erlang, "schema_bench_probe", "consume")
@external(javascript, "./schema_bench_probe.mjs", "consume")
fn consume(value: a) -> Nil

@external(erlang, "schema_bench_probe", "run")
@external(javascript, "./schema_bench_probe.mjs", "run")
fn run(cases: List(Workload)) -> Nil

pub fn main() {
  run(workloads())
}

pub fn workloads() -> List(Workload) {
  let loaded = fixture.loaded("order")
  let setup = [
    Workload("generated", "construct_codec", 2000, fn() {
      fn() { consume(order.order_codec()) }
    }),
    Workload("handwritten", "construct_codec", 2000, fn() {
      fn() { consume(fixture.handwritten_codec()) }
    }),
    Workload("dynamic", "construct_codec", 2000, fn() {
      fn() { consume(contract.value_codec(loaded)) }
    }),
  ]
  list.append(
    setup,
    list.flat_map([1, 25, 100], fn(count) {
      let iterations = case count {
        1 -> 1000
        25 -> 100
        _ -> 30
      }
      list.flat_map(["generated", "handwritten", "dynamic"], fn(implementation) {
        list.map(
          ["encode_value", "decode_value", "encode_text", "decode_text"],
          fn(operation) {
            Workload(
              implementation <> "_" <> int.to_string(count),
              operation,
              iterations,
              fn() {
                let native = fixture.sample(count)
                let typed = case implementation {
                  "handwritten" -> fixture.handwritten_codec()
                  _ -> order.order_codec()
                }
                let dynamic = contract.value_codec(loaded)
                let assert Ok(raw) = codec.encode(typed, native)
                let assert Ok(text) = codec.encode_json(typed, native)
                case implementation, operation {
                  "dynamic", "encode_value" -> fn() {
                    consume(codec.encode(dynamic, raw))
                  }
                  "dynamic", "decode_value" -> fn() {
                    consume(codec.decode(dynamic, raw))
                  }
                  "dynamic", "encode_text" -> fn() {
                    consume(codec.encode_json(dynamic, raw))
                  }
                  "dynamic", _ -> fn() {
                    consume(codec.decode_json(dynamic, text))
                  }
                  _, "encode_value" -> fn() {
                    consume(codec.encode(typed, native))
                  }
                  _, "decode_value" -> fn() {
                    consume(codec.decode(typed, raw))
                  }
                  _, "encode_text" -> fn() {
                    consume(codec.encode_json(typed, native))
                  }
                  _, _ -> fn() { consume(codec.decode_json(typed, text)) }
                }
              },
            )
          },
        )
      })
    }),
  )
}
