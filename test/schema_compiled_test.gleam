import generated/schema_empty
import generated/schema_feature
import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value
import schema_codegen_runner

fn exact(token: String) -> number.Number {
  let assert Ok(number) = number.parse(token, number.limits(1024, 800, 2000))
  number
}

fn example() -> schema_feature.Feature {
  schema_feature.Feature(
    True,
    #(schema_feature.FeaturePairFirst, Some(Some(12))),
    exact("1e1500"),
    None,
    "native",
    None,
    None,
  )
}

pub fn generated_native_records_preserve_wire_names_descriptions_and_bounds_test() {
  let codec = schema_feature.feature_codec()
  let assert Ok(generated_schema) = codec.schema(codec)
  let original = schema_codegen_runner.feature_schema()
  contract.same_schema(
    contract.from_schema(original),
    contract.from_schema(generated_schema),
  )
  |> should.be_true
  codec.description(generated_schema)
  |> should.equal(codec.description(original))
  let native = example()
  let assert Ok(encoded) = codec.encode(codec, native)
  codec.decode(codec, encoded) |> should.equal(Ok(native))
  let assert value.Object(fields) = encoded
  fields
  |> should.equal([
    #("1 id", value.Bool(True)),
    #("pair", value.Array([value.Object([]), value.Number(exact("12"))])),
    #("range", value.Number(exact("1e1500"))),
    #("wire\u{0}x", value.String("native")),
  ])
  codec.encode(codec, schema_feature.Feature(..native, range: exact("9e1499")))
  |> should.equal(
    Error(codec.EncodeError(
      [codec.Field("range")],
      codec.NumberOutsideRange(
        exact("1e1500"),
        exact("1.0000000000000000000001e1500"),
      ),
    )),
  )
}

pub fn repeated_nullable_preserves_inner_null_encoding_failure_test() {
  let native =
    schema_feature.Feature(..example(), pair: #(
      schema_feature.FeaturePairFirst,
      Some(None),
    ))
  codec.encode(schema_feature.feature_codec(), native)
  |> should.equal(
    Error(codec.EncodeError(
      [codec.Field("pair"), codec.Index(1)],
      codec.NullInsideNullable,
    )),
  )
}

pub fn empty_object_has_a_native_constructor_and_rejects_unknown_fields_test() {
  let codec = schema_empty.empty_codec()
  codec.decode(codec, value.Object([])) |> should.equal(Ok(schema_empty.Empty))
  codec.encode(codec, schema_empty.Empty) |> should.equal(Ok(value.Object([])))
  codec.decode(codec, value.Object([#("extra", value.Null)]))
  |> should.equal(
    Error(codec.DecodeError([codec.Field("extra")], codec.UnknownField)),
  )
}
