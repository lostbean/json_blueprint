//// The 1.x API, frozen: one-way `Decoder(t)` values that decode JSON text
//// into Gleam values and describe that JSON as a schema document labelled
//// Draft-07, plus encoders for unions, enums, optional fields and tuples.
////
//// Use `json/blueprint/codec` for new code: one `Codec(a)` encodes, decodes
//// strictly and describes a Draft 2020-12 schema. Keep this module for
//// recursive types, which `self_decoder` and `reuse_decoder` express with
//// `$ref` and `$defs`, and for existing 1.x code. Its wire formats differ from
//// `codec`: unions use `{"type", "data"}`, enums encode as `{"enum": label}`,
//// and objects ignore unknown fields. The schema types live in
//// `json/blueprint/schema`.
////
//// `decode` parses with `gleam/json` and rejects text above 1 MiB before
//// parsing; `decode_with_max_bytes` accepts another bound.
////
//// ```gleam
//// import gleam/json
//// import json/blueprint
////
//// pub type User {
////   User(name: String, age: Int)
//// }
////
//// pub fn user_decoder() -> blueprint.Decoder(User) {
////   blueprint.decode2(
////     User,
////     blueprint.field("name", blueprint.string()),
////     blueprint.field("age", blueprint.int()),
////   )
//// }
////
//// pub fn example() {
////   let assert Ok(User("Ada", 36)) =
////     blueprint.decode(
////       using: user_decoder(),
////       from: "{\"name\":\"Ada\",\"age\":36}",
////     )
////   blueprint.generate_json_schema(user_decoder()) |> json.to_string
//// }
//// ```

import gleam/bool
import gleam/dynamic as gleam_dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import json/blueprint/internal/dynamic
import json/blueprint/internal/text
import json/blueprint/schema.{type SchemaDefinition, Type} as jsch

type DynamicDecoder(t) =
  fn(gleam_dynamic.Dynamic) -> Result(t, List(dynamic.DecodeError))

pub opaque type Decoder(t) {
  Decoder(
    dyn_decoder: DynamicDecoder(t),
    schema: SchemaDefinition,
    defs: List(#(String, SchemaDefinition)),
  )
}

pub opaque type FieldDecoder(t) {
  FieldDecoder(
    dyn_decoder: DynamicDecoder(t),
    field_schema: #(String, SchemaDefinition),
    defs: List(#(String, SchemaDefinition)),
  )
}

pub type LazyDecoder(t) =
  fn() -> Decoder(t)

pub fn generate_json_schema(decoder: Decoder(t)) -> json.Json {
  let refs = case decoder.defs {
    [] -> None
    xs -> Some(xs)
  }
  jsch.to_json(jsch.new_schema(decoder.schema, refs))
}

/// Put the decoder's schema in `$defs` and return a decoder whose schema
/// points to it with `$ref`. The name derives from the rendered schema's
/// SHA-1 hash; it is a deterministic definition key, not a collision guarantee.
///
/// ## Example
/// ```gleam
/// type Person {
///   Person(name: String, friends: List(Pet))
/// }
///
/// type Pet {
///   Pet(name: String)
/// }
///
///
/// let pet_decoder = reuse_decoder(
///   decode2(
///     Pet,
///     field("name", string()),
///   )
/// )
///
/// let person_decoder = reuse_decoder(
///   decode2(
///     Person,
///     field("name", string()),
///     field("friends", list(pet_decoder))
///   )
/// )
/// ```
///
pub fn reuse_decoder(decoder: Decoder(t)) -> Decoder(t) {
  // Rebase root self-references to this definition before nesting it.
  let def_name = "ref_" <> jsch.hash_schema_definition(decoder.schema)
  let ref_name = "#/$defs/" <> def_name

  let schema_with_rebased_self_refs =
    jsch.map_ref(decoder.schema, fn(original_ref_name) {
      case original_ref_name {
        "#" -> ref_name
        x -> x
      }
    })
  Decoder(
    decoder.dyn_decoder,
    jsch.Ref(ref_name),
    decoder.defs |> list.prepend(#(def_name, schema_with_rebased_self_refs)),
  )
}

/// Decode a recursive type through a function that returns its decoder.
/// The schema uses `$ref: "#"` for a root self-reference.
///
/// Wrap recursive decoders in `reuse_decoder`. Nested recursive types need
/// their root references rebased to distinct definitions.
///
/// ## Example
/// ```gleam
/// // A binary tree type that can contain itself
/// pub type Tree {
///   Node(value: Int, left: Option(Tree), right: Option(Tree))
///   Leaf(value: Int)
/// }
///
/// // Create a recursive decoder for the Tree type
/// pub fn tree_decoder() -> Decoder(Tree) {
///   // Use union_type_decoder for handling different variants
///   union_type_decoder([
///     #("leaf", decode1(Leaf, field("value", int()))),
///     #("node", decode3(
///       Node,
///       field("value", int()),
///       // Use self_decoder to handle recursive fields
///       field("left", optional(self_decoder(tree_decoder))),
///       field("right", optional(self_decoder(tree_decoder))),
///     )),
///   ])
///   |> reuse_decoder
/// }
/// ```
///
pub fn self_decoder(lazy: LazyDecoder(t)) -> Decoder(t) {
  Decoder(fn(input) { lazy().dyn_decoder(input) }, jsch.Ref("#"), [])
}

/// The decoder as a function over `Dynamic` data, for use with a parser
/// other than `decode`. Errors use `gleam/dynamic/decode.DecodeError`.
pub fn get_dynamic_decoder(
  decoder: Decoder(t),
) -> fn(gleam_dynamic.Dynamic) -> Result(t, List(decode.DecodeError)) {
  fn(data) {
    decoder.dyn_decoder(data)
    |> result.map_error(fn(errors) { list.map(errors, to_decode_error) })
  }
}

fn to_decode_error(error: dynamic.DecodeError) -> decode.DecodeError {
  decode.DecodeError(
    expected: error.expected,
    found: error.found,
    path: error.path,
  )
}

/// Parse JSON text with `gleam/json` and decode it with `decoder`.
///
/// Text above 1 MiB (1,048,576 bytes of UTF-8) is rejected before parsing
/// with `json.UnableToDecode`; its one error has an empty path, `expected`
/// names the limit and `found` is `"more than <limit> bytes"`. Use
/// `decode_with_max_bytes` to accept larger text.
pub fn decode(
  using decoder: Decoder(t),
  from json_string: String,
) -> Result(t, json.DecodeError) {
  decode_with_max_bytes(
    using: decoder,
    from: json_string,
    max_bytes: text.default_max_bytes,
  )
}

/// Like `decode`, but reject text above `max_bytes` bytes of UTF-8 instead of
/// the 1 MiB default. A `max_bytes` below 1 rejects every non-empty text.
pub fn decode_with_max_bytes(
  using decoder: Decoder(t),
  from json_string: String,
  max_bytes max_bytes: Int,
) -> Result(t, json.DecodeError) {
  use <- bool.guard(
    when: text.exceeds_byte_limit(json_string, max_bytes),
    return: Error(
      json.UnableToDecode([
        decode.DecodeError(
          expected: "JSON text of at most "
            <> int.to_string(max_bytes)
            <> " bytes",
          found: "more than " <> int.to_string(max_bytes) <> " bytes",
          path: [],
        ),
      ]),
    ),
  )
  // Parse to raw Dynamic so the legacy decoder retains its own acceptance
  // rules and error paths.
  use dyn <- result.try(json.parse(from: json_string, using: decode.dynamic))
  get_dynamic_decoder(decoder)(dyn)
  |> result.map_error(json.UnableToDecode)
}

pub fn string() -> Decoder(String) {
  Decoder(dynamic.string, Type(jsch.StringType), [])
}

pub fn int() -> Decoder(Int) {
  Decoder(dynamic.int, Type(jsch.IntegerType), [])
}

pub fn float() -> Decoder(Float) {
  Decoder(dynamic.float, Type(jsch.NumberType), [])
}

pub fn bool() -> Decoder(Bool) {
  Decoder(dynamic.bool, Type(jsch.BooleanType), [])
}

pub fn list(of decoder_type: Decoder(inner)) -> Decoder(List(inner)) {
  Decoder(
    dynamic.list(decoder_type.dyn_decoder),
    jsch.Array(Some(decoder_type.schema)),
    decoder_type.defs,
  )
}

pub fn field(named name: String, of inner_type: Decoder(t)) -> FieldDecoder(t) {
  FieldDecoder(
    dynamic.field(name, inner_type.dyn_decoder),
    #(name, inner_type.schema),
    inner_type.defs,
  )
}

/// Decode `null` as `None` and another value with the inner decoder as
/// `Some`. A missing field still fails; use `optional_field` for absence.
///
/// ## Example
/// ```gleam
/// type User {
///   User(name: String, age: Option(Int))
/// }
///
/// let decoder = decode2(
///   User,
///   field("name", string()),
///   field("age", optional(int()))  // Will handle "age": null
/// )
///
/// // These JSON strings will decode successfully:
/// // {"name": "Alice", "age": 25}  -> User("Alice", Some(25))
/// // {"name": "Bob", "age": null}  -> User("Bob", None)
/// ```
///
pub fn optional(of decode: Decoder(inner)) -> Decoder(Option(inner)) {
  Decoder(
    dynamic.optional(decode.dyn_decoder),
    jsch.Nullable(decode.schema),
    decode.defs,
  )
}

@external(erlang, "json_blueprint_ffi", "null")
@external(javascript, "../json_blueprint_ffi.mjs", "do_null")
fn native_null() -> gleam_dynamic.Dynamic

/// Decode an absent or `null` field as `None`, and a present value with
/// the inner decoder as `Some`. Use `field` with `optional` when the field
/// must be present but may be `null`.
///
/// ## Example
/// ```gleam
/// type User {
///   User(name: String, age: Option(Int))
/// }
///
/// let decoder = decode2(
///   User,
///   field("name", string()),
///   optional_field("age", int())  // Will handle both missing "age" field and "age": null
/// )
///
/// // All these JSON strings will decode successfully:
/// // {"name": "Alice", "age": 25}     -> User("Alice", Some(25))
/// // {"name": "Bob", "age": null}     -> User("Bob", None)
/// // {"name": "Charlie"}              -> User("Charlie", None)
/// ```
///
pub fn optional_field(
  named name: String,
  of inner_type: Decoder(t),
) -> FieldDecoder(Option(t)) {
  FieldDecoder(
    fn(value) {
      dynamic.optional_field(name, fn(dyn) {
        case dyn == native_null() {
          False -> result.map(inner_type.dyn_decoder(dyn), Some)
          True -> Ok(None)
        }
      })(value)
      |> result.map(option.flatten)
    },
    #(name, jsch.Optional(inner_type.schema)),
    inner_type.defs,
  )
}

/// Prepend an encoded field for `Some`, or omit it for `None`.
/// Pair this encoder with `optional_field` when absence represents `None`.
///
/// ## Example
/// ```gleam
/// fn tree_decoder() {
///   blueprint.union_type_decoder([
///     #(
///       "node",
///       blueprint.decode3(
///         Node,
///         blueprint.field("value", blueprint.int()),
///         // This is an optional field for an optional value
///         blueprint.optional_field("left", blueprint.self_decoder(tree_decoder)),
///         // And this is a required field with an optional value
///         blueprint.field(
///           "right",
///           blueprint.optional(blueprint.self_decoder(tree_decoder)),
///         ),
///       ),
///     ),
///   ])
///   |> blueprint.reuse_decoder
/// }
///
/// fn encode_tree(tree: Tree) -> json.Json {
///   blueprint.union_type_encoder(tree, fn(node) {
///     case node {
///       Node(value, left, right) -> #(
///         "node",
///         [
///           #("value", json.int(value)),
///           // This is a required field with an optional value
///           #("right", json.nullable(right, encode_tree)),
///         ]
///           // And this is an optional field for an optional value
///           |> blueprint.encode_optional_field("left", left, encode_tree)
///           |> json.object(),
///       )
///     }
///   })
/// }
/// ```
pub fn encode_optional_field(
  fields fields: List(#(String, json.Json)),
  name name: String,
  maybe value: Option(t),
  encoder encode_fn: fn(t) -> json.Json,
) -> List(#(String, json.Json)) {
  case value {
    Some(left) -> list.prepend(fields, #(name, encode_fn(left)))
    None -> fields
  }
}

/// Encode a union as an object with `type` and `data` fields. The callback
/// returns the variant label and its encoded payload.
/// Keep the labels and payloads aligned with `union_type_decoder`.
///
/// ## Example
/// ```gleam
/// type Shape {
///   Circle(Float)
///   Rectangle(Float, Float)
/// }
///
/// let shape_encoder = union_type_encoder(fn(shape) {
///   case shape {
///     Circle(radius) -> #("circle", json.object([#("radius", json.float(radius))]))
///     Rectangle(width, height) -> #(
///       "rectangle",
///       json.object([
///         #("width", json.float(width)),
///         #("height", json.float(height))
///       ])
///     )
///   }
/// })
/// ```
///
///
pub fn union_type_encoder(
  value of: a,
  encoder_fn encoder_fn: fn(a) -> #(String, json.Json),
) -> json.Json {
  let #(field_name, json_value) = encoder_fn(of)
  json.object([#("type", json.string(field_name)), #("data", json_value)])
}

/// Decode a `type`/`data` union using the payload decoder for its label.
/// Test every variant; the compiler cannot check that this list is exhaustive.
///
/// ## Example
/// ```gleam
/// type Shape {
///   Circle(Float)
///   Rectangle(Float, Float)
/// }
///
/// let shape_decoder = union_type_decoder([
///   #("circle", decode1(Circle, field("radius", float()))),
///   #("rectangle", decode2(Rectangle,
///     field("width", float()),
///     field("height", float())
///   ))
/// ])
/// ```
///
pub fn union_type_decoder(
  constructor_decoders decoders: List(#(String, Decoder(a))),
) -> Decoder(a) {
  let constructor = fn(type_str: String, data: gleam_dynamic.Dynamic) -> Result(
    a,
    List(dynamic.DecodeError),
  ) {
    decoders
    |> list.find_map(fn(dec) {
      case dec.0 == type_str {
        True -> {
          Ok({ dec.1 }.dyn_decoder(data))
        }
        _ -> Error([])
      }
    })
    |> result.map_error(fn(_) {
      let valid_types =
        decoders |> list.map(fn(dec) { dec.0 }) |> string.join(", ")

      [
        dynamic.DecodeError(
          expected: "valid constructor type, one of: " <> valid_types,
          found: type_str,
          path: [],
        ),
      ]
    })
    |> result.flatten
  }

  let enum_decoder = fn(data) {
    dynamic.decode2(
      constructor,
      dynamic.field("type", dynamic.string),
      dynamic.field("data", dynamic.dynamic),
    )(data)
    |> result.flatten
  }

  let schema = case decoders {
    [] -> jsch.Object([], Some(False), None)

    [#(name, dec)] ->
      jsch.Object(
        [
          #("type", jsch.Enum([json.string(name)], Some(jsch.StringType))),
          #("data", dec.schema),
        ],
        Some(False),
        Some(["type", "data"]),
      )

    xs ->
      list.map(xs, fn(field_dec) {
        let #(name, dec) = field_dec
        jsch.Object(
          [
            #("type", jsch.Enum([json.string(name)], Some(jsch.StringType))),
            #("data", dec.schema),
          ],
          Some(False),
          Some(["type", "data"]),
        )
      })
      |> jsch.AnyOf
  }

  let defs = list.flat_map(decoders, fn(dec) { { dec.1 }.defs })

  Decoder(enum_decoder, schema, defs)
}

/// Encode a constructor with no arguments as `{"enum": label}`.
/// The callback selects its label; keep labels aligned with `enum_type_decoder`.
///
/// ## Example
/// ```gleam
/// type Color {
///   Red
///   Green
///   Blue
/// }
///
/// let color_encoder = enum_type_encoder(fn(color) {
///   case color {
///     Red -> "red"
///     Green -> "green"
///     Blue -> "blue"
///   }
/// })
/// ```
///
pub fn enum_type_encoder(
  value of: a,
  encoder_fn encoder_fn: fn(a) -> String,
) -> json.Json {
  let field_name = encoder_fn(of)
  json.object([#("enum", json.string(field_name))])
}

/// Decode `{"enum": label}` using the listed label/value pairs.
/// Test every enum value; the compiler cannot check that this list is exhaustive.
///
/// ## Example
/// ```gleam
/// type Color {
///   Red
///   Green
///   Blue
/// }
///
/// let color_decoder = enum_type_decoder([
///   #("red", Red),
///   #("green", Green),
///   #("blue", Blue),
/// ])
/// ```
///
pub fn enum_type_decoder(
  constructor_decoders decoders: List(#(String, a)),
) -> Decoder(a) {
  let constructor = fn(type_str: String) -> Result(a, List(dynamic.DecodeError)) {
    decoders
    |> list.find_map(fn(dec) {
      case dec.0 == type_str {
        True -> {
          Ok(dec.1)
        }
        _ -> Error([])
      }
    })
    |> result.map_error(fn(_) {
      let valid_types =
        decoders |> list.map(fn(dec) { dec.0 }) |> string.join(", ")

      [
        dynamic.DecodeError(
          expected: "valid constructor type, one of: " <> valid_types,
          found: type_str,
          path: [],
        ),
      ]
    })
  }

  let enum_decoder = fn(data) {
    dynamic.decode1(constructor, dynamic.field("enum", dynamic.string))(data)
    |> result.flatten
  }

  Decoder(
    enum_decoder,
    list.map(decoders, fn(field_dec) { json.string(field_dec.0) })
      |> fn(enum_values) {
        [#("enum", jsch.Enum(enum_values, Some(jsch.StringType)))]
      }
      |> jsch.Object(Some(False), Some(["enum"])),
    [],
  )
}

pub fn map(decoder decoder: Decoder(a), over foo: fn(a) -> b) -> Decoder(b) {
  Decoder(
    fn(input) { result.map(decoder.dyn_decoder(input), foo) },
    decoder.schema,
    decoder.defs,
  )
}

pub fn tuple2(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
) -> Decoder(#(a, b)) {
  Decoder(
    dynamic.tuple2(decode1.dyn_decoder, decode2.dyn_decoder),
    jsch.DetailedArray(
      None,
      Some([decode1.schema, decode2.schema]),
      Some(2),
      Some(2),
      None,
      None,
      None,
      None,
    ),
    list.append(decode1.defs, decode2.defs),
  )
}

pub fn tuple3(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
) -> Decoder(#(a, b, c)) {
  Decoder(
    dynamic.tuple3(
      decode1.dyn_decoder,
      decode2.dyn_decoder,
      decode3.dyn_decoder,
    ),
    jsch.DetailedArray(
      None,
      Some([decode1.schema, decode2.schema, decode3.schema]),
      Some(3),
      Some(3),
      None,
      None,
      None,
      None,
    ),
    list.flatten([decode1.defs, decode2.defs, decode3.defs]),
  )
}

pub fn tuple4(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
  fourth decode4: Decoder(d),
) -> Decoder(#(a, b, c, d)) {
  Decoder(
    dynamic.tuple4(
      decode1.dyn_decoder,
      decode2.dyn_decoder,
      decode3.dyn_decoder,
      decode4.dyn_decoder,
    ),
    jsch.DetailedArray(
      None,
      Some([decode1.schema, decode2.schema, decode3.schema, decode4.schema]),
      Some(4),
      Some(4),
      None,
      None,
      None,
      None,
    ),
    list.flatten([decode1.defs, decode2.defs, decode3.defs, decode4.defs]),
  )
}

pub fn tuple5(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
  fourth decode4: Decoder(d),
  fifth decode5: Decoder(e),
) -> Decoder(#(a, b, c, d, e)) {
  Decoder(
    dynamic.tuple5(
      decode1.dyn_decoder,
      decode2.dyn_decoder,
      decode3.dyn_decoder,
      decode4.dyn_decoder,
      decode5.dyn_decoder,
    ),
    jsch.DetailedArray(
      None,
      Some([
        decode1.schema,
        decode2.schema,
        decode3.schema,
        decode4.schema,
        decode5.schema,
      ]),
      Some(5),
      Some(5),
      None,
      None,
      None,
      None,
    ),
    list.flatten([
      decode1.defs,
      decode2.defs,
      decode3.defs,
      decode4.defs,
      decode5.defs,
    ]),
  )
}

pub fn tuple6(
  first decode1: Decoder(a),
  second decode2: Decoder(b),
  third decode3: Decoder(c),
  fourth decode4: Decoder(d),
  fifth decode5: Decoder(e),
  sixth decode6: Decoder(f),
) -> Decoder(#(a, b, c, d, e, f)) {
  Decoder(
    dynamic.tuple6(
      decode1.dyn_decoder,
      decode2.dyn_decoder,
      decode3.dyn_decoder,
      decode4.dyn_decoder,
      decode5.dyn_decoder,
      decode6.dyn_decoder,
    ),
    jsch.DetailedArray(
      None,
      Some([
        decode1.schema,
        decode2.schema,
        decode3.schema,
        decode4.schema,
        decode5.schema,
        decode6.schema,
      ]),
      Some(6),
      Some(6),
      None,
      None,
      None,
      None,
    ),
    list.flatten([
      decode1.defs,
      decode2.defs,
      decode3.defs,
      decode4.defs,
      decode5.defs,
      decode6.defs,
    ]),
  )
}

fn create_object_schema(
  fields: List(#(String, SchemaDefinition)),
) -> SchemaDefinition {
  jsch.Object(
    fields,
    Some(False),
    Some(
      list.filter_map(fields, fn(field_dec) {
        case field_dec {
          #(_, jsch.Optional(_)) -> Error(Nil)
          #(name, _) -> Ok(name)
        }
      }),
    ),
  )
}

/// Return the constructor for any input, including a non-object value.
/// The legacy schema describes an empty closed object, but this decoder
/// does not enforce that description.
pub fn decode0(constructor: t) -> Decoder(t) {
  Decoder(
    fn(_value) {
      // Keep permissive legacy acceptance for existing callers.
      Ok(constructor)
    },
    jsch.Object([], Some(False), None),
    [],
  )
}

pub fn decode1(constructor: fn(t1) -> t, t1: FieldDecoder(t1)) -> Decoder(t) {
  Decoder(
    dynamic.decode1(constructor, t1.dyn_decoder),
    create_object_schema([t1.field_schema]),
    t1.defs,
  )
}

pub fn decode2(
  constructor: fn(t1, t2) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
) -> Decoder(t) {
  Decoder(
    dynamic.decode2(constructor, t1.dyn_decoder, t2.dyn_decoder),
    create_object_schema([t1.field_schema, t2.field_schema]),
    list.flatten([t1.defs, t2.defs]),
  )
}

pub fn decode3(
  constructor: fn(t1, t2, t3) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
) -> Decoder(t) {
  Decoder(
    dynamic.decode3(constructor, t1.dyn_decoder, t2.dyn_decoder, t3.dyn_decoder),
    create_object_schema([t1.field_schema, t2.field_schema, t3.field_schema]),
    list.flatten([t1.defs, t2.defs, t3.defs]),
  )
}

pub fn decode4(
  constructor: fn(t1, t2, t3, t4) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
  t4: FieldDecoder(t4),
) -> Decoder(t) {
  Decoder(
    dynamic.decode4(
      constructor,
      t1.dyn_decoder,
      t2.dyn_decoder,
      t3.dyn_decoder,
      t4.dyn_decoder,
    ),
    create_object_schema([
      t1.field_schema,
      t2.field_schema,
      t3.field_schema,
      t4.field_schema,
    ]),
    list.flatten([t1.defs, t2.defs, t3.defs, t4.defs]),
  )
}

pub fn decode5(
  constructor: fn(t1, t2, t3, t4, t5) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
  t4: FieldDecoder(t4),
  t5: FieldDecoder(t5),
) -> Decoder(t) {
  Decoder(
    dynamic.decode5(
      constructor,
      t1.dyn_decoder,
      t2.dyn_decoder,
      t3.dyn_decoder,
      t4.dyn_decoder,
      t5.dyn_decoder,
    ),
    create_object_schema([
      t1.field_schema,
      t2.field_schema,
      t3.field_schema,
      t4.field_schema,
      t5.field_schema,
    ]),
    list.flatten([t1.defs, t2.defs, t3.defs, t4.defs, t5.defs]),
  )
}

pub fn decode6(
  constructor: fn(t1, t2, t3, t4, t5, t6) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
  t4: FieldDecoder(t4),
  t5: FieldDecoder(t5),
  t6: FieldDecoder(t6),
) -> Decoder(t) {
  Decoder(
    dynamic.decode6(
      constructor,
      t1.dyn_decoder,
      t2.dyn_decoder,
      t3.dyn_decoder,
      t4.dyn_decoder,
      t5.dyn_decoder,
      t6.dyn_decoder,
    ),
    create_object_schema([
      t1.field_schema,
      t2.field_schema,
      t3.field_schema,
      t4.field_schema,
      t5.field_schema,
      t6.field_schema,
    ]),
    list.flatten([t1.defs, t2.defs, t3.defs, t4.defs, t5.defs, t6.defs]),
  )
}

pub fn decode7(
  constructor: fn(t1, t2, t3, t4, t5, t6, t7) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
  t4: FieldDecoder(t4),
  t5: FieldDecoder(t5),
  t6: FieldDecoder(t6),
  t7: FieldDecoder(t7),
) -> Decoder(t) {
  Decoder(
    dynamic.decode7(
      constructor,
      t1.dyn_decoder,
      t2.dyn_decoder,
      t3.dyn_decoder,
      t4.dyn_decoder,
      t5.dyn_decoder,
      t6.dyn_decoder,
      t7.dyn_decoder,
    ),
    create_object_schema([
      t1.field_schema,
      t2.field_schema,
      t3.field_schema,
      t4.field_schema,
      t5.field_schema,
      t6.field_schema,
      t7.field_schema,
    ]),
    list.flatten([t1.defs, t2.defs, t3.defs, t4.defs, t5.defs, t6.defs, t7.defs]),
  )
}

pub fn decode8(
  constructor: fn(t1, t2, t3, t4, t5, t6, t7, t8) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
  t4: FieldDecoder(t4),
  t5: FieldDecoder(t5),
  t6: FieldDecoder(t6),
  t7: FieldDecoder(t7),
  t8: FieldDecoder(t8),
) -> Decoder(t) {
  Decoder(
    dynamic.decode8(
      constructor,
      t1.dyn_decoder,
      t2.dyn_decoder,
      t3.dyn_decoder,
      t4.dyn_decoder,
      t5.dyn_decoder,
      t6.dyn_decoder,
      t7.dyn_decoder,
      t8.dyn_decoder,
    ),
    create_object_schema([
      t1.field_schema,
      t2.field_schema,
      t3.field_schema,
      t4.field_schema,
      t5.field_schema,
      t6.field_schema,
      t7.field_schema,
      t8.field_schema,
    ]),
    list.flatten([
      t1.defs,
      t2.defs,
      t3.defs,
      t4.defs,
      t5.defs,
      t6.defs,
      t7.defs,
      t8.defs,
    ]),
  )
}

pub fn decode9(
  constructor: fn(t1, t2, t3, t4, t5, t6, t7, t8, t9) -> t,
  t1: FieldDecoder(t1),
  t2: FieldDecoder(t2),
  t3: FieldDecoder(t3),
  t4: FieldDecoder(t4),
  t5: FieldDecoder(t5),
  t6: FieldDecoder(t6),
  t7: FieldDecoder(t7),
  t8: FieldDecoder(t8),
  t9: FieldDecoder(t9),
) -> Decoder(t) {
  Decoder(
    dynamic.decode9(
      constructor,
      t1.dyn_decoder,
      t2.dyn_decoder,
      t3.dyn_decoder,
      t4.dyn_decoder,
      t5.dyn_decoder,
      t6.dyn_decoder,
      t7.dyn_decoder,
      t8.dyn_decoder,
      t9.dyn_decoder,
    ),
    create_object_schema([
      t1.field_schema,
      t2.field_schema,
      t3.field_schema,
      t4.field_schema,
      t5.field_schema,
      t6.field_schema,
      t7.field_schema,
      t8.field_schema,
      t9.field_schema,
    ]),
    list.flatten([
      t1.defs,
      t2.defs,
      t3.defs,
      t4.defs,
      t5.defs,
      t6.defs,
      t7.defs,
      t8.defs,
      t9.defs,
    ]),
  )
}

pub fn encode_tuple2(
  tuple tuple: #(a, b),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
) -> json.Json {
  let #(t1, t2) = tuple
  json.preprocessed_array([encode1(t1), encode2(t2)])
}

pub fn encode_tuple3(
  tuple tuple: #(a, b, c),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
  third encode3: fn(c) -> json.Json,
) -> json.Json {
  let #(t1, t2, t3) = tuple
  json.preprocessed_array([encode1(t1), encode2(t2), encode3(t3)])
}

pub fn encode_tuple4(
  tuple tuple: #(a, b, c, d),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
  third encode3: fn(c) -> json.Json,
  fourth encode4: fn(d) -> json.Json,
) -> json.Json {
  let #(t1, t2, t3, t4) = tuple
  json.preprocessed_array([encode1(t1), encode2(t2), encode3(t3), encode4(t4)])
}

pub fn encode_tuple5(
  tuple tuple: #(a, b, c, d, e),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
  third encode3: fn(c) -> json.Json,
  fourth encode4: fn(d) -> json.Json,
  fifth encode5: fn(e) -> json.Json,
) -> json.Json {
  let #(t1, t2, t3, t4, t5) = tuple
  json.preprocessed_array([
    encode1(t1),
    encode2(t2),
    encode3(t3),
    encode4(t4),
    encode5(t5),
  ])
}

pub fn encode_tuple6(
  tuple tuple: #(a, b, c, d, e, f),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
  third encode3: fn(c) -> json.Json,
  fourth encode4: fn(d) -> json.Json,
  fifth encode5: fn(e) -> json.Json,
  sixth encode6: fn(f) -> json.Json,
) -> json.Json {
  let #(t1, t2, t3, t4, t5, t6) = tuple
  json.preprocessed_array([
    encode1(t1),
    encode2(t2),
    encode3(t3),
    encode4(t4),
    encode5(t5),
    encode6(t6),
  ])
}

pub fn encode_tuple7(
  tuple tuple: #(a, b, c, d, e, f, g),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
  third encode3: fn(c) -> json.Json,
  fourth encode4: fn(d) -> json.Json,
  fifth encode5: fn(e) -> json.Json,
  sixth encode6: fn(f) -> json.Json,
  seventh encode7: fn(g) -> json.Json,
) -> json.Json {
  let #(t1, t2, t3, t4, t5, t6, t7) = tuple
  json.preprocessed_array([
    encode1(t1),
    encode2(t2),
    encode3(t3),
    encode4(t4),
    encode5(t5),
    encode6(t6),
    encode7(t7),
  ])
}

pub fn encode_tuple8(
  tuple tuple: #(a, b, c, d, e, f, g, h),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
  third encode3: fn(c) -> json.Json,
  fourth encode4: fn(d) -> json.Json,
  fifth encode5: fn(e) -> json.Json,
  sixth encode6: fn(f) -> json.Json,
  seventh encode7: fn(g) -> json.Json,
  eighth encode8: fn(h) -> json.Json,
) -> json.Json {
  let #(t1, t2, t3, t4, t5, t6, t7, t8) = tuple
  json.preprocessed_array([
    encode1(t1),
    encode2(t2),
    encode3(t3),
    encode4(t4),
    encode5(t5),
    encode6(t6),
    encode7(t7),
    encode8(t8),
  ])
}

pub fn encode_tuple9(
  tuple tuple: #(a, b, c, d, e, f, g, h, i),
  first encode1: fn(a) -> json.Json,
  second encode2: fn(b) -> json.Json,
  third encode3: fn(c) -> json.Json,
  fourth encode4: fn(d) -> json.Json,
  fifth encode5: fn(e) -> json.Json,
  sixth encode6: fn(f) -> json.Json,
  seventh encode7: fn(g) -> json.Json,
  eighth encode8: fn(h) -> json.Json,
  ninth encode9: fn(i) -> json.Json,
) -> json.Json {
  let #(t1, t2, t3, t4, t5, t6, t7, t8, t9) = tuple
  json.preprocessed_array([
    encode1(t1),
    encode2(t2),
    encode3(t3),
    encode4(t4),
    encode5(t5),
    encode6(t6),
    encode7(t7),
    encode8(t8),
    encode9(t9),
  ])
}
