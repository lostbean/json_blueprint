import gleeunit/should
import json/blueprint as legacy
import json/blueprint/codec

pub type Person {
  Person(name: String, age: Int)
}

pub fn person_codec() -> codec.Codec(Person) {
  let assert Ok(person) =
    codec.record2(
      codec.required("name", codec.string()),
      codec.required("age", codec.int()),
      Person,
      fn(person) { person.name },
      fn(person) { person.age },
    )
  person
}

pub fn one_way_decoder_to_schema_bearing_codec_test() {
  let legacy_decoder =
    legacy.decode2(
      Person,
      legacy.field("name", legacy.string()),
      legacy.field("age", legacy.int()),
    )

  let json = "{\"name\":\"Alice\",\"age\":30}"
  legacy.decode(using: legacy_decoder, from: json)
  |> should.equal(Ok(Person("Alice", 30)))

  let modern_codec = person_codec()
  codec.decode_json(modern_codec, json)
  |> should.equal(Ok(Person("Alice", 30)))
  codec.encode_json(modern_codec, Person("Alice", 30))
  |> should.equal(Ok(json))
  codec.schema_json(modern_codec) |> should.be_ok

  // Legacy object decoders accepted unrelated fields. Codec objects are closed.
  let extra = "{\"name\":\"Alice\",\"age\":30,\"extra\":true}"
  legacy.decode(using: legacy_decoder, from: extra)
  |> should.equal(Ok(Person("Alice", 30)))
  codec.decode_json(modern_codec, extra) |> should.be_error
}
