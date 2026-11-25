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

fn count_failure(max: Int) -> Result(a, value.ParseError) {
  Error(value.ParseError(value.Location(0, 0, 0), value.ValueLimitExceeded(max)))
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

pub fn value_limit_counts_every_value_including_containers_test() {
  // The array, its two numbers, the object and its string: five values.
  let source = "[1,2,{\"k\":\"v\"}]"
  let five = value.default_limits() |> value.with_max_values(5)
  value.parse(source, five) |> should.be_ok
  value.parse(source, value.with_max_values(five, 4))
  |> should.equal(count_failure(4))
  value.parse("null", value.with_max_values(five, 1)) |> should.be_ok
  value.parse("null", value.with_max_values(five, 0))
  |> should.equal(count_failure(0))
  value.parse("[]", value.with_max_values(five, 1)) |> should.be_ok
  value.parse("[[]]", value.with_max_values(five, 1))
  |> should.equal(count_failure(1))
}

pub fn structural_limits_apply_together_and_keep_the_byte_bound_test() {
  let limits =
    value.default_limits()
    |> value.with_max_depth(2)
    |> value.with_max_values(4)
    |> value.with_max_bytes(16)
  value.parse("[[1,2]]", limits) |> should.be_ok
  value.parse("[[[1]]]", limits) |> should.equal(depth_failure(2))
  value.parse("[[1,2,3]]", limits) |> should.equal(count_failure(4))
  let assert Error(value.ParseError(_, value.ByteLimitExceeded(16))) =
    value.parse("[[1,2]]          ", limits)
  // Setting the byte bound last must not clear the structural bounds.
  let assert Error(error) =
    value.parse_bits(bit_array.from_string("[[[1]]]"), limits)
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
  let assert Error(error) = value.parse("[1,2,3,4]", limits)
  value.is_limit_exceeded(error) |> should.be_true
  value.describe_parse_error(error)
  |> should.equal("invalid JSON: more than 4 values (value.with_max_values)")
}

pub fn structural_limits_keep_duplicate_and_syntax_rejection_test() {
  let limits =
    value.default_limits()
    |> value.with_max_depth(8)
    |> value.with_max_values(64)
  let assert Error(value.ParseError(_, value.DuplicateObjectKey)) =
    value.parse("{\"a\":1,\"\\u0061\":[2]}", limits)
  let assert Error(value.ParseError(_, value.NativeSyntax)) =
    value.parse("[1,", limits)
  let assert Error(value.ParseError(_, value.NativeSyntax)) =
    value.parse("[1] 2", limits)
  value.parse(" {\"n\":12.50,\"e\":[]} ", limits)
  |> should.equal(value.parse(
    " {\"n\":12.50,\"e\":[]} ",
    value.default_limits(),
  ))
}

pub fn deep_document_is_refused_as_a_limit_not_a_capacity_failure_test() {
  // Without a depth bound this document exhausts the JavaScript stack.
  let limits = value.default_limits() |> value.with_max_depth(128)
  value.parse(nested(200_000, "0"), limits) |> should.equal(depth_failure(128))
}

pub fn codec_and_contract_text_entry_points_honour_structural_limits_test() {
  let limits =
    value.default_limits()
    |> value.with_max_depth(1)
    |> value.with_max_values(3)
  let numbers = codec.list(codec.int())
  codec.decode_json_with_limits(numbers, "[1,2]", limits)
  |> should.equal(Ok([1, 2]))
  let assert Error(error) =
    codec.decode_json_with_limits(numbers, "[1,2,3]", limits)
  error
  |> should.equal(codec.DecodeError(
    [],
    codec.InvalidJson(value.ParseError(
      value.Location(0, 0, 0),
      value.ValueLimitExceeded(3),
    )),
  ))
  codec.is_limit_exceeded(error) |> should.be_true
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
