# json_blueprint

json_blueprint is a Gleam library that simplifies JSON encoding and decoding while automatically generating JSON schemas for your data types.

[![Package Version](https://img.shields.io/hexpm/v/json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/json_blueprint/)

```sh
gleam add json_blueprint
```

## Schema-Aware Core (Release-Ready Initial Facade)

`json_blueprint` provides a production-grade, schema-aware JSON core for Gleam applications:
- **`Value`**: Explicit, JSON-exact value model (`Null`, `Bool`, `String`, `Number`, `Array`, `Object`) with duplicate key preservation until rejection.
- **Exact `Number`**: Canonical arbitrary-precision decimal representation representing all numeric values. Native `Int` and `Float` are checked projections.
- **`Codec(a)`**: Bidirectional typed combinator deriving encoder, decoder, and Draft 2020-12 schema from a single definition.
- **`RuntimeContract`**: Validated schema contract for runtime schema matching and value validation.
- **`Document`**: Finite Draft 2020-12 schema document loader from parsed values or raw bytes.
- **`Parser`**: Bounded whole-document byte admission parser enforcing byte size, depth, number token, significand, and exponent limits, with duplicate key rejection and structured location errors.
- **`Migration`**: Explicit adapter bridging legacy 1.7.1 decoders into modern `Codec(a)` contracts while preserving wire envelopes and reporting unavailable schema.

### Target Support Matrix

| Target | Status | Exact Number Model | Native Integer Bounds | Binary64 Float Projections | Exercised Environment |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **BEAM / Erlang** | Full Support | Arbitrary-precision decimal | Unlimited (bignum) | Exact binary64 conversions | OTP 28 (all 95 tests pass) |
| **JavaScript (Node.js)** | Full Support | Arbitrary-precision decimal | `[-9007199254740991, 9007199254740991]` (typed `UnsafeNativeInteger` construction refusal / `UnsupportedNativeInteger` projection refusal) | Exact binary64 conversions via BigInt | Node.js v24.15 (all 95 tests pass) |
| **JavaScript (Browser)** | Unverified | Target-neutral ESM (`TextEncoder`, `DataView`, `BigInt`), but unverified in test suite | Same as Node.js | Same as Node.js | Untested in CI |

### Supported Finite Draft 2020-12 Profile

- **Closed Objects**: `ObjectSchema(properties)` with explicit required and optional fields.
- **Exact Pairs**: `PairSchema(left, right)` representing fixed 2-element tuples.
- **Collections**: `ListSchema(element)` representing homogenous arrays.
- **Nullable Values**: `NullableSchema(inner)` representing optional/nullable values.
- **Bounded Integers**: `IntegerRangeSchema(min, max)` enforcing integer bounds.
- **String Enums**: `StringEnumSchema(labels)` representing finite string variants.
- **Tagged Alternatives**: `TaggedSchema(tag1, s1, tag2, s2)` representing discriminated unions.

### Documented Design-Deferred Families (Retained Future Scope)

These capabilities are explicitly outside the initial release facade (per `PUBLIC-API.md`) rather than hidden behind incomplete todos:
- **Source Code Generation**: Experimental dev-time code generator paused for application naming research.
- **Recursive References (`$ref`, `$defs`)**: Deferred pending resource and cycle policies.
- **Arbitrary Unions**: Untagged unions (`anyOf`, general `oneOf`) deferred pending subtyping policy.
- **Pattern / Regex**: String format regex validation deferred.

### Schema-Aware Core Quickstart

A complete end-to-end example defining a bounded schema-aware codec, validating input bytes against Draft 2020-12 runtime contracts, and decoding into a typed domain record (tested verbatim in `test/readme_example_test.gleam`):

```gleam
pub type Task {
  Task(id: Int, title: String)
}

pub fn run_task_pipeline() -> Result(Task, String) {
  // 1. Build bidirectional codec with bounded integer range
  use id_codec <- result.try(
    codec.integer_between(1, 100_000)
    |> result.map_error(fn(_) { "Invalid id range" }),
  )
  use task_props <- result.try(
    codec.combine(
      codec.required("id", id_codec),
      codec.required("title", codec.string()),
    )
    |> result.map_error(fn(_) { "Invalid properties combination" }),
  )
  let task_codec =
    codec.imap(
      codec.object(task_props),
      fn(pair: #(Int, String)) { Task(pair.0, pair.1) },
      fn(task: Task) { #(task.id, task.title) },
    )

  // 2. Parse untrusted JSON bytes with bounded parser limits
  let limits = parser.default_limits()
  let input_bytes =
    bit_array.from_string("{\"id\": 42, \"title\": \"Verify Blueprint\"}")

  use parsed_val <- result.try(
    parser.parse_value(limits, input_bytes)
    |> result.map_error(fn(_) { "JSON parse error" }),
  )

  // 3. Derive Draft 2020-12 runtime contract and validate
  use schema <- result.try(
    codec.schema(task_codec)
    |> result.map_error(fn(_) { "Unknown schema" }),
  )
  use contract <- result.try(
    runtime.from_schema(schema)
    |> result.map_error(fn(_) { "Invalid schema contract" }),
  )
  use _validated <- result.try(
    runtime.validate(contract, parsed_val)
    |> result.map_error(fn(_) { "Schema validation failure" }),
  )

  // 4. Decode into typed domain record
  codec.decode(task_codec, parsed_val)
  |> result.map_error(fn(_) { "Decoding failure" })
}
```

### Legacy 1.7.1 Migration Contract

Existing 1.7.1 decoders (`json/blueprint.Decoder(a)`) can be adapted to modern `Codec(a)` using `json/blueprint/migration.adapt`. All errors (including safe native integer bounds) are handled honestly:

```gleam
pub type MyRecord {
  MyRecord(name: String, count: Int)
}

pub fn example() {
  let legacy_decoder =
    legacy.decode2(
      MyRecord,
      legacy.field("name", legacy.string()),
      legacy.field("count", legacy.int()),
    )

  let my_encoder = fn(record: MyRecord) {
    case number.from_int(record.count) {
      Error(_) ->
        Error(
          codec.CannotEncode(codec.CustomEncodeReason("Safe integer overflow")),
        )
      Ok(count_num) ->
        Ok(
          value.Object([
            #("name", value.String(record.name)),
            #("count", value.Number(count_num)),
          ]),
        )
    }
  }

  // Adapts legacy decoder with explicit encoder; reports codec.UnknownSchema
  let modern_codec = migration.adapt(legacy_decoder, my_encoder)
  modern_codec
}
```

---

## Legacy 1.7.1 Usage (Preserved for Compatibility)

json_blueprint preserves legacy utilities for encoding and decoding JSON data with union types under Draft 7:

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
