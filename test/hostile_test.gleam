import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/document
import json/blueprint/number
import json/blueprint/parser
import json/blueprint/value

fn default_test_limits() -> parser.ParserLimits {
  let assert Ok(num_limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(limits) = parser.parser_limits(1_000_000, 64, num_limits)
  limits
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
  ]
  list.each(str_edge_cases, fn(s) {
    let assert Ok(encoded) = codec.encode(str_c, s)
    let assert Ok(decoded) = codec.decode(str_c, encoded)
    decoded |> should.equal(s)
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
  let list_cases = [
    [],
    [0],
    [1, 2, 3],
    [-10, 0, 10, 20, 30],
    int_edge_cases,
  ]
  list.each(list_cases, fn(l) {
    let assert Ok(encoded) = codec.encode(list_int_c, l)
    let assert Ok(decoded) = codec.decode(list_int_c, encoded)
    decoded |> should.equal(l)
  })

  // 5. Nullable codec composition
  let null_str_c = codec.nullable(str_c)
  let null_cases = [
    codec.Null,
    codec.NonNull(""),
    codec.NonNull("present"),
    codec.NonNull("雪猫"),
  ]
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
  let assert Ok(range_c) = codec.integer_between(-50, 50)
  let range_valid_cases = [-50, -49, -25, -1, 0, 1, 25, 49, 50]
  list.each(range_valid_cases, fn(v) {
    let assert Ok(encoded) = codec.encode(range_c, v)
    let assert Ok(decoded) = codec.decode(range_c, encoded)
    decoded |> should.equal(v)
  })
}

pub fn codec_rejection_laws_property_test() {
  // 1. Integer Range Rejection Law: values outside [-50, 50] must be rejected by both encode and decode
  let assert Ok(range_c) = codec.integer_between(-50, 50)
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
      Error(
        codec.CannotEncode(codec.EncodeIntegerOutsideRange(-50, 50, bad_val)),
      ),
    )

    // Decode rejection
    let assert Ok(bad_num) = number.from_int(bad_val)
    codec.decode(range_c, value.Number(bad_num))
    |> should.equal(
      Error(
        codec.CannotDecode(codec.DecodeIntegerOutsideRange(-50, 50, bad_val)),
      ),
    )
  })

  // 2. String Enum Domain Rejection Law: strings not in domain must be rejected
  let assert Ok(enum_c) =
    codec.string_enum([
      #("red", "Red"),
      #("green", "Green"),
      #("blue", "Blue"),
    ])
  let disallowed_enum_strings = [
    "", "RED", "Green", "BLUE", "yellow", "red\n", " blue", "blue ", "1",
  ]
  list.each(disallowed_enum_strings, fn(bad_str) {
    codec.decode(enum_c, value.String(bad_str))
    |> should.equal(
      Error(codec.CannotDecode(codec.DecodeUnknownEnumLabel(bad_str))),
    )
  })

  // 3. Type Mismatch Rejection Law: passing wrong value variant must return DecodeExpected*
  let int_c = codec.int()
  let str_c = codec.string()
  let bool_c = codec.bool()

  // Null where int expected
  codec.decode(int_c, value.Null)
  |> should.equal(Error(codec.CannotDecode(codec.DecodeExpectedInt)))

  // Bool where string expected
  codec.decode(str_c, value.Bool(True))
  |> should.equal(Error(codec.CannotDecode(codec.DecodeExpectedString)))

  // String where bool expected
  codec.decode(bool_c, value.String("true"))
  |> should.equal(Error(codec.CannotDecode(codec.DecodeExpectedBool)))

  // Array where object expected
  let req_props = codec.required("id", int_c)
  let obj_c = codec.object(req_props)
  codec.decode(obj_c, value.Array([]))
  |> should.equal(Error(codec.CannotDecode(codec.DecodeExpectedObject)))

  // 4. Tagged Union Discriminator Rejection Law
  let assert Ok(tagged_c) = codec.tagged("left", int_c, "right", str_c)

  // Non-string discriminator tag
  let assert Ok(num1) = number.from_int(1)
  codec.decode(
    tagged_c,
    value.Object([#("tag", value.Number(num1)), #("value", value.String("val"))]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "tag",
      codec.CannotDecode(codec.DecodeExpectedString),
    )),
  )

  // Unknown tag
  codec.decode(
    tagged_c,
    value.Object([#("tag", value.String("unknown")), #("value", value.Null)]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "tag",
      codec.CannotDecode(codec.DecodeUnknownTag("unknown")),
    )),
  )
}

pub fn hostile_depth_boundary_test() {
  // Exactly at limit vs 1 beyond limit
  let assert Ok(limits) =
    parser.parser_limits(10_000, 3, default_number_limits())

  // Depth 3: [[[1]]] -> parsed array depth is 3 -> accepted
  parser.parse_value_from_string(limits, "[[[1]]]")
  |> should.be_ok

  // Depth 4: [[[[1]]]] -> parsed array depth is 4 > max_depth 3 -> rejected
  case parser.parse_value_from_string(limits, "[[[[1]]]]") {
    Error(parser.ParseError(_, parser.DepthLimitExceeded(3))) -> Nil
    _ -> panic as "expected depth limit 3 exceeded"
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

  let assert Ok(val) = parser.parse_value_from_string(limits, wide_json)
  case val {
    value.Object(entries) -> list.length(entries) |> should.equal(100)
    _ -> panic as "expected object with 100 entries"
  }
}

pub fn hostile_nested_duplicate_keys_test() {
  let limits = default_test_limits()

  // Duplicate key nested inside an array
  let nested_json = "[1, {\"a\": 10, \"b\": 20, \"a\": 30}]"
  case parser.parse_value_from_string(limits, nested_json) {
    Error(parser.ParseError(loc, parser.DuplicateObjectKey("a"))) -> {
      loc.line |> should.equal(1)
      loc.byte_offset |> should.equal(23)
    }
    _ -> panic as "expected duplicate key inside array"
  }
}

pub fn hostile_numeric_limits_test() {
  let assert Ok(short_limits) = number.number_limits(16, 10, 50)
  let assert Ok(p_limits) = parser.parser_limits(10_000, 16, short_limits)

  // 1. Exponent too large
  case parser.parse_value_from_string(p_limits, "1e51") {
    Error(parser.ParseError(
      _,
      parser.InvalidNumberToken(number.ExponentOutOfRange),
    )) -> Nil
    _ -> panic as "expected exponent out of range"
  }

  // 2. Significand too many digits
  case parser.parse_value_from_string(p_limits, "12345678901") {
    Error(parser.ParseError(
      _,
      parser.InvalidNumberToken(number.TooManySignificandDigits),
    )) -> Nil
    _ -> panic as "expected too many significand digits"
  }

  // 3. Token too long
  case parser.parse_value_from_string(p_limits, "12345678901234567") {
    Error(parser.ParseError(_, parser.InvalidNumberToken(number.TokenTooLong))) ->
      Nil
    _ -> panic as "expected token too long"
  }
}

pub fn hostile_unsupported_schema_keywords_test() {
  let limits = default_test_limits()

  // Schema with unsupported keyword "$ref"
  let ref_schema =
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"$ref\": \"#/$defs/User\"}"
  case parser.parse_schema_document_from_string(limits, ref_schema) {
    Error(parser.DocumentAdmissionError(document.UnsupportedDocument(
      _,
      document.UnsupportedKeyword("$ref"),
    ))) -> Nil
    _ -> panic as "expected unsupported keyword $ref"
  }

  // Schema with unsupported dialect
  let draft7_schema =
    "{\"$schema\": \"http://json-schema.org/draft-07/schema#\", \"type\": \"string\"}"
  case parser.parse_schema_document_from_string(limits, draft7_schema) {
    Error(parser.DocumentAdmissionError(document.UnsupportedDialect(
      _,
      "http://json-schema.org/draft-07/schema#",
    ))) -> Nil
    _ -> panic as "expected unsupported dialect draft-07"
  }

  // Schema with nested dialect
  let nested_dialect =
    "{\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"type\": \"object\", \"properties\": {\"inner\": {\"$schema\": \"https://json-schema.org/draft/2020-12/schema\", \"type\": \"string\"}}, \"required\": [\"inner\"], \"additionalProperties\": false}"
  case parser.parse_schema_document_from_string(limits, nested_dialect) {
    Error(parser.DocumentAdmissionError(document.UnsupportedDocument(
      _,
      document.NestedDialect,
    ))) -> Nil
    _ -> panic as "expected nested dialect error"
  }
}

fn default_number_limits() -> number.NumberLimits {
  let assert Ok(limits) = number.number_limits(1024, 100, 1000)
  limits
}
