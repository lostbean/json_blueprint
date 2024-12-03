# json_blueprint

json_blueprint is a Gleam library that simplifies JSON encoding and decoding while automatically generating JSON schemas for your data types.

[![Package Version](https://img.shields.io/hexpm/v/json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/json_blueprint/)

```sh
gleam add json_blueprint
```

## Usage

json_blueprint provides utilities for encoding and decoding JSON data, with special support for union types. The generated JSON schemas can be used to validate incoming JSON data with the decoder. The JSON schema follows the [JSON Schema Draft 7](https://json-schema.org/) specification and can tested and validate on [JSON Schema Lint](https://jsonschemalint.com/#!/version/draft-07/markup/json).

> ❗️ _**IMPORTANT: Recursive data types**_
>
> Make to use the `self_decoder` when defining the decoder for recursive data types.

> ⚠️ _**WARNING: Do NOT use on cyclical data type definitions**_
>
> While the library supports recursive data types (types with self reference), it does not support cyclical data types (cyclical dependency between multiple data types). Cyclical data types will result in infinite loop during decoding or schema generation.

### Encoding Union Types

Here's an example of encoding a union type to JSON:

```gleam
import json/blueprint
import gleam/json
import gleam/io
import gleeunit/should

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

fn simple_test() {
  let decoder = shape_decoder()

  // Test encoding a Circle
  let circle = Circle(5.0)
  encode_shape(circle)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(circle))

  // Test encoding a Rectangle
  let rectangle = Rectangle(10.0, 20.0)
  encode_shape(rectangle)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(rectangle))

  // Test encoding a Void
  encode_shape(Void)
  |> json.to_string
  |> blueprint.decode(using: decoder)
  |> should.equal(Ok(Void))

  // Print JSON schema
  decoder
  |> blueprint.generate_json_schema()
  |> json.to_string
  |> io.println
}
```

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "oneOf": [
    {
      "required": ["type", "data"],
      "additionalProperties": false,
      "type": "object",
      "properties": {
        "type": {
          "enum": ["circle"]
        },
        "data": {
          "required": ["radius"],
          "additionalProperties": false,
          "type": "object",
          "properties": {
            "radius": {
              "type": "number"
            }
          }
        }
      }
    },
    {
      "required": ["type", "data"],
      "additionalProperties": false,
      "type": "object",
      "properties": {
        "type": {
          "enum": ["rectangle"]
        },
        "data": {
          "required": ["width", "height"],
          "additionalProperties": false,
          "type": "object",
          "properties": {
            "width": {
              "type": "number"
            },
            "height": {
              "type": "number"
            }
          }
        }
      }
    },
    {
      "required": ["type", "data"],
      "additionalProperties": false,
      "type": "object",
      "properties": {
        "type": {
          "enum": ["void"]
        },
        "data": {
          "additionalProperties": false,
          "type": "object",
          "properties": {}
        }
      }
    }
  ]
}
```

This will encode your union types into a standardized JSON format with `type` and `data` fields, making it easy to decode on the receiving end.

And here's an example using type aliases, optional fields, and single constructor types:

```gleam
type Color {
  Red
  Green
  Blue
}

type Coordinate =
  #(Float, Float)

type Drawing {
  Box(Float, Float, Coordinate, Option(Color))
}

fn color_decoder() {
  blueprint.enum_type_decoder([
    #("red", Red),
    #("green", Green),
    #("blue", Blue),
  ])
}

fn color_encoder(input) {
  blueprint.enum_type_encoder(input, fn(color) {
    case color {
      Red -> "red"
      Green -> "green"
      Blue -> "blue"
    }
  })
}

fn encode_coordinate(coord: Coordinate) -> json.Json {
  blueprint.encode_tuple2(coord, json.float, json.float)
}

fn coordinate_decoder() {
  blueprint.tuple2(blueprint.float(), blueprint.float())
}

fn encode_drawing(drawing: Drawing) -> json.Json {
  blueprint.union_type_encoder(drawing, fn(shape) {
    case shape {
      Box(width, height, position, color) -> #(
        "box",
        json.object([
          #("width", json.float(width)),
          #("height", json.float(height)),
          #("position", encode_coordinate(position)),
          #("color", json.nullable(color, color_encoder)),
        ]),
      )
    }
  })
}

fn drawing_decoder() -> blueprint.Decoder(Drawing) {
  blueprint.union_type_decoder([
    #(
      "box",
      blueprint.decode4(
        Box,
        blueprint.field("width", blueprint.float()),
        blueprint.field("height", blueprint.float()),
        blueprint.field("position", coordinate_decoder()),
        blueprint.optional_field("color", color_decoder()),
      ),
    ),
  ])
}

pub fn drawing_test() {
  // Test cases
  let box = Box(15.0, 25.0, #(30.0, 40.0), None)

  // Test encoding
  let encoded_box = encode_drawing(box)

  // Test decoding
  encoded_box
  |> json.to_string
  |> blueprint.decode(using: drawing_decoder())
  |> should.equal(Ok(box))
}
```

## Features

- 🎯 Type-safe JSON encoding and decoding
- 🔄 Support for union types with standardized encoding
- 📋 Automatic JSON schema generation
- ✨ Clean and intuitive API

Further documentation can be found at <https://hexdocs.pm/json_blueprint>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
