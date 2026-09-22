import gleeunit/should
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value

pub type Person {
  Person(name: String, age: Int, nickname: codec.Optional(String))
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
