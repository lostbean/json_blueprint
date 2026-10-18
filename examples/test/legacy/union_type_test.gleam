import gleam/json
import gleeunit
import gleeunit/should
import json/blueprint

pub fn main() {
  gleeunit.main()
}

type Shape {
  Circle(Float)
  Rectangle(Float, Float)
  Void
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
      Void -> #("void", json.object([]))
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
    #("void", blueprint.decode0(Void)),
  ])
}

pub fn union_type_test() {
  let circle = Circle(5.0)
  let rectangle = Rectangle(10.0, 20.0)

  let decoder = shape_decoder()

  //test decoding
  encode_shape(circle)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(circle))

  encode_shape(rectangle)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(rectangle))

  encode_shape(Void)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(Void))

  blueprint.generate_json_schema(shape_decoder())
  |> json.to_string
}

pub fn constructor_type_decoder_test() {
  let circle_json = "{\"type\":\"circle\",\"data\":{\"radius\":5.0}}"
  let rectangle_json =
    "{\"type\":\"rectangle\",\"data\":{\"width\":10.0,\"height\":20.0}}"
  let void_json = "{\"type\":\"void\",\"data\":{}}"

  blueprint.decode(using: shape_decoder(), from: circle_json)
  |> should.equal(Ok(Circle(5.0)))

  blueprint.decode(using: shape_decoder(), from: rectangle_json)
  |> should.equal(Ok(Rectangle(10.0, 20.0)))

  blueprint.decode(using: shape_decoder(), from: void_json)
  |> should.equal(Ok(Void))

  let schema = blueprint.generate_json_schema(shape_decoder())

  let expected_schema_str =
    "{\"$schema\":\"http://json-schema.org/draft-07/schema#\",\"anyOf\":[{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"circle\"]},\"data\":{\"required\":[\"radius\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"radius\":{\"type\":\"number\"}}}}},{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"rectangle\"]},\"data\":{\"required\":[\"width\",\"height\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"width\":{\"type\":\"number\"},\"height\":{\"type\":\"number\"}}}}},{\"required\":[\"type\",\"data\"],\"additionalProperties\":false,\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"void\"]},\"data\":{\"additionalProperties\":false,\"type\":\"object\",\"properties\":{}}}}]}"

  schema
  |> json.to_string
  |> should.equal(expected_schema_str)
}
