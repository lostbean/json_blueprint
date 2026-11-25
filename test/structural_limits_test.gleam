import gleam/bit_array
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/value

fn nested(depth: Int, inner: String) -> String {
  string.repeat("[", depth) <> inner <> string.repeat("]", depth)
}

fn depth_failure(max: Int) -> Result(a, value.ParseError) {
  Error(value.ParseError(value.Location(0, 0, 0), value.DepthLimitExceeded(max)))
}

pub fn default_limits_admit_depth_128_and_refuse_129_test() {
  let limits = value.default_limits()
  value.parse(nested(128, "0"), limits) |> should.be_ok
  value.parse(nested(129, "0"), limits) |> should.equal(depth_failure(128))
  value.parse_bits(bit_array.from_string(nested(129, "")), limits)
  |> should.equal(depth_failure(128))
}

pub fn depth_limit_admits_the_limit_and_rejects_one_level_more_test() {
  let limits = value.default_limits() |> value.with_max_depth(3)
  value.parse(nested(3, "0"), limits) |> should.be_ok
  value.parse(nested(4, "0"), limits) |> should.equal(depth_failure(3))
  value.parse(nested(4, ""), limits) |> should.equal(depth_failure(3))
  // Objects and arrays both count, and siblings do not add up.
  value.parse("{\"a\":[{\"b\":1}],\"c\":[[2],[3]]}", limits) |> should.be_ok
  value.parse("{\"a\":[{\"b\":[1]}]}", limits)
  |> should.equal(depth_failure(3))
  // Brackets inside strings and names are text, not structure.
  value.parse("{\"[[[[\":\"[[[[{{{{\\\"[[[[\"}", limits) |> should.be_ok
}

pub fn depth_limit_zero_admits_only_a_scalar_root_test() {
  let limits = value.default_limits() |> value.with_max_depth(0)
  value.parse("\"text\"", limits) |> should.equal(Ok(value.String("text")))
  value.parse("[]", limits) |> should.equal(depth_failure(0))
  value.parse("{}", limits) |> should.equal(depth_failure(0))
  value.parse("1", value.with_max_depth(limits, -1))
  |> should.equal(depth_failure(-1))
}

pub fn unlimited_admits_deep_and_large_documents_test() {
  let limits = value.unlimited()
  value.parse(nested(1000, "0"), limits) |> should.be_ok
  let large = string.repeat(" ", 1_100_000) <> "[1]"
  value.parse(large, limits) |> should.be_ok
  // Either bound can be added back to an unlimited value on its own.
  value.parse(large, value.with_max_depth(limits, 1)) |> should.be_ok
  let assert Error(value.ParseError(_, value.ByteLimitExceeded(16))) =
    value.parse(large, value.with_max_bytes(limits, 16))
  value.parse(nested(1000, "0"), value.with_max_bytes(limits, 16))
  |> should.be_error
  value.parse(nested(1000, "0"), value.with_max_bytes(limits, 4096))
  |> should.be_ok
}

pub fn depth_and_byte_bounds_apply_together_test() {
  let limits =
    value.default_limits()
    |> value.with_max_depth(2)
    |> value.with_max_bytes(16)
  value.parse("[[1,2]]", limits) |> should.be_ok
  value.parse("[[[1]]]", limits) |> should.equal(depth_failure(2))
  let assert Error(value.ParseError(_, value.ByteLimitExceeded(16))) =
    value.parse("[[1,2]]          ", limits)
  // Setting the byte bound last must not clear the depth bound.
  let assert Error(error) =
    value.parse_bits(
      bit_array.from_string("[[[1]]]"),
      value.default_limits()
        |> value.with_max_depth(2)
        |> value.with_max_bytes(16),
    )
  error
  |> should.equal(value.ParseError(
    value.Location(0, 0, 0),
    value.DepthLimitExceeded(2),
  ))
  value.is_limit_exceeded(error) |> should.be_true
  value.describe_parse_error(error)
  |> should.equal(
    "invalid JSON: nested more than 2 levels deep (value.with_max_depth)",
  )
}

pub fn depth_limit_keeps_duplicate_and_syntax_rejection_test() {
  let limits = value.default_limits() |> value.with_max_depth(8)
  let assert Error(value.ParseError(_, value.DuplicateObjectKey)) =
    value.parse("{\"a\":1,\"\\u0061\":[2]}", limits)
  let assert Error(value.ParseError(_, value.NativeSyntax)) =
    value.parse("[1,", limits)
  let assert Error(value.ParseError(_, value.NativeSyntax)) =
    value.parse("[1] 2", limits)
  value.parse(" {\"n\":12.50,\"e\":[]} ", limits)
  |> should.equal(value.parse(" {\"n\":12.50,\"e\":[]} ", value.unlimited()))
}

pub fn deep_document_is_refused_as_a_limit_not_a_capacity_failure_test() {
  // Without a depth bound this document exhausts the JavaScript stack.
  value.parse(nested(200_000, "0"), value.default_limits())
  |> should.equal(depth_failure(128))
}

pub fn codec_and_contract_text_entry_points_bound_depth_by_default_test() {
  let assert Error(error) = codec.decode_json(codec.value(), nested(129, "0"))
  error
  |> should.equal(codec.DecodeError(
    [],
    codec.InvalidJson(value.ParseError(
      value.Location(0, 0, 0),
      value.DepthLimitExceeded(128),
    )),
  ))
  codec.is_limit_exceeded(error) |> should.be_true
  codec.decode_json(codec.value(), nested(128, "0")) |> should.be_ok
  codec.decode_json_with_limits(
    codec.value(),
    nested(129, "0"),
    value.unlimited(),
  )
  |> should.be_ok
  let shallow = value.default_limits() |> value.with_max_depth(1)
  let schema =
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
    <> "\"type\":\"array\",\"items\":{\"type\":\"string\"}}"
  let assert Error(contract.InvalidJson(value.ParseError(
    _,
    value.DepthLimitExceeded(1),
  ))) = contract.parse(schema, shallow)
  contract.parse(schema, value.with_max_depth(shallow, 2)) |> should.be_ok
}
