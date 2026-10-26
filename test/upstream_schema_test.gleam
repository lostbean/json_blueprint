// Derived from the pinned upstream files in test/oracle/upstream-schema/.
// Cases and adaptation rules are recorded in cases.json; expected verdicts are
// upstream-authored for unchanged cases and independently checked for adaptations.
import gleam/list
import gleam/result
import gleeunit/should
import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/value

fn check(schema_text: String, cases: List(#(String, Bool))) -> Nil {
  let assert Ok(schema_value) = value.parse(schema_text, value.default_limits())
  let assert Ok(loaded) = contract.load(schema_value)
  let dynamic = contract.value_codec(loaded)
  let assert Ok(rendered) = codec.schema_json(dynamic)
  let assert Ok(reloaded) = contract.parse(rendered, value.default_limits())
  contract.same_schema(loaded, reloaded) |> should.be_true
  list.each(cases, fn(item) {
    let #(text, expected) = item
    let assert Ok(raw) = value.parse(text, value.default_limits())
    contract.validate(loaded, raw) |> result.is_ok |> should.equal(expected)
    contract.validate(reloaded, raw) |> result.is_ok |> should.equal(expected)
    codec.decode(dynamic, raw) |> result.is_ok |> should.equal(expected)
    codec.decode_json(dynamic, text) |> result.is_ok |> should.equal(expected)
    codec.encode(dynamic, raw) |> result.is_ok |> should.equal(expected)
    case codec.encode_json(dynamic, raw) {
      Ok(encoded) -> {
        expected |> should.be_true
        codec.decode_json(dynamic, encoded) |> should.equal(Ok(raw))
      }
      Error(_) -> expected |> should.be_false
    }
  })
}

// integer type matches integers
pub fn type_0_unchanged_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"integer\"}",
    [
      // an integer is an integer
      #("1", True),
      // a float with zero fractional part is an integer
      #("1.0", True),
      // a float is not an integer
      #("1.1", False),
      // a string is not an integer
      #("\"foo\"", False),
      // a string is still not an integer, even if it looks like one
      #("\"1\"", False),
      // an object is not an integer
      #("{}", False),
      // an array is not an integer
      #("[]", False),
      // a boolean is not an integer
      #("true", False),
      // null is not an integer
      #("null", False),
    ],
  )
}

// number type matches numbers
pub fn type_1_unchanged_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"number\"}",
    [
      // an integer is a number
      #("1", True),
      // a float with zero fractional part is a number (and an integer)
      #("1.0", True),
      // a float is a number
      #("1.1", True),
      // a string is not a number
      #("\"foo\"", False),
      // a string is still not a number, even if it looks like one
      #("\"1\"", False),
      // an object is not a number
      #("{}", False),
      // an array is not a number
      #("[]", False),
      // a boolean is not a number
      #("true", False),
      // null is not a number
      #("null", False),
    ],
  )
}

// string type matches strings
pub fn type_2_unchanged_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"string\"}",
    [
      // 1 is not a string
      #("1", False),
      // a float is not a string
      #("1.1", False),
      // a string is a string
      #("\"foo\"", True),
      // a string is still a string, even if it looks like a number
      #("\"1\"", True),
      // an empty string is still a string
      #("\"\"", True),
      // an object is not a string
      #("{}", False),
      // an array is not a string
      #("[]", False),
      // a boolean is not a string
      #("true", False),
      // null is not a string
      #("null", False),
    ],
  )
}

// object type matches objects
pub fn type_3_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\"}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// array type matches arrays
pub fn type_4_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"array\"}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// boolean type matches booleans
pub fn type_5_unchanged_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"boolean\"}",
    [
      // an integer is not a boolean
      #("1", False),
      // zero is not a boolean
      #("0", False),
      // a float is not a boolean
      #("1.1", False),
      // a string is not a boolean
      #("\"foo\"", False),
      // an empty string is not a boolean
      #("\"\"", False),
      // an object is not a boolean
      #("{}", False),
      // an array is not a boolean
      #("[]", False),
      // true is a boolean
      #("true", True),
      // false is a boolean
      #("false", True),
      // null is not a boolean
      #("null", False),
    ],
  )
}

// null type matches only the null object
pub fn type_6_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"null\"}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// multiple types can be specified in an array
pub fn type_7_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":[\"integer\",\"string\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// type as array with one item
pub fn type_8_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":[\"string\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// type: array or object
pub fn type_9_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":[\"array\",\"object\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// type: array, object or null
pub fn type_10_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":[\"array\",\"object\",\"null\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// a schema given for items
pub fn items_0_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":{\"type\":\"integer\"}}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// items with boolean schema (true)
pub fn items_1_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":true}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// items with boolean schema (false)
pub fn items_2_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":false}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// items and subitems
pub fn items_3_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$defs\":{\"item\":{\"type\":\"array\",\"items\":false,\"prefixItems\":[{\"$ref\":\"#/$defs/sub-item\"},{\"$ref\":\"#/$defs/sub-item\"}]},\"sub-item\":{\"type\":\"object\",\"required\":[\"foo\"]}},\"type\":\"array\",\"items\":false,\"prefixItems\":[{\"$ref\":\"#/$defs/item\"},{\"$ref\":\"#/$defs/item\"},{\"$ref\":\"#/$defs/item\"}]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// nested items
pub fn items_4_unchanged_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"array\",\"items\":{\"type\":\"array\",\"items\":{\"type\":\"array\",\"items\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}}}",
    [
      // valid nested array
      #("[[[[1]],[[2],[3]]],[[[4],[5],[6]]]]", True),
      // nested array with invalid type
      #("[[[[\"1\"]],[[2],[3]]],[[[4],[5],[6]]]]", False),
      // not deep enough
      #("[[[1],[2],[3]],[[4],[5],[6]]]", False),
    ],
  )
}

// prefixItems with no additional items allowed
pub fn items_5_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"prefixItems\":[{},{},{}],\"items\":false}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// items does not look in applicators, valid case
pub fn items_6_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"allOf\":[{\"prefixItems\":[{\"minimum\":3}]}],\"items\":{\"minimum\":5}}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// prefixItems validation adjusts the starting index for items
pub fn items_7_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"prefixItems\":[{\"type\":\"string\"}],\"items\":{\"type\":\"integer\"}}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// items with heterogeneous array
pub fn items_8_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"prefixItems\":[{}],\"items\":false}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// items with null instance elements
pub fn items_9_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":{\"type\":\"null\"}}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// enum with escaped characters
pub fn enum_4_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"enum\":[\"foo\\nbar\",\"foo\\rbar\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// enum with escaped characters
// Add explicit string type; upstream instance verdicts are unchanged.
pub fn enum_4_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"enum\":[\"foo\\nbar\",\"foo\\rbar\"],\"type\":\"string\"}",
    [
      // member 1 is valid
      #("\"foo\\nbar\"", True),
      // member 2 is valid
      #("\"foo\\rbar\"", True),
      // another string is invalid
      #("\"abc\"", False),
    ],
  )
}

// minimum validation
pub fn minimum_0_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"minimum\":1.1}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// minimum validation
// Add explicit number type and a nonbinding opposite bound. Non-number instances now reject; expected outcomes independently evaluated with Draft202012Validator.
pub fn minimum_0_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"minimum\":1.1,\"type\":\"number\",\"maximum\":1000000}",
    [
      // above the minimum is valid
      #("2.6", True),
      // boundary point is valid
      #("1.1", True),
      // below the minimum is invalid
      #("0.6", False),
      // ignores non-numbers
      #("\"x\"", False),
    ],
  )
}

// minimum validation with signed integer
pub fn minimum_1_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"minimum\":-2}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// minimum validation with signed integer
// Add explicit number type and a nonbinding opposite bound. Non-number instances now reject; expected outcomes independently evaluated with Draft202012Validator.
pub fn minimum_1_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"minimum\":-2,\"type\":\"number\",\"maximum\":1000000}",
    [
      // negative above the minimum is valid
      #("-1", True),
      // positive above the minimum is valid
      #("0", True),
      // boundary point is valid
      #("-2", True),
      // boundary point with float is valid
      #("-2.0", True),
      // float below the minimum is invalid
      #("-2.0001", False),
      // int below the minimum is invalid
      #("-3", False),
      // ignores non-numbers
      #("\"x\"", False),
    ],
  )
}

// maximum validation
pub fn maximum_0_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"maximum\":3.0}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// maximum validation
// Add explicit number type and a nonbinding opposite bound. Non-number instances now reject; expected outcomes independently evaluated with Draft202012Validator.
pub fn maximum_0_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"maximum\":3.0,\"type\":\"number\",\"minimum\":-1000000}",
    [
      // below the maximum is valid
      #("2.6", True),
      // boundary point is valid
      #("3.0", True),
      // above the maximum is invalid
      #("3.5", False),
      // ignores non-numbers
      #("\"x\"", False),
    ],
  )
}

// maximum validation with unsigned integer
pub fn maximum_1_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"maximum\":300}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// maximum validation with unsigned integer
// Add explicit number type and a nonbinding opposite bound. Non-number instances now reject; expected outcomes independently evaluated with Draft202012Validator.
pub fn maximum_1_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"maximum\":300,\"type\":\"number\",\"minimum\":-1000000}",
    [
      // below the maximum is valid
      #("299.97", True),
      // boundary point integer is valid
      #("300", True),
      // boundary point float is valid
      #("300.0", True),
      // above the maximum is invalid
      #("300.5", False),
    ],
  )
}

// required validation
pub fn required_0_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"properties\":{\"foo\":{},\"bar\":{}},\"required\":[\"foo\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// required validation
// Add explicit object type, properties, required, and closed-object policy. Upstream instances are retained; changed acceptance independently evaluated with Draft202012Validator.
pub fn required_0_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"properties\":{\"foo\":{},\"bar\":{}},\"required\":[\"foo\"],\"type\":\"object\",\"additionalProperties\":false}",
    [
      // present required property is valid
      #("{\"foo\":1}", True),
      // non-present required property is invalid
      #("{\"bar\":1}", False),
      // ignores arrays
      #("[]", False),
      // ignores strings
      #("\"\"", False),
      // ignores other non-objects
      #("12", False),
      // ignores null
      #("null", False),
      // ignores boolean
      #("true", False),
    ],
  )
}

// required default validation
pub fn required_1_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"properties\":{\"foo\":{}}}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// required default validation
// Add explicit object type, properties, required, and closed-object policy. Upstream instances are retained; changed acceptance independently evaluated with Draft202012Validator.
pub fn required_1_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"properties\":{\"foo\":{}},\"type\":\"object\",\"additionalProperties\":false,\"required\":[]}",
    [
      // not required by default
      #("{}", True),
    ],
  )
}

// required with empty array
pub fn required_2_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"properties\":{\"foo\":{}},\"required\":[]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// required with empty array
// Add explicit object type, properties, required, and closed-object policy. Upstream instances are retained; changed acceptance independently evaluated with Draft202012Validator.
pub fn required_2_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"properties\":{\"foo\":{}},\"required\":[],\"type\":\"object\",\"additionalProperties\":false}",
    [
      // property not required
      #("{}", True),
    ],
  )
}

// required with escaped characters
pub fn required_3_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"required\":[\"foo\\nbar\",\"foo\\\"bar\",\"foo\\\\bar\",\"foo\\rbar\",\"foo\\tbar\",\"foo\\fbar\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// required with escaped characters
// Add explicit object type, properties, required, and closed-object policy. Upstream instances are retained; changed acceptance independently evaluated with Draft202012Validator.
pub fn required_3_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"required\":[\"foo\\nbar\",\"foo\\\"bar\",\"foo\\\\bar\",\"foo\\rbar\",\"foo\\tbar\",\"foo\\fbar\"],\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"foo\\nbar\":{},\"foo\\\"bar\":{},\"foo\\\\bar\":{},\"foo\\rbar\":{},\"foo\\tbar\":{},\"foo\\fbar\":{}}}",
    [
      // object with all properties present is valid
      #(
        "{\"foo\\nbar\":1,\"foo\\\"bar\":1,\"foo\\\\bar\":1,\"foo\\rbar\":1,\"foo\\tbar\":1,\"foo\\fbar\":1}",
        True,
      ),
      // object with some properties missing is invalid
      #("{\"foo\\nbar\":\"1\",\"foo\\\"bar\":\"1\"}", False),
    ],
  )
}

// required properties whose names are Javascript object property names
pub fn required_4_unsupported_test() -> Nil {
  let assert Ok(raw) =
    value.parse(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"required\":[\"__proto__\",\"toString\",\"constructor\"]}",
      value.default_limits(),
    )
  let assert Error(contract.UnsupportedDocument(_, _)) = contract.load(raw)
  Nil
}

// required properties whose names are Javascript object property names
// Add explicit object type, properties, required, and closed-object policy. Upstream instances are retained; changed acceptance independently evaluated with Draft202012Validator.
pub fn required_4_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"required\":[\"__proto__\",\"toString\",\"constructor\"],\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"__proto__\":{},\"toString\":{},\"constructor\":{}}}",
    [
      // ignores arrays
      #("[]", False),
      // ignores other non-objects
      #("12", False),
      // none of the properties mentioned
      #("{}", False),
      // __proto__ present
      #("{\"__proto__\":\"foo\"}", False),
      // toString present
      #("{\"toString\":{\"length\":37}}", False),
      // constructor present
      #("{\"constructor\":{\"length\":37}}", False),
      // all present
      #(
        "{\"__proto__\":12,\"toString\":{\"length\":\"foo\"},\"constructor\":37}",
        True,
      ),
    ],
  )
}

// a schema given for items
// Add explicit array type; non-array instances now reject, other upstream verdicts unchanged.
pub fn items_0_adapted_test() -> Nil {
  check(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"items\":{\"type\":\"integer\"},\"type\":\"array\"}",
    [
      // valid items
      #("[1,2,3]", True),
      // wrong type of items
      #("[1,\"x\"]", False),
      // ignores non-arrays
      #("{\"foo\":\"bar\"}", False),
      // JavaScript pseudo-array is valid
      #("{\"0\":\"invalid\",\"length\":1}", False),
    ],
  )
}
