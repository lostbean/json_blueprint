import gleam/bit_array
import gleam/option.{type Option, Some}
import gleeunit/should
import json/blueprint/codec.{type Codec}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

pub type Task {
  Task(id: Int, title: String, priority: Option(String))
}

fn task_codec() -> Codec(Task) {
  use id <- codec.field("id", codec.integer_between(1, 100_000), get: fn(t) {
    t.id
  })
  use title <- codec.field("title", codec.string(), get: fn(t) { t.title })
  use priority <- codec.optional_field("priority", codec.string(), get: fn(t) {
    t.priority
  })
  codec.success(Task(id:, title:, priority:))
}

pub fn schema_aware_core_example_test() {
  // 1. Encoding to a Value and decoding it back
  let task = Task(1, "Release Wave 4", Some("high"))
  let assert Ok(wire) = codec.encode(task_codec(), task)
  codec.decode(task_codec(), wire) |> should.equal(Ok(task))

  // 2. Schema derivation and contract validation
  let assert Ok(task_contract) = contract.from_codec(task_codec())
  let assert Ok(validated) = contract.validate(task_contract, wire)
  contract.value(validated) |> should.equal(wire)
  contract.decode(task_codec(), validated) |> should.equal(Ok(task))

  // 3. Exact numbers
  let assert Ok(exact) = number.parse("1.2300e2", number.default_limits())
  number.to_string(exact) |> should.equal("1.23e2")
  number.is_integer(exact) |> should.be_true
  number.to_int(exact, 50) |> should.equal(Ok(123))

  // 4. Bounded byte admission
  let bytes =
    bit_array.from_string(
      "{\"id\": 1, \"title\": \"Release Wave 4\", \"priority\": \"high\"}",
    )
  let assert Ok(parsed) = value.parse_bits(bytes, value.default_limits())
  codec.decode(task_codec(), parsed) |> should.equal(Ok(task))
}
