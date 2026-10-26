// Caller names, output types, and wire names remain data during source emission.
import generated/dynamic_codec
import generated/mapped_field_codec
import generated/mapping_codec
import generated/named_codec
import generated/plain_optional_codec
import generated_emitter_fixtures
import generated_mapping_fixtures
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/value

pub fn generated_names_and_types_test() {
  named_codec.decode_named_json("42") |> should.equal(Ok(42))
  let assert Ok(raw) = dynamic_codec.decode_dynamic_json("42")
  decode.run(raw, decode.int) |> should.equal(Ok(42))
  codec.encode_json(dynamic_codec.dynamic_codec(), dynamic.int(42))
  |> should.equal(Ok("42"))
  let generated = plain_optional_codec.plain_optional_codec()
  let runtime =
    codegen.runtime(generated_emitter_fixtures.optional_definition())
  codec.schema(generated) |> should.equal(codec.schema(runtime))
  codec.decode_json(generated, "{}") |> should.equal(Ok(None))
  let assert Ok(wire) = codec.encode_json(runtime, Some("test"))
  codec.encode_json(generated, Some("test")) |> should.equal(Ok(wire))
  codec.decode_json(generated, wire) |> should.equal(Ok(Some("test")))
}

// The retained fixtures must exercise the current emitter, not stale source.
pub fn generated_fixtures_match_current_emitter_test() {
  check_fingerprint(
    generated_emitter_fixtures.mapped_field_definition(),
    "generated/mapped_field_codec",
    "mapped_field",
    mapped_field_codec.generated_fingerprint,
  )
  check_fingerprint(
    generated_emitter_fixtures.dynamic_definition(),
    "generated/dynamic_codec",
    "dynamic",
    dynamic_codec.generated_fingerprint,
  )
  check_fingerprint(
    generated_emitter_fixtures.named_definition(),
    "generated/named_codec",
    "named",
    named_codec.generated_fingerprint,
  )
  check_fingerprint(
    generated_emitter_fixtures.optional_definition(),
    "generated/plain_optional_codec",
    "plain_optional",
    plain_optional_codec.generated_fingerprint,
  )
  check_fingerprint(
    generated_mapping_fixtures.definition(),
    "generated/mapping_codec",
    "mapping",
    mapping_codec.generated_fingerprint,
  )
}

fn check_fingerprint(
  definition: codegen.Definition(a),
  module_path: String,
  name: String,
  fingerprint: String,
) -> Nil {
  let assert Ok(codegen.GeneratedModule(_, _, actual)) =
    codegen.compile(module_path, name, definition)
  actual |> should.equal(fingerprint)
}

// Generated codecs are complete values, not continuation record builders.
pub fn generated_record_continuation_is_rejected_explicitly_test() {
  let generated = plain_optional_codec.plain_optional_codec()
  let runtime =
    codegen.runtime(generated_emitter_fixtures.optional_definition())
  extend_record(runtime) |> codec.check |> result.is_ok |> should.be_true
  extend_record(generated)
  |> codec.check
  |> result.map(fn(_) { Nil })
  |> should.equal(Error(codec.NotARecord("lead")))
}

fn extend_record(
  inner: codec.Codec(Option(String)),
) -> codec.Codec(Option(String)) {
  codec.field("lead", codec.int(), fn(_) { inner }, get: fn(_) { 0 })
}

// Pure named mappings preserve results and error order inside records. Cached
// schema/name metadata need not replay the runtime's placeholder callbacks.
pub fn generated_mapped_field_result_and_error_parity_test() {
  let generated = mapped_field_codec.mapped_field_codec()
  let runtime =
    codegen.runtime(generated_emitter_fixtures.mapped_field_definition())
  list.each(
    [
      "{}",
      "{\"value\":42}",
      "{\"value\":true}",
      "{\"value\":1.00000000000000001}",
      "{\"value\":42,\"extra\":null}",
      "{\"value\":false,\"extra\":null}",
      "{\"value\":42,\"value\":1}",
    ],
    fn(source) {
      codec.decode_json(generated, source)
      |> should.equal(codec.decode_json(runtime, source))
      case value.parse(source, value.default_limits()) {
        Ok(raw) ->
          codec.decode(generated, raw)
          |> should.equal(codec.decode(runtime, raw))
        Error(_) -> Nil
      }
    },
  )
  list.each([-42, 0, 42], fn(item) {
    codec.encode(generated, item) |> should.equal(codec.encode(runtime, item))
    codec.encode_json(generated, item)
    |> should.equal(codec.encode_json(runtime, item))
  })
  codec.schema(generated) |> should.equal(codec.schema(runtime))
}
