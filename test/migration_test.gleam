//// Moving a 1.x `Decoder` to a 2.0 `Codec`: the same record, and the wire
//// differences that need review against stored data.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}
import gleeunit/should
import json/blueprint as legacy
import json/blueprint/codec.{type Codec}

pub type Person {
  Person(name: String, age: Int)
}

pub fn person_codec() -> Codec(Person) {
  use name <- codec.field("name", codec.string(), fn(p: Person) { p.name })
  use age <- codec.field("age", codec.int(), fn(p: Person) { p.age })
  codec.success(Person(name:, age:))
}

fn legacy_person() -> legacy.Decoder(Person) {
  legacy.decode2(
    Person,
    legacy.field("name", legacy.string()),
    legacy.field("age", legacy.int()),
  )
}

pub fn one_way_decoder_to_schema_bearing_codec_test() {
  let text = "{\"name\":\"Alice\",\"age\":30}"
  legacy.decode(using: legacy_person(), from: text)
  |> should.equal(Ok(Person("Alice", 30)))
  codec.decode_json(person_codec(), text)
  |> should.equal(Ok(Person("Alice", 30)))
  codec.encode_json(person_codec(), Person("Alice", 30))
  |> should.equal(Ok(text))
  codec.schema_json(person_codec()) |> should.be_ok
}

pub fn codec_objects_are_closed_test() {
  // 1.x object decoders accepted unrelated fields.
  let extra = "{\"name\":\"Alice\",\"age\":30,\"extra\":true}"
  legacy.decode(using: legacy_person(), from: extra)
  |> should.equal(Ok(Person("Alice", 30)))
  codec.decode_json(person_codec(), extra) |> should.be_error
}

pub type Contact {
  Contact(email: Option(String))
}

pub fn optional_fields_distinguish_null_test() {
  let legacy_contact =
    legacy.decode1(Contact, legacy.optional_field("email", legacy.string()))
  legacy.decode(using: legacy_contact, from: "{\"email\":null}")
  |> should.equal(Ok(Contact(None)))
  let contact = {
    use email <- codec.optional_field("email", codec.string(), fn(c: Contact) {
      c.email
    })
    codec.success(Contact(email:))
  }
  codec.decode_json(contact, "{}") |> should.equal(Ok(Contact(None)))
  codec.decode_json(contact, "{\"email\":null}") |> should.be_error
}

pub type Shape {
  Circle(radius: Int)
  Point
}

pub fn union_envelopes_differ_test() {
  let legacy_text =
    legacy.union_type_encoder(Circle(2), fn(shape) {
      case shape {
        Circle(radius) -> #(
          "circle",
          json.object([#("radius", json.int(radius))]),
        )
        Point -> #("point", json.object([]))
      }
    })
    |> json.to_string
  legacy_text
  |> should.equal("{\"type\":\"circle\",\"data\":{\"radius\":2}}")
  let shape =
    codec.union({
      use circle <- codec.variant("circle", codec.int(), Circle)
      use point <- codec.unit_variant("point", Point)
      codec.match(fn(shape) {
        case shape {
          Circle(radius) -> circle(radius)
          Point -> point
        }
      })
    })
  codec.encode_json(shape, Circle(2))
  |> should.equal(Ok("{\"tag\":\"circle\",\"value\":2}"))
  codec.decode_json(shape, legacy_text) |> should.be_error
}

pub type Level {
  High
  Low
}

pub fn enums_encode_a_bare_label_test() {
  legacy.enum_type_encoder(High, fn(level) {
    case level {
      High -> "high"
      Low -> "low"
    }
  })
  |> json.to_string
  |> should.equal("{\"enum\":\"high\"}")
  codec.encode_json(codec.string_enum([#("high", High), #("low", Low)]), High)
  |> should.equal(Ok("\"high\""))
}

pub fn get_dynamic_decoder_uses_stdlib_errors_test() {
  let assert Ok(raw) = json.parse("{\"name\":1,\"age\":2}", decode.dynamic)
  let assert Error([error]) = legacy.get_dynamic_decoder(legacy_person())(raw)
  error.path |> should.equal(["name"])
}
