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

  let schema = json_schema.new_schema(email_schema)
  let json = json_schema.to_json(schema)

  json
  |> json.to_string
  |> should.equal(
    json.object([
      get_schema_header(),
      #("format", json.string("email")),
      #("maxLength", json.int(100)),
      #("minLength", json.int(5)),
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

  let schema = json_schema.new_schema(number_schema)
  let json = json_schema.to_json(schema)

  json
  |> json.to_string
  |> should.equal(
    json.object([
      get_schema_header(),
      #("multipleOf", json.float(0.5)),
      #("maximum", json.float(100.0)),
      #("minimum", json.float(0.0)),
    ])
    |> json.to_string,
  )
}

type Shape {
  Circle(Float)
  Rectangle(Float, Float)
}

fn encode_shape(shape: Shape) -> json.Json {
  blueprint.union_type_encoder(shape, fn(shape_case) {
    case shape_case {
      Circle(radius) -> #(
        "circle",
        json.object([#("radius", json.float(radius))]),
      )
      Rectangle(width, height) -> #(
        "rectangle",
        json.object([
          #("width", json.float(width)),
          #("height", json.float(height)),
        ]),
      )
    }
  })
}

fn shape_decoder() -> blueprint.Decoder(Shape) {
  blueprint.union_type_decoder([
    #(
      "circle",
      blueprint.decode1(Circle, blueprint.field("radius", blueprint.float())),
    ),
    #(
      "rectangle",
      blueprint.decode2(
        Rectangle,
        blueprint.field("width", blueprint.float()),
        blueprint.field("height", blueprint.float()),
      ),
    ),
  ])
}

pub fn constructor_type_decoder_test() {
  let shape_decoder =
    blueprint.union_type_decoder([
      #(
        "circle",
        blueprint.decode1(Circle, blueprint.field("radius", blueprint.float())),
      ),
      #(
        "rectangle",
        blueprint.decode2(
          Rectangle,
          blueprint.field("width", blueprint.float()),
          blueprint.field("height", blueprint.float()),
        ),
      ),
    ])

  let circle_json = "{\"type\":\"circle\",\"data\":{\"radius\":5.0}}"
  let rectangle_json =
    "{\"type\":\"rectangle\",\"data\":{\"width\":10.0,\"height\":20.0}}"

  blueprint.decode(using: shape_decoder, from: circle_json)
  |> should.equal(Ok(Circle(5.0)))

  blueprint.decode(using: shape_decoder, from: rectangle_json)
  |> should.equal(Ok(Rectangle(10.0, 20.0)))

  let schema = blueprint.generate_json_schema(shape_decoder)

  let expected_schema_str =
    "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"oneOf\":[{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\"circle\"]},\"data\":{\"required\":[\"radius\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"radius\":{\"type\":\"number\"}}}}},{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"enum\":[\"rectangle\"]},\"data\":{\"required\":[\"width\",\"height\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"width\":{\"type\":\"number\"},\"height\":{\"type\":\"number\"}}}}}]}"

  schema
  |> json.to_string
  |> should.equal(expected_schema_str)
}

pub fn union_type_encoder_test() {
  // Test encoding a Circle
  let circle = Circle(5.0)
  // Test encoding a Rectangle
  let rectangle = Rectangle(10.0, 20.0)

  let decoder = shape_decoder()

  encode_shape(circle)
  |> should.equal(
    json.object([
      #("type", json.string("circle")),
      #("data", json.object([#("radius", json.float(5.0))])),
    ]),
  )

  encode_shape(rectangle)
  |> should.equal(
    json.object([
      #("type", json.string("rectangle")),
      #(
        "data",
        json.object([
          #("width", json.float(10.0)),
          #("height", json.float(20.0)),
        ]),
      ),
    ]),
  )

  //test decoding
  encode_shape(circle)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(circle))

  encode_shape(rectangle)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(rectangle))
}
