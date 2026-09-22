import gleam/bit_array
import gleeunit/should
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/runtime

pub type Task {
  Task(id: Int, title: String, priority: codec.Optional(String))
}

pub fn schema_aware_core_example_test() {
  // 1. Defining a schema-aware codec
  let assert Ok(id_codec) = codec.integer_between(1, 100_000)
  let assert Ok(inner_properties) =
    codec.combine(
      codec.required("id", id_codec),
      codec.required("title", codec.string()),
    )
  let assert Ok(task_properties) =
    codec.combine(inner_properties, codec.optional("priority", codec.string()))
  let task_codec =
    codec.imap(
      codec.object(task_properties),
      fn(p: #(#(Int, String), codec.Optional(String))) {
        Task(p.0.0, p.0.1, p.1)
      },
      fn(t: Task) { #(#(t.id, t.title), t.priority) },
    )

  // 2. Encoding to Blueprint Value
  let task = Task(1, "Release Wave 4", codec.Present("high"))
  let assert Ok(wire_val) = codec.encode(task_codec, task)

  // 3. Decoding from Blueprint Value
  let assert Ok(decoded) = codec.decode(task_codec, wire_val)
  decoded |> should.equal(task)

  // 4. Schema Derivation and Runtime Contract Validation
  let assert Ok(schema) = codec.schema(task_codec)
  let assert Ok(contract) = runtime.from_schema(schema)
  let assert Ok(validated) = runtime.validate(contract, wire_val)
  runtime.encoded(validated) |> should.equal(wire_val)
  runtime.matches(contract, validated) |> should.equal(True)

  // 5. Exact Number Handling
  let assert Ok(num_limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(proj_limit) = number.integer_projection_limit(50)
  let assert Ok(exact_num) = number.parse_number(num_limits, "1.2300e2")
  number.number_text(exact_num) |> should.equal("1.23e2")
  number.is_integer(exact_num) |> should.equal(True)
  number.to_int_exact(exact_num, proj_limit) |> should.equal(Ok(123))

  // 6. Bounded Byte Admission
  let limits = parser.default_limits()
  let json_bytes =
    bit_array.from_string(
      "{\"id\": 1, \"title\": \"Release Wave 4\", \"priority\": \"high\"}",
    )
  let assert Ok(parsed_val) = parser.parse_value(limits, json_bytes)
  let assert Ok(parsed_task) = codec.decode(task_codec, parsed_val)
  parsed_task |> should.equal(task)
}
