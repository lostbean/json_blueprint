import gleam/option.{type Option, None, Some}
import gleeunit/should
import json/blueprint/codec.{Field, Index}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

pub type Person {
  Person(name: String, age: Int, nickname: Option(String))
}

type DescribedPerson =
  #(String, Int, Option(Option(String)))

fn described_person_codec() -> codec.Codec(DescribedPerson) {
  use name <- codec.field(
    "name",
    codec.describe(codec.string(), "Full name"),
    get: fn(p) { p.0 },
  )
  use age <- codec.field(
    "age",
    codec.describe(codec.int(), "Age in years"),
    get: fn(p) { p.1 },
  )
  use nickname <- codec.optional_field(
    "nickname",
    codec.describe(codec.nullable(codec.string()), "Optional nickname"),
    get: fn(p) { p.2 },
  )
  codec.success(#(name, age, nickname))
}

fn bare_person_codec() -> codec.Codec(DescribedPerson) {
  use name <- codec.field("name", codec.string(), get: fn(p) { p.0 })
  use age <- codec.field("age", codec.int(), get: fn(p) { p.1 })
  use nickname <- codec.optional_field(
    "nickname",
    codec.nullable(codec.string()),
    get: fn(p) { p.2 },
  )
  codec.success(#(name, age, nickname))
}

fn person_codec() -> codec.Codec(Person) {
  use name <- codec.field("name", codec.string(), get: fn(p) { p.name })
  use age <- codec.field("age", codec.int(), get: fn(p) { p.age })
  use nickname <- codec.optional_field("nickname", codec.string(), get: fn(p) {
    p.nickname
  })
  codec.success(Person(name:, age:, nickname:))
}

fn bare_schema() -> codec.Schema {
  let assert Ok(schema) = codec.schema(bare_person_codec())
  schema
}

pub fn described_schema_reaches_fields_and_preserves_behavior_test() {
  let described = codec.describe(described_person_codec(), "A person")
  let assert Ok(schema) = codec.schema(described)
  let assert Ok(described_contract) = contract.from_codec(described)
  let assert Ok(loaded) = contract.load(codec.schema_document(schema))
  contract.schema(described_contract) |> should.equal(contract.schema(loaded))
  contract.same_schema(described_contract, loaded) |> should.equal(True)
  let assert Ok(bare_contract) = contract.from_codec(described_person_codec())
  contract.same_schema(described_contract, bare_contract) |> should.equal(True)
  let unannotated = contract.from_schema(bare_schema())
  contract.same_schema(described_contract, unannotated) |> should.equal(True)
  let assert Ok(age) = number.from_int(37)
  let raw =
    value.Object([#("name", value.String("Ada")), #("age", value.Number(age))])

  // A value validated by the described contract decodes with a codec without
  // descriptions, and one validated by the unannotated contract decodes with
  // the described codec: descriptions do not affect matching
  let assert Ok(validated) = contract.validate(described_contract, raw)
  contract.decode(bare_person_codec(), validated)
  |> should.equal(Ok(#("Ada", 37, None)))
  let assert Ok(validated) = contract.validate(unannotated, raw)
  contract.decode(described, validated)
  |> should.equal(Ok(#("Ada", 37, None)))

  codec.schema_json(described)
  |> should.equal(Ok(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"description\":\"A person\",\"type\":\"object\",\"properties\":{\"name\":{\"description\":\"Full name\",\"type\":\"string\"},\"age\":{\"description\":\"Age in years\",\"type\":\"integer\"},\"nickname\":{\"description\":\"Optional nickname\",\"anyOf\":[{\"type\":\"null\"},{\"type\":\"string\"}]}},\"required\":[\"name\",\"age\"],\"additionalProperties\":false}",
  ))
  codec.decode_json(described, "{\"name\":\"Ada\",\"age\":37}")
  |> should.equal(Ok(#("Ada", 37, None)))
  codec.decode_json(
    described,
    "{\"name\":\"Ada\",\"age\":37,\"nickname\":null}",
  )
  |> should.equal(Ok(#("Ada", 37, Some(None))))
  codec.encode_json(described, #("Ada", 37, None))
  |> should.equal(Ok("{\"name\":\"Ada\",\"age\":37}"))
  codec.encode_json(described, #("Ada", 37, Some(Some("A"))))
  |> should.equal(Ok("{\"name\":\"Ada\",\"age\":37,\"nickname\":\"A\"}"))
}

pub fn description_replacement_and_unknown_schema_test() {
  let described =
    codec.string()
    |> codec.describe("first")
    |> codec.describe("second")
  let assert Ok(schema) = codec.schema(described)
  codec.description(schema) |> should.equal(Some("second"))
  codec.view(schema) |> should.equal(codec.StringSchema)
  codec.schema_value(schema)
  |> should.equal(
    value.Object([
      #("description", value.String("second")),
      #("type", value.String("string")),
    ]),
  )
  let custom =
    codec.custom(
      encode: fn(item: String) { Ok(value.String(item)) },
      decode: fn(_) { Error(codec.DecodeError([], codec.ExpectedString)) },
      schema: None,
      placeholder: "",
    )
  codec.schema(codec.describe(custom, "unknown"))
  |> should.equal(Error(codec.UnknownSchema))
}

pub fn public_decode_error_renderer_handles_paths_and_private_values_test() {
  codec.describe_decode_error(codec.DecodeError(
    [Field("items"), Index(1), Field("delivery.code")],
    codec.ExpectedString,
  ))
  |> should.equal("$[\"items\"][1][\"delivery.code\"]: expected a string")

  codec.describe_decode_error(codec.DecodeError(
    [Field("amount")],
    codec.IntegerOutsideRange(1, 100),
  ))
  |> should.equal("$[\"amount\"]: integer outside range 1 to 100")

  codec.describe_decode_error(codec.decode_failure("caller's message"))
  |> should.equal("$: caller's message")

  codec.describe_decode_error(codec.decode_failure(""))
  |> should.equal("$: custom validation failed")

  codec.describe_encode_error(codec.EncodeError(
    [Field("total")],
    codec.Custom("total differs from the line sum"),
  ))
  |> should.equal("$[\"total\"]: total differs from the line sum")

  codec.describe_decode_error(codec.DecodeError(
    [Field("account-secret")],
    codec.UnknownField,
  ))
  |> should.equal("$: unknown field")

  codec.describe_decode_error(codec.DecodeError(
    [Field("tag")],
    codec.UnknownTag,
  ))
  |> should.equal("$[\"tag\"]: unknown tag")

  codec.describe_decode_error(codec.DecodeError(
    [],
    codec.InvalidJson(value.ParseError(
      value.Location(6, 1, 7),
      value.UnexpectedEndOfInput,
    )),
  ))
  |> should.equal("invalid JSON at line 1, column 7: unexpected end of input")

  codec.describe_decode_error(codec.DecodeError(
    [],
    codec.InvalidJson(value.ParseError(
      value.Location(9, 1, 10),
      value.DuplicateObjectKey,
    )),
  ))
  |> should.equal("invalid JSON at line 1, column 10: duplicate object key")

  // The same texts from real decoding
  let assert Error(error) =
    codec.decode_json(person_codec(), "{\"name\":\"Ada\",\"age\":37,\"pin\":1}")
  codec.describe_decode_error(error) |> should.equal("$: unknown field")
  let assert Error(error) =
    codec.decode_json(person_codec(), "{\"name\":\"Ada\",\"name\":\"x\"}")
  codec.describe_decode_error(error)
  |> should.equal("invalid JSON at line 1, column 15: duplicate object key")
  let assert Error(error) = codec.decode_json(person_codec(), "{\"name\":")
  codec.describe_decode_error(error)
  |> should.equal("invalid JSON at line 1, column 9: unexpected end of input")
}

pub fn schema_json_exports_complete_document_test() {
  codec.schema_json(person_codec())
  |> should.equal(Ok(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"age\":{\"type\":\"integer\"},\"nickname\":{\"type\":\"string\"}},\"required\":[\"name\",\"age\"],\"additionalProperties\":false}",
  ))
}

pub fn schema_json_rejects_unknown_schema_test() {
  let custom =
    codec.custom(
      encode: fn(item: String) { Ok(value.String(item)) },
      decode: fn(raw) {
        case raw {
          value.String(item) -> Ok(item)
          _ -> Error(codec.DecodeError([], codec.ExpectedString))
        }
      },
      schema: None,
      placeholder: "",
    )

  codec.schema_json(custom)
  |> should.equal(Error(codec.UnknownSchema))
  codec.schema_json(codec.list(custom))
  |> should.equal(Error(codec.UnknownSchema))

  // The codec still encodes and decodes
  codec.decode_json(codec.list(custom), "[\"a\"]") |> should.equal(Ok(["a"]))
  codec.encode_json(codec.list(custom), ["a"]) |> should.equal(Ok("[\"a\"]"))
}

pub fn record_public_usage_test() {
  codec.encode_json(person_codec(), Person("Ada", 37, None))
  |> should.equal(Ok("{\"name\":\"Ada\",\"age\":37}"))
  codec.decode_json(person_codec(), "{\"name\":\"Ada\",\"age\":37}")
  |> should.equal(Ok(Person("Ada", 37, None)))
  codec.decode_json(
    person_codec(),
    "{\"name\":\"Ada\",\"age\":37,\"nickname\":\"A\"}",
  )
  |> should.equal(Ok(Person("Ada", 37, Some("A"))))
  codec.encode_json(person_codec(), Person("Ada", 37, Some("A")))
  |> should.equal(Ok("{\"name\":\"Ada\",\"age\":37,\"nickname\":\"A\"}"))

  codec.decode(person_codec(), value.Object([#("name", value.String("Ada"))]))
  |> should.equal(Error(codec.DecodeError([Field("age")], codec.MissingField)))
  codec.decode(
    person_codec(),
    value.Object([
      #("name", value.String("Ada")),
      #("age", int_value(37)),
      #("nickname", value.Null),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeError([Field("nickname")], codec.ExpectedString)),
  )
  codec.decode(
    person_codec(),
    value.Object([
      #("name", value.String("Ada")),
      #("age", int_value(37)),
      #("extra", value.Bool(True)),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeError([Field("extra")], codec.UnknownField)),
  )

  case
    codec.decode_json(
      person_codec(),
      "{\"name\":\"Ada\",\"age\":37,\"name\":\"Eve\"}",
    )
  {
    Error(codec.DecodeError(
      [],
      codec.InvalidJson(value.ParseError(_, value.DuplicateObjectKey)),
    )) -> True
    _ -> False
  }
  |> should.be_true

  // A repeated member in a hand-built value
  codec.decode(
    person_codec(),
    value.Object([
      #("name", value.String("Ada")),
      #("age", int_value(37)),
      #("age", int_value(38)),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeError([Field("age")], codec.DuplicateField)),
  )
}

pub fn record_duplicate_field_definition_test() {
  // Repeated field names are definition mistakes: `check` reports them, and
  // every other use panics
  let same = {
    use name <- codec.field("same", codec.string(), get: fn(p) { p.name })
    use age <- codec.field("same", codec.int(), get: fn(p) { p.age })
    codec.success(Person(name, age, None))
  }
  codec.check(same)
  |> should.equal(Error(codec.DuplicateFieldName("same")))
}

pub fn record_duplicate_later_field_definition_test() {
  let later = {
    use name <- codec.field("name", codec.string(), get: fn(p) { p.name })
    use age <- codec.field("age", codec.int(), get: fn(p) { p.age })
    use nickname <- codec.optional_field("age", codec.string(), get: fn(p) {
      p.nickname
    })
    codec.success(Person(name, age, nickname))
  }
  codec.check(later)
  |> should.equal(Error(codec.DuplicateFieldName("age")))

  // A record without repeats passes `check` unchanged
  let assert Ok(checked) = codec.check(person_codec())
  codec.schema(checked) |> should.equal(codec.schema(person_codec()))
}

fn int_value(n: Int) -> value.Value {
  let assert Ok(v) = number.from_int(n)
  value.Number(v)
}
