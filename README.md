# json_blueprint

json_blueprint is a Gleam library that simplifies JSON encoding and decoding while automatically generating JSON schemas for your data types.

[![Package Version](https://img.shields.io/hexpm/v/json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/json_blueprint/)

```sh
gleam add json_blueprint
```

## Schema-aware core (planned 2.0 facade)

`json_blueprint` provides a schema-aware JSON core for Gleam applications. These APIs are on the implementation branch and are planned for 2.0; the package manifest still identifies the published 1.7.1 release. See [unreleased changes](CHANGELOG.md) and the [migration guide](docs/migration-2.0.md).

- **`Value`**: Explicit, JSON-exact value model (`Null`, `Bool`, `String`, `Number`, `Array`, `Object`) with duplicate key preservation until rejection.
- **Exact `Number`**: Canonical arbitrary-precision decimal representation representing all numeric values. Native `Int` and `Float` are checked projections.
- **`Codec(a)`**: Bidirectional typed combinator deriving encoder, decoder, and Draft 2020-12 schema from a single definition.
- **`RuntimeContract`**: Validated schema contract for runtime schema matching and value validation.
- **`Document`**: Finite Draft 2020-12 schema document loader from parsed values or raw bytes.
- **`Parser`**: Bounded whole-document byte admission parser enforcing byte size, depth, number token, significand, and exponent limits, with duplicate key rejection and structured location errors.
- **Advanced `Decoder`**: The released one-way decoder remains available for recursive types and its existing `$ref`/`$defs` schema output, which the finite `Codec` schema does not represent.

### Target Support Matrix

| Target                   | Status       | Exact Number Model                                                                     | Native Integer Bounds                                                                                                                      | Binary64 Float Projections            | Exercised Environment        |
| :----------------------- | :----------- | :------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------ | :--------------------------- |
| **BEAM / Erlang**        | Full Support | Arbitrary-precision decimal                                                            | Unlimited (bignum)                                                                                                                         | Exact binary64 conversions            | Verified on OTP 28           |
| **JavaScript (Node.js)** | Full Support | Arbitrary-precision decimal                                                            | `[-9007199254740991, 9007199254740991]` (typed `UnsafeNativeInteger` construction refusal / `UnsupportedNativeInteger` projection refusal) | Exact binary64 conversions via BigInt | Verified on Node.js v24.19.0 |
| **JavaScript (Browser)** | Unverified   | Target-neutral ESM (`TextEncoder`, `DataView`, `BigInt`), but unverified in test suite | Same as Node.js                                                                                                                            | Same as Node.js                       | Untested in CI               |

The CI matrix exercises Gleam 1.17.0, OTP 28, and Node.js 24. The browser target is not exercised there.

### Supported finite Draft 2020-12 profile

- **Closed Objects**: `ObjectSchema(properties)` with explicit required and optional fields.
- **Exact Pairs**: `PairSchema(left, right)` representing fixed 2-element tuples.
- **Collections**: `ListSchema(element)` representing homogenous arrays.
- **Nullable Values**: `NullableSchema(inner)` accepts JSON `null` or an inner value. Object property presence is modeled separately with `codec.optional`.
- **Bounded Integers**: `IntegerRangeSchema(min, max)` enforcing integer bounds.
- **String Enums**: `StringEnumSchema(labels)` representing finite string variants.
- **Tagged Alternatives**: `TaggedSchema(tag1, s1, tag2, s2)` representing discriminated unions.

### Documented Design-Deferred Families (Retained Future Scope)

These capabilities are explicitly outside the initial release facade (per `PUBLIC-API.md`) rather than hidden behind incomplete todos:

- **Recursive References (`$ref`, `$defs`)**: Deferred pending resource and cycle policies.
- **Arbitrary Unions**: Untagged unions (`anyOf`, general `oneOf`) deferred pending subtyping policy.
- **Pattern / Regex**: String format regex validation deferred.

### Schema-Aware Core Quickstart

A complete example using one codec for a native record, JSON text, and a Draft 2020-12 schema document (tested verbatim in `test/readme_example_test.gleam`):

```gleam
pub type Task {
  Task(id: Int, title: String)
}

pub fn run_task_pipeline() -> Result(Task, String) {
  // One bidirectional codec defines the record's JSON and schema.
  use id_codec <- result.try(
    codec.integer_between(1, 100_000)
    |> result.map_error(fn(_) { "Invalid id range" }),
  )
  use task_codec <- result.try(
    codec.record2(
      codec.required("id", id_codec),
      codec.required("title", codec.string()),
      Task,
      fn(task) { task.id },
      fn(task) { task.title },
    )
    |> result.map_error(fn(_) { "Invalid record properties" }),
  )

  use task <- result.try(
    codec.decode_json(task_codec, "{\"id\":42,\"title\":\"Verify Blueprint\"}")
    |> result.map_error(fn(_) { "Invalid task JSON" }),
  )
  use _encoded <- result.try(
    codec.encode_json(task_codec, task)
    |> result.map_error(fn(_) { "Cannot encode task" }),
  )
  use _schema_json <- result.try(
    codec.schema_json(task_codec)
    |> result.map_error(fn(_) { "Unknown schema" }),
  )
  Ok(task)
}
```

`codec.record2` and `codec.record3` accept `required` or `optional` properties, a native constructor, and one accessor per property. They return `Result(Codec(a), PropertyError)` so duplicate names fail during construction. The underlying object stays closed and retains declaration order. `codec.Optional(a)` distinguishes a missing property from a present value; use `codec.nullable` separately when JSON `null` is allowed. `codec.optional_option` and `codegen.optional_option` use standard `gleam/option.Option(a)` for optional properties. With a nullable inner codec, `None`, `Some(codec.Null)`, and `Some(codec.NonNull(value))` remain distinct. For larger records, compose `Properties` with `codec.combine`, then map the tuple with `codec.imap`. Use `codec.try_imap` when either native conversion may fail; its callbacks return `codec.DecodeError` and `codec.EncodeError`, and the base wire schema is retained.

`codec.schema_json` renders the full Draft 2020-12 document from a known codec schema. A custom codec built without a schema returns `Error(codec.UnknownSchema)`. `codec.decode_json` always uses Blueprint's strict parser, including for generated and mapped codecs. It rejects duplicate keys and retains exact number tokens. `codec.decode_json_with_limits(codec, limits, source)` accepts a `parser.ParserLimits` value when the application needs a smaller byte, depth, or number bound. Start with `parser.default_limits()` and use `parser_limits.with_max_bytes`, `with_max_depth`, or `with_number_limits` to adjust one policy. The ordinary default allows exact finite-float decimal expansions, including subnormal values, while retaining finite resource limits.

Use `codec.describe(codec.string(), "City to look up")` as the inner codec of `codec.required("city", ...)` to describe that property in the exported schema. Describe the completed object codec to annotate its root. `codegen.describe` does the same for a generated definition. Descriptions do not change value admission. `codec.render_json_decode_error(error)` turns a `JsonDecodeError` into readable feedback such as `$["city"]: expected a string`; it omits actual input values and custom reason text. The error remains structured for callers that need to classify it, and callers decide whether to expose the rendered text externally.

For schema validation or runtime contract inspection, use the advanced `json/blueprint/parser` and `json/blueprint/runtime` modules with the same `Codec(a)`. The ordinary typed text path is `codec.decode_json` and `codec.encode_json`.

### Runtime and Build-Time Codecs

Define a codec once with `json/blueprint/codegen` combinators. The same typed `Definition(a)` is the input to the runtime codec and to generated encoder, decoder, and schema artifacts; keep the definition and its mappings as the single maintained source.

For example, `order_definition()` below is the application's canonical nested `Order` definition. The following compiled fixture uses `materialize_fixtures` as its application data module and `generated/order_codec` as its generated module. Replace both module names with the corresponding modules in your application:

```gleam
pub fn runtime_and_generated_order_example(
  order: materialize_fixtures.Order,
  json_text: String,
) {
  let definition = materialize_fixtures.order_definition()

  // Runtime construction: use when the application wants a dynamic codec.
  let runtime_codec = codegen.runtime(definition)

  // Generated module: construct once and use interchangeably as a Codec(Order).
  let generated_codec = generated_order_codec.order_codec()
  let _ = codec.encode_json(generated_codec, order)
  let _ = codec.decode_json(generated_codec, json_text)

  // Direct generated operations expose the same strict text admission.
  let _ = generated_order_codec.encode_order_json(order)
  let _ = generated_order_codec.decode_order_json(json_text)
  let _ = generated_order_codec.order_schema()
  let _ = codec.encode_json(runtime_codec, order)
  Nil
}
```

To generate at build time, call `codegen.compile("generated/order_codec", "order", order_definition())`. It returns a `GeneratedModule` containing the module path, Gleam source content, and a fingerprint. The application's build/generation task writes that content to `src/generated/order_codec.gleam`, then runs `gleam format src/generated/order_codec.gleam` before compiling the application. Check the generated module into source control and add a freshness test that recompiles the canonical definition and compares the result with the checked-in source; this catches stale output without maintaining the generated implementation by hand.

Generated text encoders use `gleam/json` for rendering. Ordinary generated decoders use Blueprint's strict parser. For the distinct performance and parser behavior of `gleam/json`, call the generated `decode_<name>_json_native` function or `codec.decode_json_native(generated_codec, source)` explicitly; the native parser may normalize number tokens and collapse duplicate keys. A definition containing arbitrary `number.Number` values is refused by `codegen.compile` with `NativeNumberUnsupported`, since native JSON cannot preserve Blueprint's exact arbitrary-precision number contract.

### Moving from 1.x decoders to Codec

For ordinary application records, replace the one-way `json/blueprint.Decoder(a)` definition with one `json/blueprint/codec.Codec(a)`. The codec supplies both directions and a known Draft 2020-12 schema. This example is compiled in `test/readme_example_test.gleam`:

```gleam
pub type MyRecord {
  MyRecord(name: String, count: Int)
}

pub fn example() -> codec.Codec(MyRecord) {
  let assert Ok(record_codec) =
    codec.record2(
      codec.required("name", codec.string()),
      codec.required("count", codec.int()),
      MyRecord,
      fn(record) { record.name },
      fn(record) { record.count },
    )
  record_codec
}
```

The released root `json/blueprint.Decoder` remains supported for recursive typed decoding and its existing `$ref`/`$defs` schema output. `Codec.Schema` has no recursive reference constructor, so a recursive decoder does not have an equivalent finite codec definition. See [the 2.0 migration guide](docs/migration-2.0.md) for API mappings, missing/null behavior, and the removed adapter.

---

## Advanced recursive Decoder and legacy schema output

The released decoder and schema modules remain available when recursive decoding or constraints beyond the finite codec schema are needed. Their renderer labels output as Draft-07 and currently uses `$defs`; consumers that need strict dialect interoperability should inspect the generated document. Prefer `Codec` for ordinary bidirectional application data.

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
