import generated/option_codec
import generated/order_codec
import generated_source_normalize
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import json/blueprint/codec.{DecodeError, EncodeError, Field, Index}
import json/blueprint/codegen
import json/blueprint/contract
import json/blueprint/internal/generated
import json/blueprint/number
import json/blueprint/value
import materialize_fixtures
import vanilla_order

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

const max_safe_integer = 9_007_199_254_740_991

const one_mebibyte = 1_048_576

// --- custom codecs ------------------------------------------------------------

pub fn custom_codec_retains_the_known_schema_test() {
  let constructed =
    codec.custom(
      encode: fn(_) { Ok(value.Null) },
      decode: fn(_) { Ok(7) },
      schema: Some(codec.IntSchema),
      placeholder: 0,
    )

  codec.encode(constructed, 42)
  |> should.equal(Ok(value.Null))
  codec.decode(constructed, value.Null)
  |> should.equal(Ok(7))
  codec.schema(constructed)
  |> should.equal(Ok(codec.IntSchema))

  let unknown =
    codec.custom(
      encode: fn(_) { Ok(value.Null) },
      decode: fn(_) { Ok(7) },
      schema: None,
      placeholder: 0,
    )
  codec.schema(unknown) |> should.equal(Error(codec.UnknownSchema))
  codec.schema(codec.list(unknown)) |> should.equal(Error(codec.UnknownSchema))
}

// --- generated and runtime codecs agree ----------------------------------------

pub fn generated_nested_codec_matches_runtime_codec_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  let order = sample_order()
  let assert Ok(expected_schema) = codec.schema(runtime)

  order_codec.order_schema()
  |> should.equal(expected_schema)
  codec.schema(generated)
  |> should.equal(Ok(expected_schema))

  let expected_encoding = codec.encode(runtime, order)
  order_codec.encode_order(order)
  |> should.equal(expected_encoding)
  codec.encode(generated, order)
  |> should.equal(expected_encoding)

  let assert Ok(encoded) = expected_encoding
  order_codec.decode_order(encoded)
  |> should.equal(Ok(order))
  codec.decode(generated, encoded)
  |> should.equal(Ok(order))
  codec.decode(runtime, encoded)
  |> should.equal(Ok(order))

  let optional_note_cases = [
    order_with_note(None),
    order_with_note(Some(None)),
    order_with_note(Some(Some("leave at door"))),
  ]
  let assert True =
    list.all(optional_note_cases, fn(candidate) {
      let candidate_runtime_encoding = codec.encode(runtime, candidate)
      let assert Ok(candidate_value) = candidate_runtime_encoding
      codec.encode(generated, candidate) == candidate_runtime_encoding
      && order_codec.encode_order(candidate) == candidate_runtime_encoding
      && codec.decode(generated, candidate_value) == Ok(candidate)
      && order_codec.decode_order(candidate_value) == Ok(candidate)
    })
}

pub fn generated_optional_nullable_note_has_three_wire_forms_test() {
  let generated = order_codec.order_codec()
  let note_name = "customer\n\r\f\t\\note"
  let note_member = fn(order) {
    let assert Ok(value.Object(members)) = codec.encode(generated, order)
    list.key_find(members, note_name)
  }

  note_member(order_with_note(None)) |> should.equal(Error(Nil))
  note_member(order_with_note(Some(None))) |> should.equal(Ok(value.Null))
  note_member(order_with_note(Some(Some("hi"))))
  |> should.equal(Ok(value.String("hi")))
}

pub fn generated_nested_codec_matches_runtime_errors_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  let order = sample_order()
  let assert Ok(encoded) = codec.encode(runtime, order)
  let assert value.Object(fields) = encoded
  let assert Ok(out_of_range) = number.from_int(1_000_000)
  let invalid =
    value.Object(replace_property(
      fields,
      "order_id",
      value.Number(out_of_range),
    ))

  codec.decode(runtime, invalid)
  |> should.equal(
    Error(DecodeError(
      [Field("order_id")],
      codec.IntegerOutsideRange(1, 999_999),
    )),
  )
  order_codec.decode_order(invalid)
  |> should.equal(codec.decode(runtime, invalid))
  codec.decode(generated, invalid)
  |> should.equal(codec.decode(runtime, invalid))

  let invalid_enum =
    value.Object(replace_property(
      fields,
      "status",
      value.String("unrecognized status"),
    ))
  codec.decode(runtime, invalid_enum)
  |> should.equal(Error(DecodeError([Field("status")], codec.UnknownEnumLabel)))
  order_codec.decode_order(invalid_enum)
  |> should.equal(codec.decode(runtime, invalid_enum))

  let outside_range = materialize_fixtures.Order(..order, order_id: 1_000_000)
  codec.encode(runtime, outside_range)
  |> should.equal(
    Error(EncodeError(
      [Field("order_id")],
      codec.IntegerOutsideRange(1, 999_999),
    )),
  )
  order_codec.encode_order(outside_range)
  |> should.equal(codec.encode(runtime, outside_range))
  codec.encode(generated, outside_range)
  |> should.equal(codec.encode(runtime, outside_range))
  order_codec.encode_order_json(outside_range)
  |> should.equal(codec.encode_json(runtime, outside_range))

  let unknown_status =
    materialize_fixtures.Order(..order, status: materialize_fixtures.Unmapped)
  codec.encode(runtime, unknown_status)
  |> should.equal(Error(EncodeError([Field("status")], codec.UnknownEnumValue)))
  order_codec.encode_order(unknown_status)
  |> should.equal(codec.encode(runtime, unknown_status))
  codec.encode(generated, unknown_status)
  |> should.equal(codec.encode(runtime, unknown_status))
  order_codec.encode_order_json(unknown_status)
  |> should.equal(codec.encode_json(runtime, unknown_status))
}

pub fn generated_codec_reports_every_decode_reason_like_runtime_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  let assert Ok(value.Object(fields)) = codec.encode(runtime, sample_order())
  let assert Ok(half) = number.parse("1.5", number.default_limits())
  let assert Ok(one) = number.from_int(1)
  let items = "items_\"list\""
  let note = "customer\n\r\f\t\\note"

  let cases = [
    #(value.Null, DecodeError([], codec.ExpectedObject)),
    #(
      value.Object(remove_property(fields, "type")),
      DecodeError([Field("type")], codec.MissingField),
    ),
    #(
      value.Object(list.append(fields, [#("extra", value.Null)])),
      DecodeError([Field("extra")], codec.UnknownField),
    ),
    #(
      value.Object(list.append(fields, [#("type", value.Bool(False))])),
      DecodeError([Field("type")], codec.DuplicateField),
    ),
    #(
      value.Object(replace_property(fields, "order_id", value.Number(half))),
      DecodeError([Field("order_id")], codec.ExpectedInt),
    ),
    #(
      value.Object(replace_property(fields, items, value.Bool(True))),
      DecodeError([Field(items)], codec.ExpectedArray),
    ),
    #(
      value.Object(replace_property(
        fields,
        items,
        value.Array([value.Array([value.String("x")])]),
      )),
      DecodeError([Field(items), Index(0)], codec.WrongLength(2, 1)),
    ),
    #(
      value.Object(replace_property(
        fields,
        items,
        value.Array([
          value.Array([value.String("x"), value.Number(one)]),
          value.Array([value.String("y"), value.Number(half)]),
        ]),
      )),
      DecodeError([Field(items), Index(1), Index(1)], codec.ExpectedInt),
    ),
    #(
      value.Object(replace_property(fields, note, value.Number(one))),
      DecodeError([Field(note)], codec.ExpectedString),
    ),
    #(
      value.Object(replace_property(fields, "type", value.Null)),
      DecodeError([Field("type")], codec.ExpectedBool),
    ),
    #(
      value.Object(replace_property(fields, "status", value.Number(one))),
      DecodeError([Field("status")], codec.ExpectedString),
    ),
  ]

  list.each(cases, fn(pair) {
    let #(raw, expected) = pair
    codec.decode(runtime, raw) |> should.equal(Error(expected))
    codec.decode(generated, raw) |> should.equal(Error(expected))
    order_codec.decode_order(raw) |> should.equal(Error(expected))
    // As text, the strict parser rejects the repeated key before decoding;
    // both codecs still agree.
    let text = value.to_string(raw)
    codec.decode_json(generated, text)
    |> should.equal(codec.decode_json(runtime, text))
    order_codec.decode_order_json(text)
    |> should.equal(codec.decode_json(runtime, text))
  })
}

pub fn generated_codec_is_interchangeable_with_runtime_codec_test() {
  let runtime = materialize_fixtures.build_order_codec()
  let generated = order_codec.order_codec()
  let order = sample_order()

  codec.check(generated) |> result.is_ok |> should.be_true
  codec.schema_json(generated) |> should.equal(codec.schema_json(runtime))
  let assert Ok(schema) = codec.schema(generated)
  codec.schema_document(schema)
  |> should.equal(codec.schema_document(order_codec.order_schema()))

  // Contracts treat both codecs as the same schema.
  let assert Ok(runtime_contract) = contract.from_codec(runtime)
  let assert Ok(generated_contract) = contract.from_codec(generated)
  contract.same_schema(runtime_contract, generated_contract)
  |> should.be_true
  let assert Ok(encoded) = codec.encode(generated, order)
  let assert Ok(validated) = contract.validate(runtime_contract, encoded)
  contract.decode(generated, validated) |> should.equal(Ok(order))

  // The gleam/json bridges agree.
  let assert Ok(runtime_json) = codec.to_json(runtime, order)
  let assert Ok(generated_json) = codec.to_json(generated, order)
  json.to_string(generated_json) |> should.equal(json.to_string(runtime_json))
  let assert Ok(wire) = codec.encode_json(runtime, order)
  json.parse(wire, codec.decoder(generated)) |> should.equal(Ok(order))
  let bad_wire = order_json_source("0")
  json.parse(bad_wire, codec.decoder(generated))
  |> should.equal(json.parse(bad_wire, codec.decoder(runtime)))
  let assert Error(json.UnableToDecode([decode.DecodeError(expected:, ..)])) =
    json.parse(bad_wire, codec.decoder(generated))
  expected
  |> should.equal(
    codec.describe_decode_error(DecodeError(
      [Field("order_id")],
      codec.IntegerOutsideRange(1, 999_999),
    )),
  )

  // Composed into larger runtime codecs, both report the same paths.
  let assert Ok(bad_item) = value.parse(bad_wire, value.default_limits())
  let both = value.Array([encoded, bad_item])
  codec.decode(codec.list(generated), both)
  |> should.equal(
    Error(DecodeError(
      [Index(1), Field("order_id")],
      codec.IntegerOutsideRange(1, 999_999),
    )),
  )
  codec.decode(codec.list(generated), both)
  |> should.equal(codec.decode(codec.list(runtime), both))
  let wrapped = fn(inner) {
    use order <- codec.field("order", inner, get: fn(o) { o })
    codec.success(order)
  }
  codec.schema(wrapped(generated))
  |> should.equal(codec.schema(wrapped(runtime)))
  codec.encode(
    wrapped(generated),
    materialize_fixtures.Order(..order, status: materialize_fixtures.Unmapped),
  )
  |> should.equal(
    Error(EncodeError([Field("order"), Field("status")], codec.UnknownEnumValue)),
  )
}

// --- complete JSON text ---------------------------------------------------------

pub fn generated_native_json_matches_handwritten_json_and_decodes_test() {
  let generated = order_codec.order_codec()
  let orders = [
    order_with_note_and_status(1, None, materialize_fixtures.Pending),
    order_with_note_and_status(
      999_999,
      Some(None),
      materialize_fixtures.Processing,
    ),
    order_with_note_and_status(
      42,
      Some(Some("leave\n\r\f\t\\door 🚀")),
      materialize_fixtures.ShippedQuoted,
    ),
    order_with_note_and_status(42, None, materialize_fixtures.DeliveredUnicode),
  ]
  let assert True =
    list.all(orders, fn(order) {
      let assert Ok(native_text) = order_codec.encode_order_json(order)
      let assert Ok(handwritten) = vanilla_order.encode(order)
      native_text == json.to_string(handwritten)
      && codec.encode_json(generated, order) == Ok(native_text)
      && order_codec.decode_order_json(native_text) == Ok(order)
      && order_codec.decode_order_json_native(native_text) == Ok(order)
      && codec.decode_json(generated, native_text) == Ok(order)
    })
}

pub fn generated_native_json_returns_gleam_json_errors_test() {
  // Each native failure is one `decode.DecodeError` whose `expected` is the
  // text of the error that strict decoding reports for the same input.
  let wrong_type = order_json(Some(json.string("42")), "pending", False)
  let expected = DecodeError([Field("order_id")], codec.ExpectedInt)
  order_codec.decode_order_json(wrong_type) |> should.equal(Error(expected))
  native_expected(order_codec.decode_order_json_native(wrong_type))
  |> should.equal(Ok(codec.describe_decode_error(expected)))

  let missing_id = order_json(None, "pending", False)
  let expected = DecodeError([Field("order_id")], codec.MissingField)
  order_codec.decode_order_json(missing_id) |> should.equal(Error(expected))
  native_expected(order_codec.decode_order_json_native(missing_id))
  |> should.equal(Ok(codec.describe_decode_error(expected)))

  let unknown_field = order_json(Some(json.int(42)), "pending", True)
  let expected = DecodeError([Field("unexpected")], codec.UnknownField)
  order_codec.decode_order_json(unknown_field) |> should.equal(Error(expected))
  native_expected(order_codec.decode_order_json_native(unknown_field))
  |> should.equal(Ok(codec.describe_decode_error(expected)))

  let unknown_status = order_json(Some(json.int(42)), "unrecognized", False)
  let expected = DecodeError([Field("status")], codec.UnknownEnumLabel)
  order_codec.decode_order_json(unknown_status)
  |> should.equal(Error(expected))
  native_expected(order_codec.decode_order_json_native(unknown_status))
  |> should.equal(Ok(codec.describe_decode_error(expected)))

  let out_of_range = order_json(Some(json.int(1_000_000)), "pending", False)
  let expected =
    DecodeError([Field("order_id")], codec.IntegerOutsideRange(1, 999_999))
  order_codec.decode_order_json(out_of_range) |> should.equal(Error(expected))
  native_expected(order_codec.decode_order_json_native(out_of_range))
  |> should.equal(Ok(codec.describe_decode_error(expected)))

  // Invalid text fails in the gleam/json parser, not in decoding.
  let assert Error(DecodeError([], codec.InvalidJson(_))) =
    order_codec.decode_order_json("{")
  case order_codec.decode_order_json_native("{") {
    Error(json.UnableToDecode(_)) -> should.fail()
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

pub fn generated_native_json_rejects_text_above_one_mebibyte_test() {
  let base = order_json_with_note("")
  let fitting =
    order_json_with_note(string.repeat(
      "a",
      one_mebibyte - string.byte_size(base),
    ))
  string.byte_size(fitting) |> should.equal(one_mebibyte)
  let oversized =
    order_json_with_note(string.repeat(
      "a",
      one_mebibyte - string.byte_size(base) + 1,
    ))

  order_codec.decode_order_json_native(fitting) |> should.be_ok
  order_codec.decode_order_json(fitting) |> should.be_ok

  order_codec.decode_order_json_native(oversized)
  |> should.equal(
    Error(
      json.UnableToDecode([
        decode.DecodeError(
          expected: "JSON text of at most 1048576 bytes",
          found: "more than 1048576 bytes",
          path: [],
        ),
      ]),
    ),
  )
  let assert Error(strict_error) = order_codec.decode_order_json(oversized)
  let assert DecodeError(
    [],
    codec.InvalidJson(value.ParseError(_, value.ByteLimitExceeded(max))),
  ) = strict_error
  max |> should.equal(one_mebibyte)
  codec.is_limit_exceeded(strict_error) |> should.be_true
}

pub fn generated_option_codec_native_and_strict_decoding_agree_test() {
  let cases = [
    #("{}", None),
    #("{\"note\":null}", Some(None)),
    #("{\"note\":\"hi\"}", Some(Some("hi"))),
  ]
  list.each(cases, fn(pair) {
    let #(text, expected) = pair
    option_codec.decode_option_json(text) |> should.equal(Ok(expected))
    option_codec.decode_option_json_native(text) |> should.equal(Ok(expected))
    option_codec.encode_option_json(expected) |> should.equal(Ok(text))
  })

  let expected = DecodeError([Field("note")], codec.ExpectedString)
  option_codec.decode_option_json("{\"note\":1}")
  |> should.equal(Error(expected))
  native_expected(option_codec.decode_option_json_native("{\"note\":1}"))
  |> should.equal(Ok(codec.describe_decode_error(expected)))
}

pub fn generated_native_int_accepts_exact_json_integer_forms_test() {
  order_codec.decode_order_json(order_json_source("2.0"))
  |> should.equal(Ok(empty_order(2)))
  order_codec.decode_order_json_native(order_json_source("2.0"))
  |> should.equal(Ok(empty_order(2)))

  order_codec.decode_order_json(order_json_source("2e0"))
  |> should.equal(Ok(empty_order(2)))
  order_codec.decode_order_json_native(order_json_source("2e0"))
  |> should.equal(Ok(empty_order(2)))

  let expected = DecodeError([Field("order_id")], codec.ExpectedInt)
  order_codec.decode_order_json(order_json_source("2.5"))
  |> should.equal(Error(expected))
  native_expected(
    order_codec.decode_order_json_native(order_json_source("2.5")),
  )
  |> should.equal(Ok(codec.describe_decode_error(expected)))
}

pub fn native_integer_encoding_uses_existing_safety_checks_test() {
  let unsafe = max_safe_integer + 1
  let expected = codec.encode(codec.int(), unsafe)
  let actual = generated.encode_native_int(unsafe)
  let assert True = case expected, actual {
    Ok(value.Number(_)), Ok(json_int) -> json_int == json.int(unsafe)
    Error(expected_error), Error(actual_error) -> expected_error == actual_error
    _, _ -> False
  }

  case actual {
    Error(error) -> {
      error |> should.equal(EncodeError([], codec.UnsafeInteger))
      generated.encode_native_list(generated.encode_native_int, [unsafe])
      |> should.equal(Error(EncodeError([Index(0)], codec.UnsafeInteger)))
      generated.encode_native_required(
        "count",
        generated.encode_native_int,
        unsafe,
      )
      |> should.equal(Error(EncodeError([Field("count")], codec.UnsafeInteger)))
    }
    Ok(_) -> Nil
  }
}

pub fn generated_native_int_decoder_rejects_unsafe_integer_results_test() {
  let unsafe = max_safe_integer + 1
  let unsafe_integer = order_json_source("9007199254740992")
  let strict_expected =
    DecodeError([Field("order_id")], codec.IntegerOutsideRange(1, 999_999))
  order_codec.decode_order_json(unsafe_integer)
  |> should.equal(Error(strict_expected))
  let result =
    native_expected(order_codec.decode_order_json_native(unsafe_integer))

  case number.from_int(unsafe) {
    // JavaScript: the native parser's integer is not safe.
    Error(number.UnsafeNativeInteger) ->
      result
      |> should.equal(
        Ok(
          codec.describe_decode_error(DecodeError(
            [Field("order_id")],
            codec.ExpectedInt,
          )),
        ),
      )
    Error(number.NonFiniteInteger) -> should.fail()
    Error(number.NonIntegerValue) -> should.fail()
    Ok(_) ->
      result |> should.equal(Ok(codec.describe_decode_error(strict_expected)))
  }
}

pub fn generated_native_nested_integer_encoding_preserves_safety_errors_test() {
  let unsafe = max_safe_integer + 1
  let runtime = materialize_fixtures.build_order_codec()
  let item =
    materialize_fixtures.Order(
      42,
      [#("unsafe", unsafe)],
      None,
      True,
      materialize_fixtures.Pending,
    )
  let expected =
    EncodeError(
      [Field("items_\"list\""), Index(0), Index(1)],
      codec.UnsafeInteger,
    )

  case number.from_int(unsafe) {
    Error(number.UnsafeNativeInteger) -> {
      order_codec.encode_order_json(item) |> should.equal(Error(expected))
      order_codec.encode_order(item) |> should.equal(Error(expected))
      codec.encode(runtime, item) |> should.equal(Error(expected))
    }
    Error(number.NonFiniteInteger) -> should.fail()
    Error(number.NonIntegerValue) -> should.fail()
    Ok(_) -> {
      order_codec.encode_order_json(item) |> should.be_ok
      order_codec.encode_order_json(item)
      |> should.equal(codec.encode_json(runtime, item))
    }
  }
}

@target(erlang)
pub fn native_integer_between_projects_integers_of_its_bounds_test() {
  // Bounds beyond 24 digits decode their whole range, as `codec.int()` does
  // not; strict and native decoding agree.
  let maximum = 1_000_000_000_000_000_000_000_000_000_000
  let large = 12_345_678_901_234_567_890_123_456
  let text = "12345678901234567890123456"
  let assert Ok(raw) = value.parse(text, value.default_limits())
  let assert Ok(dynamic) = json.parse(text, decode.dynamic)

  codec.decode(codec.integer_between(0, maximum), raw)
  |> should.equal(Ok(large))
  generated.decode_integer_between(0, maximum, raw)
  |> should.equal(Ok(large))
  generated.decode_native_integer_between(0, maximum, dynamic)
  |> should.equal(Ok(large))

  // Beyond the bounds, both report the range rather than the digit count.
  let beyond = "10000000000000000000000000000000000000000"
  let assert Ok(raw) = value.parse(beyond, value.default_limits())
  let assert Ok(dynamic) = json.parse(beyond, decode.dynamic)
  let expected = Error(DecodeError([], codec.IntegerOutsideRange(0, maximum)))
  codec.decode(codec.integer_between(0, maximum), raw)
  |> should.equal(expected)
  generated.decode_integer_between(0, maximum, raw) |> should.equal(expected)
  generated.decode_native_integer_between(0, maximum, dynamic)
  |> should.equal(expected)
}

pub fn native_json_integer_parser_normalization_is_observable_test() {
  // Explicit native parsing normalizes this decimal to 1; ordinary generated
  // decoding keeps the exact token and rejects it as a fractional integer.
  let source = order_json_source("1.0000000000000001")
  let runtime = materialize_fixtures.build_order_codec()
  let expected = DecodeError([Field("order_id")], codec.ExpectedInt)

  codec.decode_json(runtime, source)
  |> should.equal(Error(expected))
  order_codec.decode_order_json(source)
  |> should.equal(Error(expected))
  order_codec.decode_order_json_native(source)
  |> should.equal(Ok(empty_order(1)))
}

pub fn native_duplicate_keys_follow_backend_parser_semantics_test() {
  let duplicate_id =
    "{\"order_id\":41,\"order_id\":42,\"items_\\\"list\\\"\":[],\"type\":true,\"status\":\"pending\"}"
  let runtime = materialize_fixtures.build_order_codec()

  let assert Error(DecodeError(
    [],
    codec.InvalidJson(value.ParseError(_, value.DuplicateObjectKey)),
  )) = codec.decode_json(runtime, duplicate_id)
  order_codec.decode_order_json(duplicate_id)
  |> should.equal(codec.decode_json(runtime, duplicate_id))

  // The named native decoder retains the target parser's collapse policy.
  let assert Ok(parser_id) =
    json.parse(from: duplicate_id, using: {
      use id <- decode.field("order_id", decode.int)
      decode.success(id)
    })
  let assert Ok(native_order) =
    order_codec.decode_order_json_native(duplicate_id)
  native_order.order_id |> should.equal(parser_id)
}

// --- compiling --------------------------------------------------------------------

pub fn native_number_definitions_fail_with_a_typed_compile_error_test() {
  codegen.compile("generated/number", "number", codegen.number())
  |> should.equal(Error(codegen.NativeNumberUnsupported))
  let inside_object =
    codegen.object(codegen.required("amount", codegen.number()))
  codegen.compile("generated/number", "number", inside_object)
  |> should.equal(Error(codegen.NativeNumberUnsupported))
}

pub fn compile_rejects_invalid_module_paths_and_names_test() {
  let assert Error(codegen.InvalidModulePath("Generated/x", _)) =
    codegen.compile("Generated/x", "item", codegen.string())
  let assert Error(codegen.InvalidModulePath("generated/type", _)) =
    codegen.compile("generated/type", "item", codegen.string())
  let assert Error(codegen.InvalidCodecName("Item", _)) =
    codegen.compile("generated/x", "Item", codegen.string())
  let assert Error(codegen.InvalidCodecName("let", _)) =
    codegen.compile("generated/x", "let", codegen.string())
}

pub fn codec_generation_is_deterministic_and_fresh_test() {
  let definition = materialize_fixtures.order_definition()
  let assert Ok(first) =
    codegen.compile("generated/order_codec", "order", definition)
  let assert Ok(second) =
    codegen.compile("generated/order_codec", "order", definition)
  let codegen.GeneratedModule(first_path, first_content, first_fingerprint) =
    first
  let codegen.GeneratedModule(second_path, second_content, second_fingerprint) =
    second

  first_path
  |> should.equal("generated/order_codec.gleam")
  first_path
  |> should.equal(second_path)
  first_content
  |> should.equal(second_content)
  first_fingerprint
  |> should.equal(second_fingerprint)
  first_fingerprint
  |> should.equal(order_codec.generated_fingerprint)
  let assert Ok(generated_file) =
    read_file_to_string("test/generated/order_codec.gleam")
  let normalized_file = generated_source_normalize.normalize(generated_file)
  let normalized_generated = generated_source_normalize.normalize(first_content)
  normalized_file |> should.equal(normalized_generated)

  let contains = fn(needle) { string.contains(first_content, needle) }
  contains("const order_compiled_inner_property_names: List(String)")
  |> should.be_true
  contains("generated.decode_object(order_compiled_inner_property_names")
  |> should.be_true
  contains("import materialize_fixtures") |> should.be_true
  contains("import json/blueprint/internal/generated") |> should.be_true
  contains("codec.custom(") |> should.be_true
  contains("placeholder: materialize_fixtures.order_from_fields(")
  |> should.be_true
  contains("generated.encode_native_integer_between(1, 999_999, item)")
  |> should.be_true
  contains("codec.decode_json(order_codec(), source)") |> should.be_true
  contains("generated.decode_json_native(source, ") |> should.be_true
  contains(") -> Result(materialize_fixtures.Order, json.DecodeError) {")
  |> should.be_true
  contains("option.Option(option.Option(String))") |> should.be_true
  contains("codec.encode_json(") |> should.be_false
  contains("codec.new(") |> should.be_false
  contains("codec.Optional(") |> should.be_false
  contains("codec.Nullable(") |> should.be_false
  contains("json_text.") |> should.be_false
  contains("parser_core") |> should.be_false

  let assert Ok(integer_definition) =
    codegen.compile("generated/integer", "integer", codegen.int())
  let codegen.GeneratedModule(_, integer_content, _) = integer_definition
  integer_content
  |> string.contains("generated.encode_native_int(item)")
  |> should.be_true
}

pub fn codec_compiler_rejects_conflicting_import_aliases_test() {
  let assert Ok(mapping) =
    codegen.named_mapping(
      identity_string,
      "alpha/shape.identity_string",
      identity_string,
      "beta/shape.identity_string",
    )
  let assert Ok(definition) = codegen.imap(codegen.string(), "String", mapping)

  codegen.compile("generated/conflict", "item", definition)
  |> should.equal(
    Error(codegen.ConflictingImportAlias("shape", "alpha/shape", "beta/shape")),
  )
}

pub fn codec_compiler_rejects_unimported_qualified_types_test() {
  let assert Ok(mapping) =
    codegen.named_mapping(
      identity_string,
      "compiled_codec_test.identity_string",
      identity_string,
      "compiled_codec_test.identity_string",
    )
  let assert Ok(definition) =
    codegen.imap(codegen.string(), "external_model.Widget", mapping)

  codegen.compile("generated/unresolved", "item", definition)
  |> should.equal(Error(codegen.MissingTypeImport("external_model")))
}

pub fn invalid_references_are_rejected_before_compiling_test() {
  codegen.named_mapping(
    identity_string,
    "not a reference",
    identity_string,
    "compiled_codec_test.identity_string",
  )
  |> should.equal(Error(codegen.InvalidFunctionReference("not a reference")))
  codegen.enum_variant("x", materialize_fixtures.Pending, "lowercase.pending")
  |> should.equal(Error(codegen.InvalidFunctionReference("lowercase.pending")))
  let assert Ok(pending) =
    codegen.enum_variant(
      "pending",
      materialize_fixtures.Pending,
      "materialize_fixtures.Pending",
    )
  let assert Error(codegen.InvalidTypeReference("not-a-type")) =
    codegen.string_enum("not-a-type", [pending])
  let assert Ok(mapping) =
    codegen.named_mapping(
      identity_string,
      "compiled_codec_test.identity_string",
      identity_string,
      "compiled_codec_test.identity_string",
    )
  let assert Error(codegen.InvalidTypeReference("List(")) =
    codegen.imap(codegen.string(), "List(", mapping)
}

pub fn named_mapping_references_are_trusted_metadata_test() {
  let assert Ok(mapping) =
    codegen.named_mapping(
      identity_string,
      "compiled_codec_test.uppercase_string",
      identity_string,
      "compiled_codec_test.identity_string",
    )
  let assert Ok(definition) = codegen.imap(codegen.string(), "String", mapping)
  let assert Ok(generated) =
    codegen.compile("generated/mismatched_mapping", "item", definition)
  let codegen.GeneratedModule(_, content, _) = generated

  codec.decode(codegen.runtime(definition), value.String("mixed"))
  |> should.equal(Ok("mixed"))
  content
  |> string.contains("compiled_codec_test.uppercase_string, raw)")
  |> should.be_true
}

// --- codegen definition behavior ------------------------------------------------

pub fn optional_definitions_decode_absent_as_none_test() {
  let definition = codegen.object(codegen.optional("count", codegen.int()))
  let runtime = codegen.runtime(definition)

  codec.decode_json(runtime, "{}") |> should.equal(Ok(None))
  codec.decode_json(runtime, "{\"count\":3}") |> should.equal(Ok(Some(3)))
  codec.decode_json(runtime, "{\"count\":null}")
  |> should.equal(Error(DecodeError([Field("count")], codec.ExpectedInt)))
  codec.encode_json(runtime, None) |> should.equal(Ok("{}"))
  codec.encode_json(runtime, Some(3)) |> should.equal(Ok("{\"count\":3}"))
  codec.schema(runtime)
  |> should.equal(
    Ok(
      codec.ObjectSchema([codec.PropertySchema("count", False, codec.IntSchema)]),
    ),
  )

  let assert Ok(codegen.GeneratedModule(_, content, _)) =
    codegen.compile("generated/count", "count", definition)
  content
  |> string.contains(
    "pub fn decode_count(raw: value.Value) -> Result(option.Option(Int), codec.DecodeError)",
  )
  |> should.be_true
  content
  |> string.contains("generated.decode_optional(\"count\", fields, ")
  |> should.be_true
}

pub fn optional_nullable_definitions_keep_absent_null_and_value_test() {
  let runtime: codec.Codec(Option(Option(String))) =
    codegen.runtime(
      codegen.object(codegen.optional(
        "note",
        codegen.nullable(codegen.string()),
      )),
    )

  codec.decode_json(runtime, "{}") |> should.equal(Ok(None))
  codec.decode_json(runtime, "{\"note\":null}") |> should.equal(Ok(Some(None)))
  codec.decode_json(runtime, "{\"note\":\"hi\"}")
  |> should.equal(Ok(Some(Some("hi"))))
  codec.encode_json(runtime, None) |> should.equal(Ok("{}"))
  codec.encode_json(runtime, Some(None)) |> should.equal(Ok("{\"note\":null}"))
  codec.encode_json(runtime, Some(Some("hi")))
  |> should.equal(Ok("{\"note\":\"hi\"}"))
}

pub fn nullable_definitions_are_options_test() {
  let definition = codegen.nullable(codegen.int())
  let runtime: codec.Codec(Option(Int)) = codegen.runtime(definition)

  codec.decode_json(runtime, "null") |> should.equal(Ok(None))
  codec.decode_json(runtime, "4") |> should.equal(Ok(Some(4)))
  codec.encode_json(runtime, None) |> should.equal(Ok("null"))
  codec.schema(runtime)
  |> should.equal(Ok(codec.NullableSchema(codec.IntSchema)))

  let assert Ok(codegen.GeneratedModule(_, content, _)) =
    codegen.compile("generated/maybe", "maybe", definition)
  content
  |> string.contains(
    "pub fn encode_maybe(item: option.Option(Int)) -> Result(value.Value, codec.EncodeError)",
  )
  |> should.be_true
  content
  |> string.contains("placeholder: option.None")
  |> should.be_true
}

pub fn integer_between_definitions_are_total_test() {
  let in_order: codegen.Definition(Int) = codegen.integer_between(1, 3)
  codec.decode_json(codegen.runtime(in_order), "3") |> should.equal(Ok(3))
  codec.decode_json(codegen.runtime(in_order), "4")
  |> should.equal(Error(DecodeError([], codec.IntegerOutsideRange(1, 3))))
  let assert Ok(_) = codegen.compile("generated/small", "small", in_order)

  let single = codegen.integer_between(-7, -7)
  codec.decode_json(codegen.runtime(single), "-7") |> should.equal(Ok(-7))
  let assert Ok(codegen.GeneratedModule(_, content, _)) =
    codegen.compile("generated/single", "single", single)
  content
  |> string.contains("generated.decode_integer_between(-7, -7, raw)")
  |> should.be_true

  // Reversed bounds are a definition mistake that compile reports.
  let reversed = codegen.integer_between(5, 1)
  codec.check(codegen.runtime(reversed))
  |> should.equal(Error(codec.ReversedIntegerBounds(5, 1)))
  codegen.compile("generated/reversed", "reversed", reversed)
  |> should.equal(
    Error(codegen.InvalidDefinition(codec.ReversedIntegerBounds(5, 1))),
  )
  let nested = codegen.object(codegen.required("n", reversed))
  codegen.compile("generated/reversed", "reversed", nested)
  |> should.equal(
    Error(codegen.InvalidDefinition(codec.ReversedIntegerBounds(5, 1))),
  )
}

@target(javascript)
pub fn integer_between_unsafe_bounds_are_reported_by_compile_test() {
  let unsafe = codegen.integer_between(0, max_safe_integer + 1)
  codegen.compile("generated/unsafe", "unsafe", unsafe)
  |> should.equal(
    Error(
      codegen.InvalidDefinition(codec.UnsafeIntegerBound(max_safe_integer + 1)),
    ),
  )
}

pub fn duplicate_property_names_are_reported_by_compile_test() {
  let properties =
    codegen.combine(
      codegen.required("id", codegen.int()),
      codegen.required("name", codegen.string()),
    )
    |> codegen.combine(codegen.optional("id", codegen.string()))
  let definition = codegen.object(properties)

  codec.check(codegen.runtime(definition))
  |> should.equal(Error(codec.DuplicateFieldName("id")))
  codegen.compile("generated/duplicate", "duplicate", definition)
  |> should.equal(
    Error(codegen.InvalidDefinition(codec.DuplicateFieldName("id"))),
  )

  // Distinct names compile.
  let distinct =
    codegen.combine(
      codegen.required("id", codegen.int()),
      codegen.required("name", codegen.string()),
    )
    |> codegen.object
  let assert Ok(_) = codegen.compile("generated/distinct", "distinct", distinct)
}

pub fn enum_definition_mistakes_are_reported_by_compile_test() {
  let assert Ok(pending) =
    codegen.enum_variant(
      "pending",
      materialize_fixtures.Pending,
      "materialize_fixtures.Pending",
    )
  let assert Ok(pending_again) =
    codegen.enum_variant(
      "pending",
      materialize_fixtures.Processing,
      "materialize_fixtures.Processing",
    )
  let assert Ok(also_pending) =
    codegen.enum_variant(
      "also pending",
      materialize_fixtures.Pending,
      "materialize_fixtures.Pending",
    )

  let assert Ok(repeated_label) =
    codegen.string_enum("materialize_fixtures.OrderStatus", [
      pending,
      pending_again,
    ])
  codegen.compile("generated/status", "status", repeated_label)
  |> should.equal(
    Error(codegen.InvalidDefinition(codec.DuplicateEnumLabel("pending"))),
  )

  let assert Ok(repeated_value) =
    codegen.string_enum("materialize_fixtures.OrderStatus", [
      pending,
      also_pending,
    ])
  codegen.compile("generated/status", "status", repeated_value)
  |> should.equal(
    Error(codegen.InvalidDefinition(codec.DuplicateEnumValue("also pending"))),
  )

  let assert Ok(empty) =
    codegen.string_enum("materialize_fixtures.OrderStatus", [])
  codec.check(codegen.runtime(empty)) |> should.equal(Error(codec.EmptyEnum))
  codegen.compile("generated/status", "status", empty)
  |> should.equal(Error(codegen.InvalidDefinition(codec.EmptyEnum)))
}

// --- helpers ----------------------------------------------------------------------

fn identity_string(value: String) -> String {
  value
}

pub fn uppercase_string(value: String) -> String {
  string.uppercase(value)
}

/// The `expected` text of a native decode failure.
fn native_expected(
  result: Result(a, json.DecodeError),
) -> Result(String, Option(a)) {
  case result {
    Error(json.UnableToDecode([decode.DecodeError(expected:, ..)])) ->
      Ok(expected)
    Error(_) -> Error(None)
    Ok(item) -> Error(Some(item))
  }
}

fn sample_order() -> materialize_fixtures.Order {
  order_with_note(Some(Some("leave at door")))
}

fn order_with_note(note: Option(Option(String))) -> materialize_fixtures.Order {
  materialize_fixtures.Order(
    42,
    [#("widget", 2), #("雪 🚀", 7)],
    note,
    True,
    materialize_fixtures.ShippedQuoted,
  )
}

fn order_with_note_and_status(
  id: Int,
  note: Option(Option(String)),
  status: materialize_fixtures.OrderStatus,
) -> materialize_fixtures.Order {
  materialize_fixtures.Order(
    id,
    [#("widget", 2), #("雪 🚀", 7)],
    note,
    True,
    status,
  )
}

fn order_json(id: Option(json.Json), status: String, unknown: Bool) -> String {
  let id_fields = case id {
    Some(value) -> [#("order_id", value)]
    None -> []
  }
  let unknown_fields = case unknown {
    True -> [#("unexpected", json.bool(False))]
    False -> []
  }
  json.object(list.append(
    id_fields,
    list.append(
      [
        #("items_\"list\"", json.preprocessed_array([])),
        #("type", json.bool(True)),
        #("status", json.string(status)),
      ],
      unknown_fields,
    ),
  ))
  |> json.to_string
}

fn order_json_source(id: String) -> String {
  "{\"order_id\":"
  <> id
  <> ",\"items_\\\"list\\\"\":[],\"type\":true,\"status\":\"pending\"}"
}

fn order_json_with_note(note: String) -> String {
  "{\"order_id\":1,\"items_\\\"list\\\"\":[],\"customer\\n\\r\\f\\t\\\\note\":\""
  <> note
  <> "\",\"type\":true,\"status\":\"pending\"}"
}

fn empty_order(id: Int) -> materialize_fixtures.Order {
  materialize_fixtures.Order(id, [], None, True, materialize_fixtures.Pending)
}

fn replace_property(
  fields: List(#(String, value.Value)),
  name: String,
  replacement: value.Value,
) -> List(#(String, value.Value)) {
  list.map(fields, fn(field) {
    case field.0 == name {
      True -> #(name, replacement)
      False -> field
    }
  })
}

fn remove_property(
  fields: List(#(String, value.Value)),
  name: String,
) -> List(#(String, value.Value)) {
  list.filter(fields, fn(field) { field.0 != name })
}
