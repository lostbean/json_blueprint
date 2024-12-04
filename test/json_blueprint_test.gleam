import gleam/json
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import json/blueprint
import json/blueprint/schema as json_schema

pub fn main() {
  gleeunit.main()
}

fn get_schema_header() {
  #("$schema", json.string(json_schema.json_schema_version))
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
      #("type", json.string("array")),
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
  |> json.to_string
  |> should.equal(
    json.object([
      get_schema_header(),
      #(
        "required",
        json.preprocessed_array([json.string("name"), json.string("age")]),
      ),
      #("additionalProperties", json.bool(False)),
      #("type", json.string("object")),
      #(
        "properties",
        json.object([
          #("name", json.object([#("type", json.string("string"))])),
          #("age", json.object([#("type", json.string("integer"))])),
          #("email", json.object([#("type", json.string("string"))])),
        ]),
      ),
    ])
    |> json.to_string,
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

  let schema = json_schema.new_schema(email_schema, None)
  let json = json_schema.to_json(schema)

  json
  |> json.to_string
  |> should.equal(
    json.object([
      get_schema_header(),
      #("format", json.string("email")),
      #("maxLength", json.int(100)),
      #("minLength", json.int(5)),
      #("type", json.string("string")),
    ])
    |> json.to_string,
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

  let schema = json_schema.new_schema(number_schema, None)
  let json = json_schema.to_json(schema)

  json
  |> json.to_string
  |> should.equal(
    json.object([
      get_schema_header(),
      #("multipleOf", json.float(0.5)),
      #("maximum", json.float(100.0)),
      #("minimum", json.float(0.0)),
      #("type", json.string("number")),
    ])
    |> json.to_string,
  )
}

// Helper function to create a Person decoder
fn person_decoder() -> blueprint.Decoder(Person) {
  blueprint.decode3(
    Person,
    blueprint.field("name", blueprint.string()),
    blueprint.field("age", blueprint.int()),
    blueprint.field("email", blueprint.optional(blueprint.string())),
  )
}

// Helper function to create an Address decoder
fn address_decoder() -> blueprint.Decoder(Address) {
  blueprint.decode3(
    Address,
    blueprint.field("street", blueprint.string()),
    blueprint.field("city", blueprint.string()),
    blueprint.field("zip", blueprint.string()),
  )
}

// Test reuse_decoder with nested structures
pub fn reuse_decoder_test() {
  // Create a person decoder and reuse it
  let person_decoder = person_decoder()
  let reused_person_decoder = blueprint.reuse_decoder(person_decoder)

  // Create an address decoder
  let address_decoder = address_decoder()

  // Create a PersonWithAddress decoder using the reused person decoder
  let person_with_address_decoder =
    blueprint.decode2(
      PersonWithAddress,
      blueprint.field("person", reused_person_decoder),
      blueprint.field("address", address_decoder),
    )

  // Test JSON data
  let json_str =
    "{
    \"person\": {
      \"name\": \"John Doe\",
      \"age\": 30,
      \"email\": \"john@example.com\"
    },
    \"address\": {
      \"street\": \"123 Main St\",
      \"city\": \"Springfield\",
      \"zip\": \"12345\"
    }
  }"

  // Decode the JSON
  let result = blueprint.decode(person_with_address_decoder, json_str)

  // Assert the result
  result
  |> should.be_ok
  |> fn(person_with_address) {
    person_with_address.person.name
    |> should.equal("John Doe")
    person_with_address.person.age
    |> should.equal(30)
    person_with_address.person.email
    |> should.equal(Some("john@example.com"))
    person_with_address.address.street
    |> should.equal("123 Main St")
    person_with_address.address.city
    |> should.equal("Springfield")
    person_with_address.address.zip
    |> should.equal("12345")
  }

  // Test schema generation
  blueprint.generate_json_schema(person_with_address_decoder)
  |> json.to_string
  |> should.equal(
    "{\"$defs\":{\"ref_707AD0AE2AF80DF30FAB6C677D270B616C19AF94\":{\"required\":[\"name\",\"age\",\"email\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"age\":{\"type\":\"integer\"},\"email\":{\"type\":[\"string\",\"null\"]}}}},\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"required\":[\"person\",\"address\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"person\":{\"$ref\":\"#/$defs/ref_707AD0AE2AF80DF30FAB6C677D270B616C19AF94\"},\"address\":{\"required\":[\"street\",\"city\",\"zip\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"street\":{\"type\":\"string\"},\"city\":{\"type\":\"string\"},\"zip\":{\"type\":\"string\"}}}}}",
  )
}
