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

## Examples

<details>
  <summary>Encoding Union Types</summary>
  
Here's an example of encoding a union type to JSON:

```gleam
import gleam/io
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
  |> io.println
}
```

#### Generated JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "anyOf": [
    {
      "required": ["type", "data"],
      "additionalProperties": false,
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
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
          "type": "string",
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
          "type": "string",
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

</details>

<details>
  <summary>Type aliases and optional fields</summary>
  
And here's an example using type aliases, optional fields, and single constructor types:

```gleam
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import json/blueprint

pub fn main() {
  gleeunit.main()
}

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

  blueprint.generate_json_schema(drawing_decoder())
  |> json.to_string
  |> io.println
}

```

#### Generated JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "required": ["type", "data"],
  "additionalProperties": false,
  "type": "object",
  "properties": {
    "type": {
      "type": "string",
      "enum": ["box"]
    },
    "data": {
      "required": ["width", "height", "position"],
      "additionalProperties": false,
      "type": "object",
      "properties": {
        "width": {
          "type": "number"
        },
        "height": {
          "type": "number"
        },
        "position": {
          "maxItems": 2,
          "minItems": 2,
          "prefixItems": [
            {
              "type": "number"
            },
            {
              "type": "number"
            }
          ],
          "type": "array"
        },
        "color": {
          "required": ["enum"],
          "additionalProperties": false,
          "type": "object",
          "properties": {
            "enum": {
              "type": "string",
              "enum": ["red", "green", "blue"]
            }
          }
        }
      }
    }
  }
}
```

</details>

<details>
  <summary>Recursive data types</summary>
  
And here's an example using type aliases, optional fields, and single constructor types:

```gleam
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import json/blueprint

pub fn main() {
  gleeunit.main()
}

type Tree {
  Node(value: Int, left: Option(Tree), right: Option(Tree))
}

type ListOfTrees(t) {
  ListOfTrees(head: t, tail: ListOfTrees(t))
  NoTrees
}

fn encode_tree(tree: Tree) -> json.Json {
  blueprint.union_type_encoder(tree, fn(node) {
    case node {
      Node(value, left, right) -> #(
        "node",
        [
          #("value", json.int(value)),
          #("right", json.nullable(right, encode_tree)),
        ]
          |> blueprint.encode_optional_field("left", left, encode_tree)
          |> json.object(),
      )
    }
  })
}

fn encode_list_of_trees(tree: ListOfTrees(Tree)) -> json.Json {
  blueprint.union_type_encoder(tree, fn(list) {
    case list {
      ListOfTrees(head, tail) -> #(
        "list",
        json.object([
          #("head", encode_tree(head)),
          #("tail", encode_list_of_trees(tail)),
        ]),
      )
      NoTrees -> #("no_trees", json.object([]))
    }
  })
}

// Without reuse_decoder, recursive types would cause infinite schema expansion
fn tree_decoder() {
  blueprint.union_type_decoder([
    #(
      "node",
      blueprint.decode3(
        Node,
        blueprint.field("value", blueprint.int()),
        // testing both an optional field a field with a possible null
        blueprint.optional_field("left", blueprint.self_decoder(tree_decoder)),
        blueprint.field(
          "right",
          blueprint.optional(blueprint.self_decoder(tree_decoder)),
        ),
      ),
    ),
  ])
  // !!!IMPORTANT!!! Add the reuse_decoder when there are nested recursive types so
  // the schema references (`#`) get rewritten correctly and self-references from the
  // different types don't get mixed up. As a recommendation, always add it when
  // decoding recursive types.
  |> blueprint.reuse_decoder
}

fn decode_list_of_trees() {
  blueprint.union_type_decoder([
    #(
      "list",
      blueprint.decode2(
        ListOfTrees,
        blueprint.field("head", tree_decoder()),
        blueprint.field("tail", blueprint.self_decoder(decode_list_of_trees)),
      ),
    ),
    #("no_trees", blueprint.decode0(NoTrees)),
  ])
}

pub fn tree_decoder_test() {
  // Create a sample tree structure:
  //       5
  //      / \
  //     3   7
  //    /     \
  //   1       9
  let tree =
    Node(
      value: 5,
      left: Some(Node(value: 3, left: Some(Node(1, None, None)), right: None)),
      right: Some(Node(value: 7, left: None, right: Some(Node(9, None, None)))),
    )

  // Create a list of trees
  let tree_list =
    ListOfTrees(
      Node(value: 1, left: None, right: None),
      ListOfTrees(
        Node(
          value: 10,
          left: Some(Node(value: 1, left: None, right: None)),
          right: None,
        ),
        NoTrees,
      ),
    )

  // Test encoding
  let json_str = tree |> encode_tree |> json.to_string()
  let list_json_str = tree_list |> encode_list_of_trees |> json.to_string()

  // Test decoding
  let decoded = blueprint.decode(using: tree_decoder(), from: json_str)

  decoded
  |> should.equal(Ok(tree))

  let decoded_list =
    blueprint.decode(using: decode_list_of_trees(), from: list_json_str)

  decoded_list
  |> should.equal(Ok(tree_list))

  // Test schema generation
  blueprint.generate_json_schema(decode_list_of_trees())
  |> json.to_string
  |> io.println
}
```

#### Generated JSON Schema

```json
{
  "$defs": {
    "ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2": {
      "required": ["type", "data"],
      "additionalProperties": false,
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "enum": ["node"]
        },
        "data": {
          "required": ["value", "right"],
          "additionalProperties": false,
          "type": "object",
          "properties": {
            "value": {
              "type": "integer"
            },
            "left": {
              "$ref": "#/$defs/ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2"
            },
            "right": {
              "anyOf": [
                {
                  "$ref": "#/$defs/ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2"
                },
                {
                  "type": "null"
                }
              ]
            }
          }
        }
      }
    }
  },
  "$schema": "http://json-schema.org/draft-07/schema#",
  "anyOf": [
    {
      "required": ["type", "data"],
      "additionalProperties": false,
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "enum": ["list"]
        },
        "data": {
          "required": ["head", "tail"],
          "additionalProperties": false,
          "type": "object",
          "properties": {
            "head": {
              "$ref": "#/$defs/ref_CEF475B4CA96DC7B2C0C206AC7598AFFC4B66FD2"
            },
            "tail": {
              "$ref": "#"
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
          "type": "string",
          "enum": ["no_trees"]
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

</details>

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
