import gleeunit/should
import json/blueprint/codec
import json/blueprint/document
import json/blueprint/number
import json/blueprint/runtime
import json/blueprint/value

pub type Person {
  Person(name: String, age: Int, nickname: codec.Optional(String))
}

pub fn described_schema_reaches_fields_and_preserves_behavior_test() {
  let assert Ok(person_codec) =
    codec.record3(
      codec.required("name", codec.describe(codec.string(), "Full name")),
      codec.required("age", codec.describe(codec.int(), "Age in years")),
      codec.optional(
        "nickname",
        codec.describe(codec.nullable(codec.string()), "Optional nickname"),
      ),
      fn(name, age, nickname) { #(name, age, nickname) },
      fn(person) { person.0 },
      fn(person) { person.1 },
      fn(person) { person.2 },
    )
  let described = codec.describe(person_codec, "A person")
  let assert Ok(schema) = codec.schema(described)
  let assert Ok(contract) = runtime.from_codec(described)
  let assert Ok(loaded) = document.load(codec.schema_document(schema))
  runtime.schema(contract) |> should.equal(runtime.schema(loaded))
  runtime.same_schema(contract, loaded) |> should.equal(True)
  let assert Ok(bare_contract) = runtime.from_codec(person_codec)
  runtime.same_schema(contract, bare_contract) |> should.equal(True)
  let assert Ok(unannotated) =
    runtime.from_schema(
      codec.ObjectSchema([
        codec.PropertySchema("name", True, codec.StringSchema),
        codec.PropertySchema("age", True, codec.IntSchema),
        codec.PropertySchema(
          "nickname",
          False,
          codec.NullableSchema(codec.StringSchema),
        ),
      ]),
    )
  runtime.same_schema(contract, unannotated) |> should.equal(True)
  let assert Ok(age) = number.from_int(37)
  let assert Ok(validated) =
    runtime.validate(
      contract,
      value.Object([
        #("name", value.String("Ada")),
        #("age", value.Number(age)),
      ]),
    )
  runtime.matches(unannotated, validated) |> should.equal(True)
  codec.schema_json(described)
  |> should.equal(Ok(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"description\":\"A person\",\"type\":\"object\",\"properties\":{\"name\":{\"description\":\"Full name\",\"type\":\"string\"},\"age\":{\"description\":\"Age in years\",\"type\":\"integer\"},\"nickname\":{\"description\":\"Optional nickname\",\"anyOf\":[{\"type\":\"null\"},{\"type\":\"string\"}]}},\"required\":[\"name\",\"age\"],\"additionalProperties\":false}",
  ))
  codec.decode_json(described, "{\"name\":\"Ada\",\"age\":37}")
  |> should.equal(Ok(#("Ada", 37, codec.Missing)))
  codec.encode_json(described, #("Ada", 37, codec.Missing))
  |> should.equal(Ok("{\"name\":\"Ada\",\"age\":37}"))
}

pub fn description_replacement_and_unknown_schema_test() {
  let described =
    codec.string()
    |> codec.describe("first")
    |> codec.describe("second")
  codec.schema(described)
  |> should.equal(Ok(codec.DescribedSchema("second", codec.StringSchema)))
  let custom =
    codec.new(fn(item: String) { Ok(value.String(item)) }, fn(_) {
      Error(codec.CannotDecode(codec.DecodeExpectedString))
    })
  codec.schema(codec.describe(custom, "unknown"))
  |> should.equal(Error(codec.UnknownSchema))
}

pub fn public_decode_error_renderer_handles_paths_and_private_values_test() {
  codec.render_json_decode_error(
    codec.TypedCodecFailure(codec.DecodeAtField(
      "items",
      codec.DecodeAtIndex(
        1,
        codec.DecodeAtField(
          "delivery.code",
          codec.CannotDecode(codec.DecodeExpectedString),
        ),
      ),
    )),
  )
  |> should.equal("$[\"items\"][1][\"delivery.code\"]: expected a string")

  codec.render_json_decode_error(
    codec.TypedCodecFailure(codec.DecodeAtField(
      "amount",
      codec.CannotDecode(codec.DecodeIntegerOutsideRange(1, 100, 999)),
    )),
  )
  |> should.equal("$[\"amount\"]: integer outside range 1 to 100")

  codec.render_json_decode_error(
    codec.TypedCodecFailure(
      codec.CannotDecode(codec.CustomDecodeReason("secret value")),
    ),
  )
  |> should.equal("$: custom validation failed")

  codec.render_json_decode_error(
    codec.TypedCodecFailure(codec.DecodeAtField(
      "account-secret",
      codec.CannotDecode(codec.DecodeUnknownProperty("account-secret")),
    )),
  )
  |> should.equal("$: unknown property")

  codec.render_json_decode_error(
    codec.TypedCodecFailure(codec.DecodeAtField(
      "tag",
      codec.CannotDecode(codec.DecodeUnknownTag("private-tag")),
    )),
  )
  |> should.equal("$[\"tag\"]: unknown tag")

  codec.render_json_decode_error(
    codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
      codec.BlueprintJsonLocation(6, 1, 7),
      codec.BlueprintUnexpectedEndOfInput,
    )),
  )
  |> should.equal("invalid JSON at line 1, column 7: unexpected end of input")

  codec.render_json_decode_error(
    codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
      codec.BlueprintJsonLocation(9, 1, 10),
      codec.BlueprintDuplicateObjectKey("private-key"),
    )),
  )
  |> should.equal("invalid JSON at line 1, column 10: duplicate object key")
}

pub fn schema_json_exports_complete_document_test() {
  let assert Ok(person_codec) =
    codec.record3(
      codec.required("name", codec.string()),
      codec.required("age", codec.int()),
      codec.optional("nickname", codec.string()),
      Person,
      fn(person) { person.name },
      fn(person) { person.age },
      fn(person) { person.nickname },
    )

  codec.schema_json(person_codec)
  |> should.equal(Ok(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"age\":{\"type\":\"integer\"},\"nickname\":{\"type\":\"string\"}},\"required\":[\"name\",\"age\"],\"additionalProperties\":false}",
  ))
}

pub fn schema_json_rejects_unknown_schema_test() {
  let custom =
    codec.new(fn(item: String) { Ok(value.String(item)) }, fn(raw) {
      case raw {
        value.String(item) -> Ok(item)
        _ -> Error(codec.CannotDecode(codec.DecodeExpectedString))
      }
    })

  codec.schema_json(custom)
  |> should.equal(Error(codec.UnknownSchema))
  codec.schema_json(codec.list(custom))
  |> should.equal(Error(codec.UnknownSchema))
}

pub fn record3_public_usage_test() {
  let assert Ok(person_codec) =
    codec.record3(
      codec.required("name", codec.string()),
      codec.required("age", codec.int()),
      codec.optional("nickname", codec.string()),
      Person,
      fn(person) { person.name },
      fn(person) { person.age },
      fn(person) { person.nickname },
    )

  codec.encode_json(person_codec, Person("Ada", 37, codec.Missing))
  |> should.equal(Ok("{\"name\":\"Ada\",\"age\":37}"))
  codec.decode_json(person_codec, "{\"name\":\"Ada\",\"age\":37}")
  |> should.equal(Ok(Person("Ada", 37, codec.Missing)))
  codec.decode_json(
    person_codec,
    "{\"name\":\"Ada\",\"age\":37,\"nickname\":\"A\"}",
  )
  |> should.equal(Ok(Person("Ada", 37, codec.Present("A"))))

  codec.decode(person_codec, value.Object([#("name", value.String("Ada"))]))
  |> should.equal(
    Error(codec.DecodeAtField(
      "age",
      codec.CannotDecode(codec.DecodeMissingProperty("age")),
    )),
  )
  codec.decode(
    person_codec,
    value.Object([
      #("name", value.String("Ada")),
      #("age", int_value(37)),
      #("nickname", value.Null),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "nickname",
      codec.CannotDecode(codec.DecodeExpectedString),
    )),
  )
  codec.decode(
    person_codec,
    value.Object([
      #("name", value.String("Ada")),
      #("age", int_value(37)),
      #("extra", value.Bool(True)),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "extra",
      codec.CannotDecode(codec.DecodeUnknownProperty("extra")),
    )),
  )

  case
    codec.decode_json(
      person_codec,
      "{\"name\":\"Ada\",\"age\":37,\"name\":\"Eve\"}",
    )
  {
    Error(codec.BlueprintParserFailure(codec.BlueprintJsonParseFailure(
      _,
      codec.BlueprintDuplicateObjectKey("name"),
    ))) -> True
    _ -> False
  }
  |> should.be_true
}

pub fn record2_duplicate_admission_test() {
  codec.record2(
    codec.required("same", codec.string()),
    codec.required("same", codec.int()),
    fn(name, age) { Person(name, age, codec.Missing) },
    fn(person) { person.name },
    fn(person) { person.age },
  )
  |> should.equal(Error(codec.DuplicateProperty("same")))
}

pub fn record3_duplicate_later_property_test() {
  codec.record3(
    codec.required("name", codec.string()),
    codec.required("age", codec.int()),
    codec.optional("age", codec.string()),
    Person,
    fn(person) { person.name },
    fn(person) { person.age },
    fn(person) { person.nickname },
  )
  |> should.equal(Error(codec.DuplicateProperty("age")))
}

fn int_value(n: Int) -> value.Value {
  let assert Ok(v) = number.from_int(n)
  value.Number(v)
}
