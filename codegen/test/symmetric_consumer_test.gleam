//// A separate package exercises the public runtime contract API.
//// This consumer needs no generator or internal runtime modules.

import gleeunit/should
import json/blueprint/codec.{Field, Index}
import json/blueprint/contract
import json/blueprint/value

pub fn main() {
  ordinary_dynamic_encoding_test()
  native_envelope_reports_nested_failure_and_allows_recovery_test()
  loaded_tagged_contract_preserves_exact_payload_and_locates_errors_test()
}

type Envelope {
  Envelope(id: String, results: List(value.Value))
}

fn parsed(text: String) -> value.Value {
  let assert Ok(raw) = value.parse(text, value.default_limits())
  raw
}

pub fn ordinary_dynamic_encoding_test() {
  let assert Ok(schema) = contract.from_codec(codec.string())
  let payload = contract.value_codec(schema)
  codec.encode_json(payload, value.String("ready"))
  |> should.equal(Ok("\"ready\""))
  codec.encode_json(payload, value.Bool(True))
  |> should.equal(Error(codec.EncodeError([], codec.ExpectedString)))
  codec.schema(payload) |> should.equal(Ok(contract.schema(schema)))
  codec.decode(payload, value.Bool(True))
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedString)))
}

pub fn native_envelope_reports_nested_failure_and_allows_recovery_test() {
  let assert Ok(schema) = contract.from_codec(codec.integer_between(1, 10))
  let envelope = {
    use id <- codec.field("id", codec.string(), get: fn(e: Envelope) { e.id })
    use results <- codec.field(
      "results",
      codec.list(contract.value_codec(schema)),
      get: fn(e) { e.results },
    )
    codec.success(Envelope(id, results))
  }
  let invalid = Envelope("request-1", [parsed("3"), parsed("99")])
  codec.encode_json(envelope, invalid)
  |> should.equal(
    Error(codec.EncodeError(
      [Field("results"), Index(1)],
      codec.IntegerOutsideRange(1, 10),
    )),
  )

  // The application recognizes a repairable field and supplies corrected data.
  let recovered = case codec.encode_json(envelope, invalid) {
    Error(codec.EncodeError(
      [Field("results"), Index(1)],
      codec.IntegerOutsideRange(1, 10),
    )) ->
      codec.encode_json(
        envelope,
        Envelope(..invalid, results: [parsed("3"), parsed("10")]),
      )
    other -> other
  }
  recovered |> should.equal(Ok("{\"id\":\"request-1\",\"results\":[3,10]}"))
  let assert Ok(text) = recovered
  codec.decode_json(envelope, text)
  |> should.equal(Ok(Envelope("request-1", [parsed("3"), parsed("10")])))
}

pub fn loaded_tagged_contract_preserves_exact_payload_and_locates_errors_test() {
  let document =
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
    <> "\"type\":\"object\",\"oneOf\":["
    <> "{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"measured\"},"
    <> "\"value\":{\"type\":\"number\",\"minimum\":1e399,\"maximum\":1e401}},"
    <> "\"required\":[\"tag\",\"value\"],\"additionalProperties\":false},"
    <> "{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"absent\"}},"
    <> "\"required\":[\"tag\"],\"additionalProperties\":false}]}"
  let assert Ok(schema) = contract.parse(document, value.default_limits())
  let payload = contract.value_codec(schema)
  let raw = parsed("{\"value\":1e400,\"tag\":\"measured\"}")
  codec.encode(payload, raw) |> should.equal(Ok(raw))
  codec.encode_json(payload, raw)
  |> should.equal(Ok("{\"value\":1e400,\"tag\":\"measured\"}"))
  codec.encode_json(payload, parsed("{\"tag\":\"absent\"}"))
  |> should.equal(Ok("{\"tag\":\"absent\"}"))
  codec.encode(payload, parsed("{\"tag\":\"measured\",\"value\":false}"))
  |> should.equal(
    Error(codec.EncodeError([Field("value")], codec.ExpectedNumber)),
  )
  codec.encode(payload, parsed("{\"tag\":\"unknown\"}"))
  |> should.equal(Error(codec.EncodeError([Field("tag")], codec.UnknownTag)))
}
