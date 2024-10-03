import blueprint
import gleam/json
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import json_schema

pub fn main() {
  gleeunit.main()
}

fn get_schema_header() {
  #("$schema", json.string("https://json-schema.org/draft/2020-12/schema"))
}

// Test type for object decoding
pub type Person {
  Person(name: String, age: Int, email: Option(String))
}

// Test type for nested objects
pub type Address {
  Address(street: String, city: String, zip: String)
}

pub type PersonWithAddress {
  PersonWithAddress(person: Person, address: Address)
}

// Basic decoder tests
pub fn string_decoder_test() {
  let decoder = blueprint.string()
  let json = "\"hello\""

  blueprint.decode(using: decoder, from: json)
  |> should.equal(Ok("hello"))

  let schema = blueprint.generate_json_schema(decoder)
  schema
  |> should.equal(
    json.object([get_schema_header(), #("type", json.string("string"))]),
  )
}

pub fn int_decoder_test() {
  let decoder = blueprint.int()
  let json = "42"

  blueprint.decode(using: decoder, from: json)
  |> should.equal(Ok(42))

  let schema = blueprint.generate_json_schema(decoder)
  schema
  |> should.equal(
    json.object([get_schema_header(), #("type", json.string("integer"))]),
  )
}

pub fn float_decoder_test() {
  let decoder = blueprint.float()
  let json = "3.14"

  blueprint.decode(using: decoder, from: json)
  |> should.equal(Ok(3.14))

  let schema = blueprint.generate_json_schema(decoder)
  schema
  |> should.equal(
    json.object([get_schema_header(), #("type", json.string("number"))]),
  )
}

pub fn bool_decoder_test() {
  let decoder = blueprint.bool()
  let json = "true"

  blueprint.decode(using: decoder, from: json)
  |> should.equal(Ok(True))

  let schema = blueprint.generate_json_schema(decoder)
  schema
  |> should.equal(
    json.object([get_schema_header(), #("type", json.string("boolean"))]),
  )
}

// List decoder tests
pub fn list_decoder_test() {
  let decoder = blueprint.list(blueprint.int())
  let json = "[1, 2, 3]"

  blueprint.decode(using: decoder, from: json)
  |> should.equal(Ok([1, 2, 3]))

  let schema = blueprint.generate_json_schema(decoder)
  schema
  |> should.equal(
    json.object([
      get_schema_header(),
      #("items", json.object([#("type", json.string("integer"))])),
    ]),
  )
}

// Optional decoder tests
pub fn optional_decoder_test() {
  let decoder = blueprint.optional(blueprint.string())
  let json_some = "\"present\""
  let json_none = "null"

  blueprint.decode(using: decoder, from: json_some)
  |> should.equal(Ok(Some("present")))

  blueprint.decode(using: decoder, from: json_none)
  |> should.equal(Ok(None))
}

// Object decoder tests
pub fn person_decoder_test() {
  let person_decoder =
    blueprint.decode3(
      Person,
      blueprint.field("name", blueprint.string()),
      blueprint.field("age", blueprint.int()),
      blueprint.optional_field("email", blueprint.string()),
    )

  let json = "{\"name\":\"Alice\",\"age\":30,\"email\":\"alice@example.com\"}"

  let expected =
    Person(name: "Alice", age: 30, email: Some("alice@example.com"))

  blueprint.decode(using: person_decoder, from: json)
  |> should.equal(Ok(expected))

  // Test schema generation
  blueprint.generate_json_schema(person_decoder)
  |> should.equal(
    json.object([
      get_schema_header(),
      #(
        "properties",
        json.object([
          #("name", json.object([#("type", json.string("string"))])),
          #("age", json.object([#("type", json.string("integer"))])),
          #("email", json.object([#("type", json.string("string"))])),
        ]),
      ),
    ]),
  )
}

// Nested object decoder tests
pub fn nested_object_decoder_test() {
  let address_decoder =
    blueprint.decode3(
      Address,
      blueprint.field("street", blueprint.string()),
      blueprint.field("city", blueprint.string()),
      blueprint.field("zip", blueprint.string()),
    )

  let person_with_address_decoder =
    blueprint.decode2(
      PersonWithAddress,
      blueprint.field(
        "person",
        blueprint.decode3(
          Person,
          blueprint.field("name", blueprint.string()),
          blueprint.field("age", blueprint.int()),
          blueprint.optional_field("email", blueprint.string()),
        ),
      ),
      blueprint.field("address", address_decoder),
    )

  let json =
    "{\"person\":{\"name\":\"Bob\",\"age\":25},\"address\":{\"street\":\"123 Main St\",\"city\":\"Springfield\",\"zip\":\"12345\"}}"

  let expected =
    PersonWithAddress(
      person: Person(name: "Bob", age: 25, email: None),
      address: Address(street: "123 Main St", city: "Springfield", zip: "12345"),
    )

  blueprint.decode(using: person_with_address_decoder, from: json)
  |> should.equal(Ok(expected))
}

// Tuple decoder tests
pub fn tuple_decoder_test() {
  let tuple2_decoder = blueprint.tuple2(blueprint.string(), blueprint.int())
  let json = "[\"hello\",42]"

  blueprint.decode(using: tuple2_decoder, from: json)
  |> should.equal(Ok(#("hello", 42)))

  let tuple3_decoder =
    blueprint.tuple3(blueprint.string(), blueprint.int(), blueprint.bool())
  let json3 = "[\"hello\",42,true]"

  blueprint.decode(using: tuple3_decoder, from: json3)
  |> should.equal(Ok(#("hello", 42, True)))
}

// Error handling tests
pub fn decoder_error_test() {
  let decoder = blueprint.string()
  let invalid_json = "{"

  blueprint.decode(using: decoder, from: invalid_json)
  |> should.be_error

  let wrong_type_json = "42"
  blueprint.decode(using: decoder, from: wrong_type_json)
  |> should.be_error
}

// JSON Schema specific tests
pub fn json_schema_string_format_test() {
  let email_schema =
    json_schema.string_constraint(
      min_length: Some(5),
      max_length: Some(100),
      pattern: None,
      format: Some(json_schema.Email),
    )

  let schema = json_schema.new_schema(email_schema)
  let json = json_schema.to_json(schema)

  json
  |> should.equal(
    json.object([
      #("$schema", json.string("https://json-schema.org/draft/2020-12/schema")),
      #("minLength", json.int(5)),
      #("maxLength", json.int(100)),
      #("format", json.string("email")),
    ]),
  )
}

pub fn json_schema_number_constraint_test() {
  let number_schema =
    json_schema.number_constraint(
      minimum: Some(0.0),
      maximum: Some(100.0),
      exclusive_minimum: None,
      exclusive_maximum: None,
      multiple_of: Some(0.5),
    )

  let schema = json_schema.new_schema(number_schema)
  let json = json_schema.to_json(schema)

  json
  |> should.equal(
    json.object([
      #("$schema", json.string("https://json-schema.org/draft/2020-12/schema")),
      #("minimum", json.float(0.0)),
      #("maximum", json.float(100.0)),
      #("multipleOf", json.float(0.5)),
    ]),
  )
}
