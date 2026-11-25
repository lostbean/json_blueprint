//// Moving from the removed 1.x `Decoder` API to codecs: the same record, the
//// wire differences that need review against stored data, and recursive
//// data read from a bounded `Value`. The 1.x wire forms appear as literal
//// text because the 1.x module no longer exists.

import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleeunit/should
import json/blueprint/codec.{type Codec}
import json/blueprint/value.{type Value}

pub type Person {
  Person(name: String, age: Int)
}

// 1.x: `blueprint.decode2(Person, blueprint.field("name", blueprint.string()),
// blueprint.field("age", blueprint.int()))`.
pub fn person_codec() -> Codec(Person) {
  use name <- codec.field("name", codec.string(), get: fn(p) { p.name })
  use age <- codec.field("age", codec.int(), get: fn(p) { p.age })
  codec.success(Person(name:, age:))
}

pub fn one_way_decoder_to_schema_bearing_codec_test() {
  let text = "{\"name\":\"Alice\",\"age\":30}"
  codec.decode_json(person_codec(), text)
  |> should.equal(Ok(Person("Alice", 30)))
  codec.encode_json(person_codec(), Person("Alice", 30))
  |> should.equal(Ok(text))
  codec.schema_json(person_codec()) |> should.be_ok
}

pub fn codec_objects_are_closed_test() {
  // 1.x object decoders accepted unrelated fields.
  let extra = "{\"name\":\"Alice\",\"age\":30,\"extra\":true}"
  codec.decode_json(person_codec(), extra) |> should.be_error
}

pub type Contact {
  Contact(email: Option(String))
}

pub fn optional_fields_distinguish_null_test() {
  // 1.x `optional_field` decoded both `{}` and `{"email":null}` to `None`.
  let contact = {
    use email <- codec.optional_field("email", codec.string(), get: fn(c) {
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
  // What 1.x `union_type_encoder` wrote for `Circle(2)`.
  let legacy_text = "{\"type\":\"circle\",\"data\":{\"radius\":2}}"
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
  // 1.x `enum_type_encoder` wrote `{"enum":"high"}`.
  codec.encode_json(codec.string_enum([#("high", High), #("low", Low)]), High)
  |> should.equal(Ok("\"high\""))
}

// --- recursive data ------------------------------------------------------------

/// 1.x expressed this type with `self_decoder`. Codecs describe finite shapes
/// only, so read recursive data from a bounded `Value` with your own function.
pub type Category {
  Category(name: String, children: List(Category))
}

pub fn parse_category(text: String) -> Result(Category, Nil) {
  value.parse(text, value.default_limits())
  |> result.replace_error(Nil)
  |> result.try(category_from_value)
}

fn category_from_value(raw: Value) -> Result(Category, Nil) {
  case raw {
    value.Object(members) -> {
      use name <- result.try(case list.key_find(members, "name") {
        Ok(value.String(name)) -> Ok(name)
        _ -> Error(Nil)
      })
      use children <- result.try(case list.key_find(members, "children") {
        Ok(value.Array(items)) -> list.try_map(items, category_from_value)
        _ -> Error(Nil)
      })
      Ok(Category(name:, children:))
    }
    _ -> Error(Nil)
  }
}

pub fn recursive_data_reads_from_a_bounded_value_test() {
  parse_category(
    "{\"name\":\"root\",\"children\":[{\"name\":\"leaf\",\"children\":[]}]}",
  )
  |> should.equal(Ok(Category("root", [Category("leaf", [])])))
}

pub fn recursive_data_nested_beyond_the_default_depth_is_refused_test() {
  // Each level is an object and an array: 65 levels nest 130 deep.
  let deep =
    list.repeat(Nil, 65)
    |> list.fold("{\"name\":\"leaf\",\"children\":[]}", fn(inner, _) {
      "{\"name\":\"node\",\"children\":[" <> inner <> "]}"
    })
  parse_category(deep) |> should.equal(Error(Nil))
  let assert Error(error) = value.parse(deep, value.default_limits())
  value.is_limit_exceeded(error) |> should.be_true
}
