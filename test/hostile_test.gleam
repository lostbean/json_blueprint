import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec.{Field}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

fn default_test_limits() -> value.Limits {
  value.default_limits()
  |> value.with_max_bytes(1_000_000)
  |> value.with_max_depth(64)
  |> value.with_number_limits(default_number_limits())
}

fn default_number_limits() -> number.Limits {
  number.limits(
    max_token_bytes: 1024,
    max_significant_digits: 100,
    max_exponent: 1000,
  )
}

// Deterministic PRNG for bounded property generation (32-bit LCG)
type Prng {
  Prng(state: Int)
}

fn prng_new(seed: Int) -> Prng {
  Prng(state: seed)
}

fn prng_next_int(prng: Prng, min: Int, max: Int) -> #(Int, Prng) {
  let span = max - min + 1
  let next_state = { prng.state * 1_103_515_245 + 12_345 } % 2_147_483_647
  let safe_state = case next_state < 0 {
    True -> 0 - next_state
    False -> next_state
  }
  let val = min + { safe_state % span }
  #(val, Prng(safe_state))
}

pub type Side {
  Left(Int)
  Right(String)
  Neither
}

fn side_codec() -> codec.Codec(Side) {
  codec.union({
    use left <- codec.variant("left", codec.int(), Left)
    use right <- codec.variant("right", codec.string(), Right)
    use neither <- codec.unit_variant("neither", Neither)
    codec.match(fn(side) {
      case side {
        Left(n) -> left(n)
        Right(s) -> right(s)
        Neither -> neither
      }
    })
  })
}

pub fn codec_roundtrip_laws_property_test() {
  // 1. Integer codec: edge values + deterministic generated safe integer corpus
  let int_c = codec.int()
  let int_edge_cases = [
    0,
    1,
    -1,
    42,
    -42,
    128,
    -128,
    32_767,
    -32_768,
    2_147_483_647,
    -2_147_483_648,
    9_007_199_254_740_991,
    -9_007_199_254_740_991,
  ]
  // Generate 50 additional deterministic integers within safe bounds
  let #(generated_ints, _) =
    list.fold(list.repeat(Nil, 50), #([], prng_new(12_345)), fn(acc, _) {
      let #(n, next_prng) = prng_next_int(acc.1, -1_000_000_000, 1_000_000_000)
      #([n, ..acc.0], next_prng)
    })
  let all_ints = list.append(int_edge_cases, generated_ints)

  list.each(all_ints, fn(i) {
    // Identity law: decode(encode(v)) == Ok(v)
    let assert Ok(encoded) = codec.encode(int_c, i)
    let assert Ok(decoded) = codec.decode(int_c, encoded)
    decoded |> should.equal(i)

    // Idempotence: encode(decode(enc)) == Ok(enc)
    let assert Ok(re_encoded) = codec.encode(int_c, decoded)
    re_encoded |> should.equal(encoded)

    // Through text as well
    let assert Ok(text) = codec.encode_json(int_c, i)
    codec.decode_json(int_c, text) |> should.equal(Ok(i))
  })

  // 2. String codec: edge values + unicode + escapes
  let str_c = codec.string()
  let str_edge_cases = [
    "",
    "a",
    "hello",
    "with spaces and tabs\t\t",
    "newlines\r\nand\nlines",
    "quotes \"and\" \\backslashes\\",
    "unicode: 雪猫 🚀 àéîôù",
    "json-like: {\"key\": [1, true, null]}",
    "control: \u{0001}\u{001F}",
  ]
  list.each(str_edge_cases, fn(s) {
    let assert Ok(encoded) = codec.encode(str_c, s)
    let assert Ok(decoded) = codec.decode(str_c, encoded)
    decoded |> should.equal(s)
    let assert Ok(text) = codec.encode_json(str_c, s)
    codec.decode_json(str_c, text) |> should.equal(Ok(s))
  })

  // 3. Boolean codec: True and False roundtrip
  let bool_c = codec.bool()
  list.each([True, False], fn(b) {
    let assert Ok(encoded) = codec.encode(bool_c, b)
    let assert Ok(decoded) = codec.decode(bool_c, encoded)
    decoded |> should.equal(b)
  })

  // 4. List codec composition over generated ints and strings
  let list_int_c = codec.list(int_c)
  let list_cases = [[], [0], [1, 2, 3], [-10, 0, 10, 20, 30], int_edge_cases]
  list.each(list_cases, fn(l) {
    let assert Ok(encoded) = codec.encode(list_int_c, l)
    let assert Ok(decoded) = codec.decode(list_int_c, encoded)
    decoded |> should.equal(l)
  })

  // 5. Nullable codec composition
  let null_str_c = codec.nullable(str_c)
  let null_cases = [None, Some(""), Some("present"), Some("雪猫")]
  list.each(null_cases, fn(n) {
    let assert Ok(encoded) = codec.encode(null_str_c, n)
    let assert Ok(decoded) = codec.decode(null_str_c, encoded)
    decoded |> should.equal(n)
  })

  // 6. Pair codec composition
  let pair_c = codec.pair(str_c, int_c)
  let pair_cases = [
    #("", 0),
    #("alpha", 1),
    #("beta", -42),
    #("unicode", 9_007_199_254_740_991),
  ]
  list.each(pair_cases, fn(p) {
    let assert Ok(encoded) = codec.encode(pair_c, p)
    let assert Ok(decoded) = codec.decode(pair_c, encoded)
    decoded |> should.equal(p)
  })

  // 7. Integer range roundtrip for values in bounds [-50, 50]
  let range_c = codec.integer_between(-50, 50)
  let range_valid_cases = [-50, -49, -25, -1, 0, 1, 25, 49, 50]
  list.each(range_valid_cases, fn(v) {
    let assert Ok(encoded) = codec.encode(range_c, v)
    let assert Ok(decoded) = codec.decode(range_c, encoded)
    decoded |> should.equal(v)
  })

  // 8. Union codec with payload and unit variants
  let side_cases = [Left(0), Left(-7), Right(""), Right("雪猫"), Neither]
  list.each(side_cases, fn(s) {
    let assert Ok(encoded) = codec.encode(side_codec(), s)
    let assert Ok(decoded) = codec.decode(side_codec(), encoded)
    decoded |> should.equal(s)
  })
  codec.encode_json(side_codec(), Neither)
  |> should.equal(Ok("{\"tag\":\"neither\"}"))
  codec.encode_json(side_codec(), Left(3))
  |> should.equal(Ok("{\"tag\":\"left\",\"value\":3}"))
}

pub fn codec_rejection_laws_property_test() {
  // 1. Integer Range Rejection Law: values outside [-50, 50] must be rejected by both encode and decode
  let range_c = codec.integer_between(-50, 50)
  let out_of_range_values = [
    -51,
    -52,
    -100,
    -1000,
    51,
    52,
    100,
    1000,
    9_007_199_254_740_991,
    -9_007_199_254_740_991,
  ]
  list.each(out_of_range_values, fn(bad_val) {
    // Encode rejection
    codec.encode(range_c, bad_val)
    |> should.equal(
      Error(codec.EncodeError([], codec.IntegerOutsideRange(-50, 50))),
    )

    // Decode rejection
    let assert Ok(bad_num) = number.from_int(bad_val)
    codec.decode(range_c, value.Number(bad_num))
    |> should.equal(
      Error(codec.DecodeError([], codec.IntegerOutsideRange(-50, 50))),
    )
  })

  // Integers far beyond any native range are rejected without conversion
  let assert Ok(huge) = number.parse("1e900", number.default_limits())
  codec.decode(range_c, value.Number(huge))
  |> should.equal(
    Error(codec.DecodeError([], codec.IntegerOutsideRange(-50, 50))),
  )
  codec.decode(codec.int(), value.Number(huge))
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedInt)))

  // 2. String Enum Domain Rejection Law: strings not in domain must be rejected
  let enum_c =
    codec.string_enum([#("red", "Red"), #("green", "Green"), #("blue", "Blue")])
  let disallowed_enum_strings = [
    "", "RED", "Green", "BLUE", "yellow", "red\n", " blue", "blue ", "1",
  ]
  list.each(disallowed_enum_strings, fn(bad_str) {
    codec.decode(enum_c, value.String(bad_str))
    |> should.equal(Error(codec.DecodeError([], codec.UnknownEnumLabel)))
  })
  codec.encode(enum_c, "Purple")
  |> should.equal(Error(codec.EncodeError([], codec.UnknownEnumValue)))

  // 3. Type Mismatch Rejection Law: passing wrong value variant must return Expected*
  let int_c = codec.int()
  let str_c = codec.string()
  let bool_c = codec.bool()

  // Null where int expected
  codec.decode(int_c, value.Null)
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedInt)))

  // Bool where string expected
  codec.decode(str_c, value.Bool(True))
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedString)))

  // String where bool expected
  codec.decode(bool_c, value.String("true"))
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedBool)))

  // Array where object expected
  let obj_c = {
    use id <- codec.field("id", int_c, get: fn(id) { id })
    codec.success(id)
  }
  codec.decode(obj_c, value.Array([]))
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedObject)))

  // 4. Tagged Union Discriminator Rejection Law
  let assert Ok(num1) = number.from_int(1)

  // Non-string discriminator tag
  codec.decode(
    side_codec(),
    value.Object([#("tag", value.Number(num1)), #("value", value.String("val"))]),
  )
  |> should.equal(
    Error(codec.DecodeError([Field("tag")], codec.ExpectedString)),
  )

  // Unknown tag
  codec.decode(
    side_codec(),
    value.Object([#("tag", value.String("unknown")), #("value", value.Null)]),
  )
  |> should.equal(Error(codec.DecodeError([Field("tag")], codec.UnknownTag)))

  // Missing tag
  codec.decode(side_codec(), value.Object([#("value", value.Null)]))
  |> should.equal(Error(codec.DecodeError([Field("tag")], codec.MissingField)))

  // A unit variant with a value, and a payload variant without one
  codec.decode(
    side_codec(),
    value.Object([#("tag", value.String("neither")), #("value", value.Null)]),
  )
  |> should.equal(
    Error(codec.DecodeError([Field("value")], codec.UnknownField)),
  )
  codec.decode(side_codec(), value.Object([#("tag", value.String("left"))]))
  |> should.equal(
    Error(codec.DecodeError([Field("value")], codec.MissingField)),
  )

  // Extra members
  codec.decode(
    side_codec(),
    value.Object([
      #("tag", value.String("neither")),
      #("__proto__", value.Null),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeError([Field("__proto__")], codec.UnknownField)),
  )
}

pub fn hostile_depth_boundary_test() {
  // Exactly at limit vs 1 beyond limit
  let limits =
    value.default_limits()
    |> value.with_max_bytes(10_000)
    |> value.with_max_depth(3)
    |> value.with_number_limits(default_number_limits())

  // Depth 3: [[[1]]] -> parsed array depth is 3 -> accepted
  value.parse("[[[1]]]", limits)
  |> should.be_ok

  // Depth 4: [[[[1]]]] -> parsed array depth is 4 > max_depth 3 -> rejected
  case value.parse("[[[[1]]]]", limits) {
    Error(value.ParseError(_, value.DepthLimitExceeded(3))) -> Nil
    _ -> panic as "expected depth limit 3 exceeded"
  }

  // Codecs decoding text use the same bound
  let nested = codec.list(codec.list(codec.list(codec.int())))
  codec.decode_json_with_limits(nested, "[[[1]]]", limits)
  |> should.equal(Ok([[[1]]]))
  let assert Error(error) =
    codec.decode_json_with_limits(codec.list(nested), "[[[[1]]]]", limits)
  codec.is_limit_exceeded(error) |> should.be_true

  // Very deep input stops at the default depth without recursion trouble
  let deep = string.repeat("[", 100_000) <> string.repeat("]", 100_000)
  case value.parse(deep, value.default_limits()) {
    Error(value.ParseError(_, value.DepthLimitExceeded(64))) -> Nil
    _ -> panic as "expected default depth limit 64 exceeded"
  }
}

pub fn hostile_wide_document_test() {
  let limits = default_test_limits()

  // Construct a wide JSON object with 100 distinct properties
  let pairs =
    list.index_map(list.repeat(Nil, 100), fn(_, i) {
      let idx = int.to_string(i + 1)
      "\"prop_" <> idx <> "\": " <> idx
    })
  let wide_json = "{" <> string.join(pairs, ", ") <> "}"

  let assert Ok(val) = value.parse(wide_json, limits)
  case val {
    value.Object(entries) -> list.length(entries) |> should.equal(100)
    _ -> panic as "expected object with 100 entries"
  }

  // The element limit bounds wide documents
  case value.parse(wide_json, limits |> value.with_max_elements(100)) {
    Error(value.ParseError(_, value.ElementLimitExceeded(100))) -> Nil
    _ -> panic as "expected element limit 100 exceeded"
  }
}

pub fn hostile_nested_duplicate_keys_test() {
  let limits = default_test_limits()

  // Duplicate key nested inside an array
  let nested_json = "[1, {\"a\": 10, \"b\": 20, \"a\": 30}]"
  case value.parse(nested_json, limits) {
    Error(value.ParseError(loc, value.DuplicateObjectKey)) -> {
      loc.line |> should.equal(1)
      loc.byte_offset |> should.equal(23)
    }
    _ -> panic as "expected duplicate key inside array"
  }

  // `value.object` refuses a repeated key in a value built by hand
  value.object([#("a", value.Null), #("a", value.Bool(True))])
  |> should.equal(Error(value.DuplicateKey("a")))
}

pub fn hostile_numeric_limits_test() {
  let short_limits =
    number.limits(
      max_token_bytes: 16,
      max_significant_digits: 10,
      max_exponent: 50,
    )
  let p_limits =
    value.default_limits()
    |> value.with_max_bytes(10_000)
    |> value.with_max_depth(16)
    |> value.with_number_limits(short_limits)

  // 1. Exponent too large
  case value.parse("1e51", p_limits) {
    Error(value.ParseError(_, value.InvalidNumber(number.ExponentOutOfRange))) ->
      Nil
    _ -> panic as "expected exponent out of range"
  }

  // 2. Significand too many digits
  case value.parse("12345678901", p_limits) {
    Error(value.ParseError(
      _,
      value.InvalidNumber(number.TooManySignificandDigits),
    )) -> Nil
    _ -> panic as "expected too many significand digits"
  }

  // 3. Token too long
  case value.parse("12345678901234567", p_limits) {
    Error(value.ParseError(_, value.InvalidNumber(number.TokenTooLong))) -> Nil
    _ -> panic as "expected token too long"
  }

  // The same bounds apply to number.parse directly
  number.parse("1e51", short_limits)
  |> should.equal(Error(number.ExponentOutOfRange))
  number.parse("1e50", short_limits) |> should.be_ok
}

pub fn hostile_unsupported_schema_keywords_test() {
  let limits = default_test_limits()

  // Schema with unsupported keyword "$ref"
  let ref_schema =
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"$ref\": \"#/$defs/User\"}"
  case contract.parse(ref_schema, limits) {
    Error(contract.InvalidDocument(contract.UnsupportedDocument(
      _,
      contract.UnsupportedKeyword("$ref"),
    ))) -> Nil
    _ -> panic as "expected unsupported keyword $ref"
  }

  // Schema with unsupported dialect
  let draft7_schema =
    "{\"$schema\": \"http://json-schema.org/draft-07/schema#\", \"type\": \"string\"}"
  case contract.parse(draft7_schema, limits) {
    Error(contract.InvalidDocument(contract.UnsupportedDialect(
      _,
      "http://json-schema.org/draft-07/schema#",
    ))) -> Nil
    _ -> panic as "expected unsupported dialect draft-07"
  }

  // Schema with nested dialect
  let nested_dialect =
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"type\": \"object\", \"properties\": {\"inner\": {\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"type\": \"string\"}}, \"required\": [\"inner\"], \"additionalProperties\": false}"
  case contract.parse(nested_dialect, limits) {
    Error(contract.InvalidDocument(contract.UnsupportedDocument(
      path,
      contract.NestedDialect,
    ))) ->
      path
      |> should.equal([Field("properties"), Field("inner"), Field("$schema")])
    _ -> panic as "expected nested dialect error"
  }

  // Schema text beyond the parse limits
  let deep_schema =
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", "
    <> string.repeat("\"type\": \"array\", \"items\": {", 70)
    <> "\"type\": \"string\""
    <> string.repeat("}", 70)
    <> "}"
  case contract.parse(deep_schema, limits) {
    Error(contract.InvalidJson(value.ParseError(_, value.DepthLimitExceeded(64)))) ->
      Nil
    _ -> panic as "expected schema depth limit exceeded"
  }
}

pub fn hostile_validation_test() {
  // Validation walks only parsed values, so its work follows the parse bounds;
  // a long list fails at the first bad element with its index
  let assert Ok(ints) = contract.from_codec(codec.list(codec.int()))
  let items =
    list.repeat(value.Number(int_num(1)), 10_000)
    |> list.append([value.String("x")])
  contract.validate(ints, value.Array(items))
  |> should.equal(
    Error(contract.ValidationError([codec.Index(10_000)], codec.ExpectedInt)),
  )

  // Huge integers validate against an integer schema without conversion
  let assert Ok(huge) = number.parse("1e900", number.default_limits())
  let assert Ok(any_int) = contract.from_codec(codec.int())
  contract.validate(any_int, value.Number(huge)) |> should.be_ok
  let assert Ok(bounded) = contract.from_codec(codec.integer_between(0, 10))
  contract.validate(bounded, value.Number(huge))
  |> should.equal(
    Error(contract.ValidationError([], codec.IntegerOutsideRange(0, 10))),
  )
}

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

fn enum_document(count: Int) -> String {
  let labels =
    list.repeat(Nil, count)
    |> list.index_map(fn(_, i) { "\"l" <> int.to_string(i) <> "\"" })
    |> string.join(",")
  "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
  <> "\"type\":\"string\",\"enum\":["
  <> labels
  <> "]}"
}

pub fn hostile_repeated_label_document_test() {
  // A repeated label far into a long enum is found, with its index
  let text = string.replace(enum_document(2000), "\"l1999\"]", "\"l7\"]")
  contract.parse(text, value.default_limits())
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.InvalidDefinition(
        [Field("enum"), codec.Index(1999)],
        codec.DuplicateEnumLabel("l7"),
      )),
    ),
  )
}

// A large enum from a remote schema loads and validates in linear time: the
// duplicate checks use sets, and a custom codec does not re-check its schema
// on each use.
pub fn hostile_large_enum_document_test() {
  let assert Ok(remote) =
    contract.parse(enum_document(100_000), value.default_limits())
  codec.decode(contract.value_codec(remote), value.String("l99999"))
  |> should.equal(Ok(value.String("l99999")))
}
