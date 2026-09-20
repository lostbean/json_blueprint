import gleam/bit_array
import gleeunit/should
import json/blueprint as legacy
import json/blueprint/codec
import json/blueprint/migration
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/runtime
import json/blueprint/value

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

  // 7. Legacy 1.7.1 Migration
  let legacy_decoder =
    legacy.decode2(
      fn(id, title) { Task(id, title, codec.Missing) },
      legacy.field("id", legacy.int()),
      legacy.field("title", legacy.string()),
    )
  let legacy_encoder = fn(t: Task) {
    case number.from_int(t.id) {
      Error(_) ->
        Error(
          codec.CannotEncode(codec.CustomEncodeReason("Safe integer overflow")),
        )
      Ok(id_num) ->
        Ok(
          value.Object([
            #("id", value.Number(id_num)),
            #("title", value.String(t.title)),
          ]),
        )
    }
  }
  let adapted_codec = migration.adapt(legacy_decoder, legacy_encoder)
  codec.schema(adapted_codec) |> should.equal(Error(codec.UnknownSchema))
  let assert Ok(num42) = number.from_int(42)
  let assert Ok(legacy_decoded) =
    codec.decode(
      adapted_codec,
      value.Object([
        #("id", value.Number(num42)),
        #("title", value.String("Migrated task")),
      ]),
    )
  legacy_decoded
  |> should.equal(Task(42, "Migrated task", codec.Missing))
}

pub type MyRecord {
  MyRecord(name: String, count: Int)
}

pub fn readme_migration_example_test() {
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
  codec.schema(modern_codec)
  |> should.equal(Error(codec.UnknownSchema))

  let test_record = MyRecord("item", 42)
  let assert Ok(wire) = codec.encode(modern_codec, test_record)
  codec.decode(modern_codec, wire)
  |> should.equal(Ok(test_record))
}
