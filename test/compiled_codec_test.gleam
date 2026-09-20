import generated/order_codec
import generated_source_normalize
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/number
import json/blueprint/value
import materialize_fixtures
import vanilla_order

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

pub fn from_parts_retains_the_known_schema_test() {
  let constructed =
    codec.from_parts(fn(_) { Ok(value.Null) }, fn(_) { Ok(7) }, codec.IntSchema)

  codec.encode(constructed, 42)
  |> should.equal(Ok(value.Null))
  codec.decode(constructed, value.Null)
  |> should.equal(Ok(7))
  codec.schema(constructed)
  |> should.equal(Ok(codec.IntSchema))
}

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
    order_with_note(codec.Missing),
    order_with_note(codec.Present(codec.Null)),
    order_with_note(codec.Present(codec.NonNull("leave at door"))),
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
  order_codec.decode_order(invalid_enum)
  |> should.equal(codec.decode(runtime, invalid_enum))

  let outside_range =
    materialize_fixtures.Order(
      1_000_000,
      order.items,
      order.note,
      order.active,
      order.status,
    )
  order_codec.encode_order(outside_range)
  |> should.equal(codec.encode(runtime, outside_range))
  codec.encode(generated, outside_range)
  |> should.equal(codec.encode(runtime, outside_range))

  let unknown_status =
    materialize_fixtures.Order(
      order.order_id,
      order.items,
      order.note,
      order.active,
      materialize_fixtures.Unmapped,
    )
  order_codec.encode_order(unknown_status)
  |> should.equal(codec.encode(runtime, unknown_status))
}

pub fn generated_native_json_matches_handwritten_json_and_decodes_test() {
  let generated = order_codec.order_codec()
  let orders = [
    order_with_note_and_status(1, codec.Missing, materialize_fixtures.Pending),
    order_with_note_and_status(
      999_999,
      codec.Present(codec.Null),
      materialize_fixtures.Processing,
    ),
    order_with_note_and_status(
      42,
      codec.Present(codec.NonNull("leave\n\r\f\t\\door 🚀")),
      materialize_fixtures.ShippedQuoted,
    ),
    order_with_note_and_status(
      42,
      codec.Missing,
      materialize_fixtures.DeliveredUnicode,
    ),
  ]
  let assert True =
    list.all(orders, fn(order) {
      let assert Ok(native_text) = order_codec.encode_order_json(order)
      let assert Ok(handwritten) = vanilla_order.encode(order)
      native_text == json.to_string(handwritten)
      && codec.encode_json(generated, order) == Ok(native_text)
      && order_codec.decode_order_json(native_text) == Ok(order)
      && codec.decode_json(generated, native_text) == Ok(order)
    })
}

pub fn generated_native_json_returns_typed_codec_errors_test() {
  let wrong_type = order_json(Some(json.string("42")), "pending", False)
  order_codec.decode_order_json(wrong_type)
  |> should.equal(
    Error(
      codec.TypedCodecFailure(codec.DecodeAtField(
        "order_id",
        codec.CannotDecode(codec.DecodeExpectedInt),
      )),
    ),
  )

  let missing_id = order_json(None, "pending", False)
  order_codec.decode_order_json(missing_id)
  |> should.equal(
    Error(
      codec.TypedCodecFailure(codec.DecodeAtField(
        "order_id",
        codec.CannotDecode(codec.DecodeMissingProperty("order_id")),
      )),
    ),
  )

  let unknown_field = order_json(Some(json.int(42)), "pending", True)
  order_codec.decode_order_json(unknown_field)
  |> should.equal(
    Error(
      codec.TypedCodecFailure(
        codec.CannotDecode(codec.DecodeUnknownProperty("unexpected")),
      ),
    ),
  )

  let unknown_status = order_json(Some(json.int(42)), "unrecognized", False)
  order_codec.decode_order_json(unknown_status)
  |> should.equal(
    Error(
      codec.TypedCodecFailure(codec.DecodeAtField(
        "status",
        codec.CannotDecode(codec.DecodeUnknownEnumLabel("unrecognized")),
      )),
    ),
  )

  let out_of_range = order_json(Some(json.int(1_000_000)), "pending", False)
  order_codec.decode_order_json(out_of_range)
  |> should.equal(
    Error(
      codec.TypedCodecFailure(codec.DecodeAtField(
        "order_id",
        codec.CannotDecode(codec.DecodeIntegerOutsideRange(
          1,
          999_999,
          1_000_000,
        )),
      )),
    ),
  )

  order_codec.decode_order_json("{")
  |> should.be_error
}

pub fn generated_native_int_accepts_exact_json_integer_forms_test() {
  order_codec.decode_order_json(order_json_source("2.0"))
  |> should.equal(Ok(empty_order(2)))

  order_codec.decode_order_json(order_json_source("2e0"))
  |> should.equal(Ok(empty_order(2)))

  order_codec.decode_order_json(order_json_source("2.5"))
  |> should.equal(
    Error(
      codec.TypedCodecFailure(codec.DecodeAtField(
        "order_id",
        codec.CannotDecode(codec.DecodeExpectedInt),
      )),
    ),
  )
}

pub fn native_integer_encoding_uses_existing_safety_checks_test() {
  let unsafe = 9_007_199_254_740_991 + 1
  let expected = codec.encode_int_value(unsafe)
  let actual = codec.encode_native_int(unsafe)
  let assert True = case expected, actual {
    Ok(value.Number(_)), Ok(json_int) -> json_int == json.int(unsafe)
    Error(expected_error), Error(actual_error) -> expected_error == actual_error
    _, _ -> False
  }

  case actual {
    Error(error) -> {
      codec.encode_native_list_with(codec.encode_native_int, [unsafe])
      |> should.equal(Error(codec.EncodeAtIndex(0, error)))
      codec.encode_native_required_property_with(
        "count",
        codec.encode_native_int,
        unsafe,
      )
      |> should.equal(Error(codec.EncodeAtField("count", error)))
    }
    Ok(_) -> Nil
  }
}

pub fn generated_native_int_decoder_rejects_unsafe_integer_results_test() {
  let unsafe = 9_007_199_254_740_991 + 1
  let unsafe_integer =
    "{\"order_id\":9007199254740992,\"items_\\\"list\\\"\":[],\"type\":true,\"status\":\"pending\"}"
  let result = order_codec.decode_order_json(unsafe_integer)

  case number.from_int(unsafe) {
    Error(number.UnsafeNativeInteger) ->
      result
      |> should.equal(
        Error(
          codec.TypedCodecFailure(codec.DecodeAtField(
            "order_id",
            codec.CannotDecode(codec.DecodeExpectedInt),
          )),
        ),
      )
    Error(number.NonFiniteInteger) -> should.be_true(False)
    Error(number.NonIntegerValue) -> should.be_true(False)
    Ok(_) ->
      result
      |> should.equal(
        Error(
          codec.TypedCodecFailure(codec.DecodeAtField(
            "order_id",
            codec.CannotDecode(codec.DecodeIntegerOutsideRange(
              1,
              999_999,
              unsafe,
            )),
          )),
        ),
      )
  }
}

pub fn generated_native_nested_integer_encoding_preserves_safety_errors_test() {
  let unsafe = 9_007_199_254_740_991 + 1
  let item =
    materialize_fixtures.Order(
      42,
      [#("unsafe", unsafe)],
      codec.Missing,
      True,
      materialize_fixtures.Pending,
    )

  case number.from_int(unsafe) {
    Error(number.UnsafeNativeInteger) ->
      order_codec.encode_order_json(item)
      |> should.equal(
        Error(codec.EncodeAtField(
          "items_\"list\"",
          codec.EncodeAtIndex(
            0,
            codec.EncodeAtIndex(
              1,
              codec.CannotEncode(codec.EncodeInvalidNativeValue(
                "UnsafeNativeInteger",
              )),
            ),
          ),
        )),
      )
    Error(number.NonFiniteInteger) -> should.be_true(False)
    Error(number.NonIntegerValue) -> should.be_true(False)
    Ok(_) ->
      case order_codec.encode_order_json(item) {
        Ok(_) -> Nil
        Error(_) -> should.be_true(False)
      }
  }
}

pub fn native_json_integer_parser_normalization_is_observable_test() {
  // gleam/json normalizes JSON numbers before Blueprint sees their lexical
  // token. A decimal just above 1 can therefore arrive as the native value 1.
  let source = order_json_source("1.0000000000000001")
  let runtime = materialize_fixtures.build_order_codec()

  codec.decode_json(runtime, source)
  |> should.be_error
  order_codec.decode_order_json(source)
  |> should.equal(Ok(empty_order(1)))
}

pub fn native_duplicate_keys_follow_backend_parser_semantics_test() {
  let duplicate_id =
    "{\"order_id\":41,\"order_id\":42,\"items_\\\"list\\\"\":[],\"type\":true,\"status\":\"pending\"}"
  let runtime = materialize_fixtures.build_order_codec()

  case codec.decode_json(runtime, duplicate_id) {
    Error(codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
      _,
      codec.BlueprintDuplicateObjectKey("order_id"),
    ))) -> should.be_true(True)
    _ -> should.be_true(False)
  }

  // Runtime Blueprint rejects duplicate keys; gleam/json first collapses the
  // object according to the target parser, which the generated codec inherits.
  let assert Ok(parser_id) =
    json.parse(from: duplicate_id, using: {
      use id <- decode.field("order_id", decode.int)
      decode.success(id)
    })
  let assert Ok(native_order) = order_codec.decode_order_json(duplicate_id)
  native_order.order_id |> should.equal(parser_id)
}

pub fn native_number_definitions_fail_with_a_typed_compile_error_test() {
  codegen.compile("generated/number", "number", codegen.number())
  |> should.equal(Error(codegen.NativeNumberUnsupported))
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
  first_content
  |> string.contains("const order_compiled_inner_property_names: List(String)")
  |> should.be_true
  first_content
  |> string.contains(
    "codec.decode_object_with(order_compiled_inner_property_names",
  )
  |> should.be_true
  first_content
  |> string.contains("import materialize_fixtures")
  |> should.be_true
  first_content
  |> string.contains("codec.from_json_parts(")
  |> should.be_true
  first_content
  |> string.contains("codec.encode_native_integer_between(1, 999_999, item)")
  |> should.be_true
  first_content
  |> string.contains("json.parse(from: source, using: decode.dynamic)")
  |> should.be_true
  first_content
  |> string.contains("codec.encode_json(")
  |> should.be_false
  first_content
  |> string.contains("codec.new(")
  |> should.be_false
  first_content
  |> string.contains("json_text.")
  |> should.be_false
  first_content
  |> string.contains("parser_core")
  |> should.be_false
  let assert Ok(integer_definition) =
    codegen.compile("generated/integer", "integer", codegen.int())
  let codegen.GeneratedModule(_, integer_content, _) = integer_definition
  integer_content
  |> string.contains("codec.encode_native_int(item)")
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

fn identity_string(value: String) -> String {
  value
}

pub fn uppercase_string(value: String) -> String {
  string.uppercase(value)
}

fn sample_order() -> materialize_fixtures.Order {
  order_with_note(codec.Present(codec.NonNull("leave at door")))
}

fn order_with_note(
  note: codec.Optional(codec.Nullable(String)),
) -> materialize_fixtures.Order {
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
  note: codec.Optional(codec.Nullable(String)),
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

fn empty_order(id: Int) -> materialize_fixtures.Order {
  materialize_fixtures.Order(
    id,
    [],
    codec.Missing,
    True,
    materialize_fixtures.Pending,
  )
}

fn replace_property(
  fields: List(#(String, value.Value)),
  name: String,
  replacement: value.Value,
) -> List(#(String, value.Value)) {
  case fields {
    [] -> []
    [#(field_name, _), ..rest] if field_name == name -> [
      #(field_name, replacement),
      ..rest
    ]
    [field, ..rest] -> [field, ..replace_property(rest, name, replacement)]
  }
}
