//// Public-consumer regressions for finite-profile admission diagnostics.

import gleam/list
import gleam/string
import gleeunit/should
import json/blueprint/codec.{Field}
import json/blueprint/contract
import json/blueprint/value

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file(path: String) -> Result(String, String)

type Fixture {
  Fixture(name: String, schema: value.Value, kind: String, path: String)
}

fn fixture_codec() -> codec.Codec(Fixture) {
  use name <- codec.field("name", codec.string(), get: fn(f) { f.name })
  use schema <- codec.field("schema", codec.value(), get: fn(f) { f.schema })
  use kind <- codec.field("kind", codec.string(), get: fn(f) { f.kind })
  use path <- codec.field("path", codec.string(), get: fn(f) { f.path })
  codec.success(Fixture(name, schema, kind, path))
}

pub fn profile_fixture_classification_test() {
  let assert Ok(text) = read_file("test/contract_profile_cases.json")
  let assert Ok(fixtures) = codec.decode_json(codec.list(fixture_codec()), text)
  list.each(fixtures, fn(fixture) {
    let outcome = contract.load(fixture.schema)
    let kind = case outcome {
      Ok(_) -> "accepted"
      Error(contract.UnsupportedDocument(..)) -> "unsupported"
      Error(contract.MalformedDocument(..)) -> "malformed"
      Error(_) -> "other"
    }
    #(fixture.name, kind) |> should.equal(#(fixture.name, fixture.kind))
    case outcome {
      Error(error) -> {
        let diagnostic = contract.describe_document_error(error)
        #(fixture.name, string.starts_with(diagnostic, fixture.path <> ":"))
        |> should.equal(#(fixture.name, True))
      }
      Ok(_) -> Nil
    }
  })
}

fn document(members: String) -> String {
  "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
  <> members
  <> "}"
}

pub fn default_open_object_is_unsupported_test() {
  contract.parse(
    document("\"type\":\"object\",\"properties\":{},\"required\":[]"),
    value.default_limits(),
  )
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.UnsupportedDocument(
        [Field("additionalProperties")],
        contract.OpenObject,
      )),
    ),
  )
}

type Request {
  Request(name: String)
}

pub fn supported_closed_object_preserves_native_decoding_and_rejection_test() {
  let native = {
    use name <- codec.field("name", codec.string(), get: fn(r) { r.name })
    codec.success(Request(name))
  }
  let limits = value.default_limits() |> value.with_max_depth(8)
  let assert Ok(remote) =
    contract.parse(
      document(
        "\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},"
        <> "\"required\":[\"name\"],\"additionalProperties\":false",
      ),
      limits,
    )
  let assert Ok(arguments) = value.parse("{\"name\":\"Ada\"}", limits)
  let assert Ok(checked) = contract.validate(remote, arguments)
  contract.decode(native, checked) |> should.equal(Ok(Request("Ada")))
  let assert Ok(extra) =
    value.parse("{\"name\":\"Ada\",\"extra\":true}", limits)
  contract.validate(remote, extra)
  |> should.equal(
    Error(contract.ValidationError([Field("extra")], codec.UnknownField)),
  )
  contract.validate(remote, value.Object([]))
  |> should.equal(
    Error(contract.ValidationError([Field("name")], codec.MissingField)),
  )
}

@target(javascript)
pub fn integer_bound_outside_native_representation_is_unsupported_test() {
  contract.parse(
    document("\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740993"),
    value.default_limits(),
  )
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.UnsupportedDocument(
        [Field("maximum")],
        contract.UnsupportedSchemaForm,
      )),
    ),
  )
}

@target(erlang)
pub fn erlang_keeps_large_integer_bound_acceptance_test() {
  contract.parse(
    document("\"type\":\"integer\",\"minimum\":0,\"maximum\":9007199254740993"),
    value.default_limits(),
  )
  |> should.be_ok
}

pub fn nonnative_tuple_length_is_unsupported_test() {
  let assert Error(contract.InvalidDocument(contract.UnsupportedDocument(..))) =
    contract.parse(
      document(
        "\"type\":\"array\",\"prefixItems\":[{},{}],\"minItems\":2,\"maxItems\":9007199254740993",
      ),
      value.default_limits(),
    )
}

pub fn negative_tuple_length_remains_malformed_before_native_projection_test() {
  contract.parse(
    document(
      "\"type\":\"array\",\"prefixItems\":[{},{}],\"minItems\":-9007199254740993,\"maxItems\":2",
    ),
    value.default_limits(),
  )
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.MalformedDocument(
        [Field("minItems")],
        contract.InvalidTupleShape,
      )),
    ),
  )
}
