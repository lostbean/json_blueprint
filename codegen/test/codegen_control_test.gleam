//// Codegen definitions keep descriptions and optional properties, and
//// generated codecs admit text as strictly as runtime codecs.

import generated/option_codec
import generated/order_codec
import generated_source_normalize
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec.{DecodeError, Field}
import json/blueprint/codegen
import json/blueprint/value
import option_fixtures

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

pub fn codegen_description_preserves_runtime_and_generated_schema_test() {
  let definition = codegen.describe(codegen.string(), "A quoted \"name\"")
  codec.schema(codegen.runtime(definition))
  |> should.equal(
    Ok(codec.DescribedSchema("A quoted \"name\"", codec.StringSchema)),
  )
  let assert Ok(compiled) =
    codegen.compile("generated/described_name", "described_name", definition)
  let codegen.GeneratedModule(_, content, _) = compiled
  string.contains(
    content,
    "codec.DescribedSchema(\"A quoted \\\"name\\\"\", codec.StringSchema)",
  )
  |> should.be_true

  // A later description at the same node replaces the earlier one.
  codegen.describe(definition, "Renamed")
  |> codegen.runtime
  |> codec.schema
  |> should.equal(Ok(codec.DescribedSchema("Renamed", codec.StringSchema)))
}

pub fn option_property_keeps_missing_null_and_value_test() {
  let c = {
    use note <- codec.optional_field(
      "note",
      codec.nullable(codec.string()),
      fn(note: Option(Option(String))) { note },
    )
    codec.success(note)
  }
  codec.decode(c, value.Object([])) |> should.equal(Ok(None))
  codec.decode(c, value.Object([#("note", value.Null)]))
  |> should.equal(Ok(Some(None)))
  codec.decode(c, value.Object([#("note", value.String("hi"))]))
  |> should.equal(Ok(Some(Some("hi"))))
  codec.encode(c, Some(None))
  |> should.equal(Ok(value.Object([#("note", value.Null)])))
  codec.encode(c, Some(Some("hi")))
  |> should.equal(Ok(value.Object([#("note", value.String("hi"))])))
  codec.encode(c, None) |> should.equal(Ok(value.Object([])))

  // The codegen definition is the same codec.
  let runtime = codegen.runtime(option_fixtures.definition())
  codec.schema(runtime) |> should.equal(codec.schema(c))
  list.each(
    [
      value.Object([]),
      value.Object([#("note", value.Null)]),
      value.Object([#("note", value.String("hi"))]),
      value.Object([#("note", value.Bool(True))]),
    ],
    fn(raw) { codec.decode(runtime, raw) |> should.equal(codec.decode(c, raw)) },
  )

  // Without `nullable`, `null` is not a value of the optional field.
  let plain = {
    use note <- codec.optional_field(
      "note",
      codec.string(),
      fn(note: Option(String)) { note },
    )
    codec.success(note)
  }
  codec.decode(plain, value.Object([#("note", value.Null)]))
  |> should.equal(Error(DecodeError([Field("note")], codec.ExpectedString)))
}

pub fn generated_option_property_matches_runtime_test() {
  let runtime = codegen.runtime(option_fixtures.definition())
  let generated = option_codec.option_codec()
  let cases = [
    #(value.Object([]), None),
    #(value.Object([#("note", value.Null)]), Some(None)),
    #(value.Object([#("note", value.String("hi"))]), Some(Some("hi"))),
  ]
  list.all(cases, fn(pair) {
    codec.decode(runtime, pair.0) == Ok(pair.1)
    && codec.decode(generated, pair.0) == Ok(pair.1)
    && codec.encode(generated, pair.1) == Ok(pair.0)
    && codec.encode(runtime, pair.1) == Ok(pair.0)
  })
  |> should.be_true
  codec.schema(generated) |> should.equal(codec.schema(runtime))
  option_codec.decode_option_json("{\"note\":null}")
  |> should.equal(Ok(Some(None)))
  let assert Ok(compiled) =
    codegen.compile(
      "generated/option_codec",
      "option",
      option_fixtures.definition(),
    )
  let codegen.GeneratedModule(_, content, fingerprint) = compiled
  fingerprint |> should.equal(option_codec.generated_fingerprint)
  let assert Ok(file) = read_file_to_string("test/generated/option_codec.gleam")
  generated_source_normalize.normalize(file)
  |> should.equal(generated_source_normalize.normalize(content))
}

pub fn generated_and_mapped_json_use_strict_admission_test() {
  let generated = order_codec.order_codec()
  let duplicate =
    "{\"order_id\":1,\"order_id\":2,\"items_\\\"list\\\"\":[],\"type\":true,\"status\":\"pending\"}"
  let assert Error(DecodeError(
    [],
    codec.InvalidJson(value.ParseError(_, value.DuplicateObjectKey)),
  )) = codec.decode_json(generated, duplicate)
}
