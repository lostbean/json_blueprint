@target(erlang)
import gleeunit/should
@target(erlang)
import json/blueprint/codec
@target(erlang)
import json/blueprint/number
@target(erlang)
import json/blueprint/runtime
@target(erlang)
import json/blueprint/value

@target(erlang)
pub fn contract_normalization_sorting_test() {
  // Object properties should normalize in alphabetical order
  let unsorted_schema =
    codec.ObjectSchema([
      codec.PropertySchema("zeta", True, codec.StringSchema),
      codec.PropertySchema("alpha", False, codec.IntSchema),
      codec.PropertySchema("beta", True, codec.BoolSchema),
    ])

  let assert Ok(contract) = runtime.from_schema(unsorted_schema)
  runtime.schema(contract)
  |> should.equal(
    codec.ObjectSchema([
      codec.PropertySchema("alpha", False, codec.IntSchema),
      codec.PropertySchema("beta", True, codec.BoolSchema),
      codec.PropertySchema("zeta", True, codec.StringSchema),
    ]),
  )

  // Enum labels should normalize in alphabetical order
  let unsorted_enum = codec.StringEnumSchema(["urgent", "low", "normal"])
  let assert Ok(enum_contract) = runtime.from_schema(unsorted_enum)
  runtime.schema(enum_contract)
  |> should.equal(codec.StringEnumSchema(["low", "normal", "urgent"]))

  // Tagged alternatives should normalize in alphabetical order
  let unsorted_tagged =
    codec.TaggedSchema("zeta", codec.IntSchema, "alpha", codec.StringSchema)
  let assert Ok(tagged_contract) = runtime.from_schema(unsorted_tagged)
  runtime.schema(tagged_contract)
  |> should.equal(codec.TaggedSchema(
    "alpha",
    codec.StringSchema,
    "zeta",
    codec.IntSchema,
  ))

  // same_schema respects normalization
  let sorted_schema =
    codec.ObjectSchema([
      codec.PropertySchema("alpha", False, codec.IntSchema),
      codec.PropertySchema("beta", True, codec.BoolSchema),
      codec.PropertySchema("zeta", True, codec.StringSchema),
    ])
  let assert Ok(sorted_contract) = runtime.from_schema(sorted_schema)
  runtime.same_schema(contract, sorted_contract)
  |> should.equal(True)
}

@target(erlang)
pub fn contract_normalization_invariants_test() {
  // Reversed integer range
  runtime.from_schema(codec.IntegerRangeSchema(10, 5))
  |> should.equal(Error(runtime.ReversedIntegerRange(10, 5)))

  // Reversed number range
  let min = number.from_int(20)
  let max = number.from_int(10)
  runtime.from_schema(codec.NumberRangeSchema(min, max))
  |> should.equal(Error(runtime.ReversedNumberRange(min, max)))

  // Duplicate object properties
  runtime.from_schema(
    codec.ObjectSchema([
      codec.PropertySchema("dup", True, codec.StringSchema),
      codec.PropertySchema("dup", False, codec.IntSchema),
    ]),
  )
  |> should.equal(Error(runtime.DuplicateSchemaProperty("dup")))

  // Duplicate tags
  runtime.from_schema(codec.TaggedSchema(
    "same",
    codec.StringSchema,
    "same",
    codec.IntSchema,
  ))
  |> should.equal(Error(runtime.DuplicateSchemaTag("same")))

  // Empty string enum
  runtime.from_schema(codec.StringEnumSchema([]))
  |> should.equal(Error(runtime.EmptyStringEnum))

  // Duplicate enum labels
  runtime.from_schema(codec.StringEnumSchema(["a", "b", "a"]))
  |> should.equal(Error(runtime.DuplicateSchemaEnumLabel("a")))
}

@target(erlang)
pub fn validation_located_errors_test() {
  // Root error
  let assert Ok(str_contract) = runtime.from_schema(codec.StringSchema)
  runtime.validate(str_contract, value.Number(number.from_int(123)))
  |> should.equal(Error(runtime.ValidationError([], runtime.ExpectedString)))

  // Nested object field error
  let assert Ok(obj_contract) =
    runtime.from_schema(
      codec.ObjectSchema([
        codec.PropertySchema(
          "user",
          True,
          codec.ObjectSchema([
            codec.PropertySchema("age", True, codec.IntSchema),
          ]),
        ),
      ]),
    )

  runtime.validate(
    obj_contract,
    value.Object([
      #("user", value.Object([#("age", value.String("not-an-int"))])),
    ]),
  )
  |> should.equal(
    Error(runtime.ValidationError(
      [runtime.Property("user"), runtime.Property("age")],
      runtime.ExpectedInteger,
    )),
  )

  // Array index error
  let assert Ok(list_contract) =
    runtime.from_schema(codec.ListSchema(codec.StringSchema))
  runtime.validate(
    list_contract,
    value.Array([value.String("ok"), value.Bool(True)]),
  )
  |> should.equal(
    Error(runtime.ValidationError([runtime.Index(1)], runtime.ExpectedString)),
  )

  // Closed object: unexpected extra field
  let assert Ok(simple_obj_contract) =
    runtime.from_schema(
      codec.ObjectSchema([
        codec.PropertySchema("name", True, codec.StringSchema),
      ]),
    )
  runtime.validate(
    simple_obj_contract,
    value.Object([
      #("name", value.String("valid")),
      #("extra", value.Null),
    ]),
  )
  |> should.equal(
    Error(runtime.ValidationError(
      [runtime.Property("extra")],
      runtime.UnknownProperty("extra"),
    )),
  )

  // Missing required field
  runtime.validate(simple_obj_contract, value.Object([]))
  |> should.equal(
    Error(runtime.ValidationError(
      [runtime.Property("name")],
      runtime.MissingProperty("name"),
    )),
  )

  // Duplicate key in payload
  runtime.validate(
    simple_obj_contract,
    value.Object([
      #("name", value.String("first")),
      #("name", value.String("second")),
    ]),
  )
  |> should.equal(
    Error(runtime.ValidationError(
      [runtime.Property("name")],
      runtime.DuplicateProperty("name"),
    )),
  )

  // Tagged branch validation and error
  let assert Ok(tagged_contract) =
    runtime.from_schema(codec.TaggedSchema(
      "approve",
      codec.ObjectSchema([
        codec.PropertySchema("qty", True, codec.IntegerRangeSchema(1, 10)),
      ]),
      "decline",
      codec.ObjectSchema([
        codec.PropertySchema("reason", True, codec.StringSchema),
      ]),
    ))

  // Valid tagged
  let valid_tagged =
    value.Object([
      #("tag", value.String("approve")),
      #("value", value.Object([#("qty", value.Number(number.from_int(5)))])),
    ])
  let assert Ok(validated) = runtime.validate(tagged_contract, valid_tagged)
  runtime.encoded(validated)
  |> should.equal(valid_tagged)
  runtime.matches(tagged_contract, validated)
  |> should.equal(True)

  // Tagged payload out of range
  let invalid_tagged =
    value.Object([
      #("tag", value.String("approve")),
      #("value", value.Object([#("qty", value.Number(number.from_int(0)))])),
    ])
  runtime.validate(tagged_contract, invalid_tagged)
  |> should.equal(
    Error(runtime.ValidationError(
      [
        runtime.Property("value"),
        runtime.TaggedBranch("approve"),
        runtime.Property("qty"),
      ],
      runtime.IntegerOutsideRange(1, 10, 0),
    )),
  )

  // Tagged unknown tag
  runtime.validate(
    tagged_contract,
    value.Object([
      #("tag", value.String("unknown")),
      #("value", value.Null),
    ]),
  )
  |> should.equal(
    Error(runtime.ValidationError(
      [runtime.Property("tag")],
      runtime.UnknownTag("unknown"),
    )),
  )
}

@target(erlang)
pub fn runtime_decode_test() {
  let c = codec.pair(codec.string(), codec.int())
  let assert Ok(contract) = runtime.from_codec(c)

  let raw =
    value.Array([value.String("item"), value.Number(number.from_int(42))])
  let assert Ok(validated) = runtime.validate(contract, raw)

  runtime.decode(c, validated)
  |> should.equal(Ok(#("item", 42)))
}
