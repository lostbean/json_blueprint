//// Bidirectional JSON codecs: one `Codec(a)` encodes a Gleam value, decodes
//// JSON text, and describes the JSON as a Draft 2020-12 schema.
////
//// Describe a record once with `field`, `optional_field` and `success`, then
//// use it in both directions:
////
//// ```gleam
//// import gleam/option.{type Option}
//// import json/blueprint/codec.{type Codec}
////
//// pub type Role {
////   Admin
////   Member
//// }
////
//// pub type User {
////   User(name: String, age: Int, email: Option(String), role: Role)
//// }
////
//// pub fn user_codec() -> Codec(User) {
////   use name <- codec.field("name", codec.string(), get: fn(u) { u.name })
////   use age <- codec.field("age", codec.integer_between(0, 150), get: fn(u) {
////     u.age
////   })
////   use email <- codec.optional_field("email", codec.string(), get: fn(u) {
////     u.email
////   })
////   use role <- codec.field(
////     "role",
////     codec.string_enum([#("admin", Admin), #("member", Member)]),
////     get: fn(u) { u.role },
////   )
////   codec.success(User(name:, age:, email:, role:))
//// }
////
//// pub fn example() -> Result(String, String) {
////   let text = "{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}"
////   case codec.decode_json(user_codec(), text) {
////     Error(error) -> Error(codec.describe_decode_error(error))
////     Ok(user) -> {
////       let assert Ok(text) = codec.encode_json(user_codec(), user)
////       Ok(text)
////     }
////   }
//// }
//// ```
////
//// Each getter is passed with its `get:` label and needs no type
//// annotation: the rest of the `use` block, which ends in `success`, is
//// checked first and fixes the record type. The body after each `use` runs
//// with placeholder values when the codec describes itself, so keep it a
//// plain constructor call.
////
//// Sending a codec, or a value that holds one, to another BEAM process
//// copies it without sharing. Each combinator holds each of its inputs once,
//// so the copy costs about the codec's own size: a child codec or a large
//// value captured by a later field is copied once, and a run-time enum label
//// costs its own data once. Before 2.2.0 a continuation was copied once per
//// callback that held it; the codec practice guide,
//// `docs/CODEC-PRACTICE.md` in the repository, gives the rules for code that
//// must still run on 2.1.x.
////
//// Objects are closed: an unknown field fails to decode. `optional_field`
//// omits the field for `None`; wrap the inner codec in `nullable` to also
//// accept `null`. `union` with `variant` and `unit_variant` describes a sum
//// type as `{"tag": ..., "value": ...}`. `map` and `try_map` convert to your
//// own types, `custom` builds a codec from functions, and `value` passes any
//// JSON through as a `Value`. `placeholder` gives a generic wrapper the
//// value a codec describes itself with. A check across
//// fields reports its path when the dependent field's codec is built from
//// the fields before it; see `try_map`.
////
//// `decode_json` applies a 1 MiB byte bound and rejects duplicate keys.
//// `decode_json_with_limits` takes a different byte bound. Both targets decode
//// built-in codecs directly from the native parse tree; custom codecs and
//// `value()` materialize their requested `Value` subtree. JavaScript uses
//// JSON.parse with exact source retention and strict duplicate/Unicode checks.
//// Neither target applies a depth or value-count limit.
//// `to_json` and `decoder` bridge to `gleam/json` and
//// `gleam/dynamic/decode`.
////
//// A definition written wrongly, such as a field named twice or an enum label
//// repeated, panics with a message naming the field or label when the
//// mistaken part is first used: when it encodes or decodes a value, or when
//// `schema` describes the codec. `check` returns the same problem as a
//// `DefinitionError` instead, for codecs built from runtime data such as enum
//// labels loaded from a database; call it at startup.
////
//// `DecodeError` and `EncodeError` are `{path, reason}` records, rendered
//// by `describe_decode_error` and `describe_encode_error`: the library owns
//// the path, and a `Custom` reason renders the caller's message. `Reason`
//// may gain variants in minor releases; match it with a `_` branch, and
//// build errors with `decode_failure` and `encode_failure`.
////
//// `schema` returns an opaque `Schema`. `schema_value` and
//// `schema_document` render it as JSON Schema; code that translates a
//// schema, such as a provider adapter, reads it with `view`, which gives
//// the kind at the root, and `description`. `view` has a fixed set of
//// variants for 2.x, and a kind added later reaches it as
//// `OtherSchema(document)`, so a match like this one keeps compiling:
////
//// ```gleam
//// import gleam/list
////
//// /// Whether a provider that takes strings, integers, booleans, lists and
//// /// closed objects of them can take `schema`.
//// pub fn supported(schema: codec.Schema) -> Bool {
////   case codec.view(schema) {
////     codec.StringSchema
////     | codec.StringEnumSchema(_)
////     | codec.IntSchema
////     | codec.IntegerRangeSchema(_, _)
////     | codec.BoolSchema -> True
////     codec.ListSchema(items) -> supported(items)
////     codec.ObjectSchema(properties) ->
////       list.all(properties, fn(property) { supported(property.schema) })
////     codec.NumberSchema
////     | codec.NumberRangeSchema(_, _)
////     | codec.PairSchema(_, _)
////     | codec.NullableSchema(_)
////     | codec.UnionSchema(_)
////     | codec.AnySchema -> False
////     // A kind added in a later 2.x release: reject what is not known.
////     codec.OtherSchema(_) -> False
////   }
//// }
//// ```
////
//// A schema whose enum labels or descriptions are runtime data can be
//// published under other strings: `map_enum_labels` replaces the labels of
//// every string enumeration and fails when two labels of one enumeration
//// would become the same, and `map_descriptions` replaces every description.
//// Both return another checked `Schema` of the same structure and leave the
//// codec as it is.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string
import json/blueprint/internal/native
import json/blueprint/internal/schema_tree.{type Tree} as tree
import json/blueprint/number.{type Number}
import json/blueprint/value.{type Value}

// --- schema ------------------------------------------------------------------

/// The JSON Schema of a codec, within the finite Draft 2020-12 profile that
/// codecs describe. Get one with `schema`, render it with `schema_value` or
/// `schema_document`, and read its structure with `view` and `description`.
/// `map_enum_labels` and `map_descriptions` derive another schema of the same
/// structure.
///
/// It is opaque so that the schema model can grow without breaking callers;
/// see `SchemaView` for the evolution policy. Two schemas are `==` when they
/// have the same structure and descriptions; `contract.same_schema` ignores
/// descriptions and member order.
pub opaque type Schema {
  Schema(tree: Tree)
}

/// The kind of a schema at its root, for code that translates schemas, such
/// as a tool server normalising an input schema or an LLM client converting
/// one for a provider. Children are `Schema` values: call `view` on them to
/// walk the tree.
///
/// Evolution policy: these variants are fixed for every 2.x release. A schema
/// kind added in a minor release reaches `view` as `OtherSchema(document)`,
/// where `document` is that kind's JSON Schema object, as `schema_value`
/// renders it. A consumer written against 2.0 therefore keeps compiling and
/// decides in its `OtherSchema` branch whether to forward the document or
/// reject the schema. A dedicated variant for a new kind is a breaking change
/// and arrives only in a major release; until then a minor release may add a
/// function that reads it. No 2.0 schema produces `OtherSchema`.
///
/// Descriptions are annotations, not kinds: `view` looks through them and
/// `description` reads them, so a described string is still a
/// `StringSchema`.
pub type SchemaView {
  /// `string()`: `{"type": "string"}`.
  StringSchema
  /// `string_enum`: `{"type": "string", "enum": labels}`.
  StringEnumSchema(labels: List(String))
  /// `int()`: `{"type": "integer"}`.
  IntSchema
  /// `integer_between`: an integer with inclusive bounds.
  IntegerRangeSchema(minimum: Int, maximum: Int)
  /// `float()` and `number()`: `{"type": "number"}`.
  NumberSchema
  /// `number_between`: a number with inclusive bounds.
  NumberRangeSchema(minimum: Number, maximum: Number)
  /// `bool()`: `{"type": "boolean"}`.
  BoolSchema
  /// `pair`: an array of exactly two items.
  PairSchema(left: Schema, right: Schema)
  /// `list`: an array whose items all match `items`.
  ListSchema(items: Schema)
  /// `nullable`: `null` or `inner`.
  NullableSchema(inner: Schema)
  /// A record: a closed object.
  ObjectSchema(properties: List(PropertySchema))
  /// `union`: a closed `{"tag": ..., "value": ...}` object, one variant per
  /// tag.
  UnionSchema(variants: List(VariantSchema))
  /// `value()`: any JSON value, `{}` in a document.
  AnySchema
  /// A kind added after 2.0, as its JSON Schema object. See the evolution
  /// policy above.
  OtherSchema(document: Value)
}

/// One property of an `ObjectSchema`. May gain fields in a minor release;
/// read them by label.
pub type PropertySchema {
  PropertySchema(name: String, required: Bool, schema: Schema)
}

/// One variant of a `UnionSchema`. A unit variant has no payload. May gain
/// fields in a minor release; read them by label.
pub type VariantSchema {
  VariantSchema(tag: String, payload: Option(Schema))
}

/// The kind of `schema` at its root, after any description. Children are
/// `Schema` values; `view` them in turn. The module doc has an example.
pub fn view(schema: Schema) -> SchemaView {
  view_tree(schema.tree)
}

fn view_tree(node: Tree) -> SchemaView {
  case node {
    tree.DescribedSchema(_, inner) -> view_tree(inner)
    tree.StringSchema -> StringSchema
    tree.StringEnumSchema(labels) -> StringEnumSchema(labels)
    tree.IntSchema -> IntSchema
    tree.IntegerRangeSchema(minimum, maximum) ->
      IntegerRangeSchema(minimum, maximum)
    tree.NumberSchema -> NumberSchema
    tree.NumberRangeSchema(minimum, maximum) ->
      NumberRangeSchema(minimum, maximum)
    tree.BoolSchema -> BoolSchema
    tree.PairSchema(left, right) -> PairSchema(Schema(left), Schema(right))
    tree.ListSchema(items) -> ListSchema(Schema(items))
    tree.NullableSchema(inner) -> NullableSchema(Schema(inner))
    tree.ObjectSchema(properties) ->
      ObjectSchema(
        list.map(properties, fn(property) {
          PropertySchema(
            name: property.name,
            required: property.required,
            schema: Schema(property.schema),
          )
        }),
      )
    tree.UnionSchema(variants) ->
      UnionSchema(
        list.map(variants, fn(variant) {
          VariantSchema(
            tag: variant.tag,
            payload: option.map(variant.payload, Schema),
          )
        }),
      )
    tree.AnySchema -> AnySchema
  }
}

/// The description that `describe` gave `schema`, if any. The schema of a
/// field, an item or a payload has its own description.
pub fn description(schema: Schema) -> Option(String) {
  case schema.tree {
    tree.DescribedSchema(description, _) -> Some(description)
    _ -> None
  }
}

/// `schema` with every label of every string enumeration in it, at any depth,
/// replaced by `mapping(label)`. Nothing else changes: the structure, the
/// order of labels, bounds, property names, union tags and descriptions stay
/// as they are, so the result is what `string_enum` of the mapped labels
/// would describe in the same places.
///
/// Use it to publish a schema whose labels are runtime data under other
/// labels, such as stable stand-ins for generated identifiers. Only the
/// schema is mapped. The codec it came from still reads and writes its own
/// labels, and `contract.decode` refuses that codec for a value validated
/// against the mapped schema, so map the documents the same way.
///
/// Labels of one enumeration must stay distinct: when `mapping` gives two of
/// them the same string, the result is `Error(DuplicateEnumLabel(label))`
/// with the repeated mapped label. Enumerations are checked separately, so
/// two enumerations may share a label. The empty string is a valid label.
/// `mapping` is called once for each label of each enumeration.
pub fn map_enum_labels(
  schema: Schema,
  with mapping: fn(String) -> String,
) -> Result(Schema, DefinitionError) {
  let mapped = rewrite(schema.tree, mapping, fn(description) { description })
  use Nil <- result.map(validate_tree(mapped))
  Schema(mapped)
}

/// `schema` with every description in it, at any depth, replaced by
/// `mapping(description)`. Descriptions are annotations, so the result
/// accepts the same documents and `contract.same_schema` holds between the
/// two. A node without a description gains none.
pub fn map_descriptions(
  schema: Schema,
  with mapping: fn(String) -> String,
) -> Schema {
  Schema(rewrite(schema.tree, fn(label) { label }, mapping))
}

fn rewrite(
  node: Tree,
  label: fn(String) -> String,
  describe: fn(String) -> String,
) -> Tree {
  case node {
    tree.DescribedSchema(description, inner) ->
      tree.DescribedSchema(
        describe(description),
        rewrite(inner, label, describe),
      )
    tree.StringEnumSchema(labels) ->
      tree.StringEnumSchema(list.map(labels, label))
    tree.StringSchema
    | tree.IntSchema
    | tree.NumberSchema
    | tree.BoolSchema
    | tree.IntegerRangeSchema(_, _)
    | tree.NumberRangeSchema(_, _)
    | tree.AnySchema -> node
    tree.PairSchema(left, right) ->
      tree.PairSchema(
        rewrite(left, label, describe),
        rewrite(right, label, describe),
      )
    tree.ListSchema(items) -> tree.ListSchema(rewrite(items, label, describe))
    tree.NullableSchema(inner) ->
      tree.NullableSchema(rewrite(inner, label, describe))
    tree.ObjectSchema(properties) ->
      tree.ObjectSchema(
        list.map(properties, fn(property) {
          tree.PropertySchema(
            ..property,
            schema: rewrite(property.schema, label, describe),
          )
        }),
      )
    tree.UnionSchema(variants) ->
      tree.UnionSchema(
        list.map(variants, fn(variant) {
          tree.VariantSchema(
            ..variant,
            payload: option.map(variant.payload, rewrite(_, label, describe)),
          )
        }),
      )
  }
}

@internal
pub fn from_tree(node: Tree) -> Schema {
  Schema(node)
}

@internal
pub fn to_tree(schema: Schema) -> Tree {
  schema.tree
}

/// A codec built by `custom` without a schema has none to describe.
pub type SchemaError {
  UnknownSchema
}

// --- errors ------------------------------------------------------------------

/// A mistake in a codec definition. The strings name the offending field,
/// tag or label from the definition, never input data.
pub type DefinitionError {
  DuplicateFieldName(name: String)
  /// The codec after a `field` or `optional_field` is not another field or
  /// `success`.
  NotARecord(after_field: String)
  DuplicateTag(tag: String)
  EmptyUnion
  EmptyEnum
  DuplicateEnumLabel(label: String)
  /// Two labels map to the same value; `label` is the second.
  DuplicateEnumValue(label: String)
  ReversedIntegerBounds(minimum: Int, maximum: Int)
  ReversedNumberBounds(minimum: Number, maximum: Number)
  /// On JavaScript, a bound of `integer_between` outside the safe range.
  UnsafeIntegerBound(bound: Int)
}

/// A step of the path from the root of a value to a failure.
pub type PathSegment {
  Field(name: String)
  Index(index: Int)
}

/// Why a value failed to decode or encode. Typed decoding can report JSON,
/// structure, native conversion and contract-matching failures. Typed encoding
/// can report enum values, native numeric safety and nullable failures.
/// `contract.value_codec` can also report structure and label failures while
/// encoding. Both directions can report numeric bounds and `Custom` failures;
/// `to_json` can additionally report `UnrepresentableNumber`.
///
/// May gain variants in a minor release; match with a `_` branch.
pub type Reason {
  /// `decode_json` could not parse the text; the path is empty.
  InvalidJson(value.ParseError)
  ExpectedString
  ExpectedInt
  ExpectedNumber
  ExpectedBool
  ExpectedArray
  ExpectedObject
  WrongLength(expected: Int, actual: Int)
  MissingField
  UnknownField
  DuplicateField
  UnknownEnumLabel
  UnknownTag
  /// The number is beyond the largest finite float.
  FloatOutOfRange
  /// `contract.decode`: the codec's schema differs from the contract's.
  ContractMismatch
  UnknownEnumValue
  /// On JavaScript, an `Int` outside the safe integer range.
  UnsafeInteger
  /// On JavaScript, an infinite or NaN `Float`.
  NonFiniteFloat
  /// `nullable` was given `Some(x)` whose inner codec encodes `x` as `null`.
  NullInsideNullable
  /// `to_json`: the number has no exact `gleam/json` form.
  UnrepresentableNumber(Number)
  IntegerOutsideRange(minimum: Int, maximum: Int)
  NumberOutsideRange(minimum: Number, maximum: Number)
  /// A message from `try_map`, `decode_failure` or `encode_failure`.
  Custom(message: String)
}

/// A decoding failure at `path`. Read fields by label.
pub type DecodeError {
  DecodeError(path: List(PathSegment), reason: Reason)
}

/// An encoding failure at `path`. Read fields by label.
pub type EncodeError {
  EncodeError(path: List(PathSegment), reason: Reason)
}

/// A decoding failure with `Custom(message)` at the current path, for
/// `custom` decoders.
pub fn decode_failure(message: String) -> DecodeError {
  DecodeError([], Custom(message))
}

/// An encoding failure with `Custom(message)` at the current path, for
/// `custom` encoders.
pub fn encode_failure(message: String) -> EncodeError {
  EncodeError([], Custom(message))
}

// --- codec -------------------------------------------------------------------

/// Encodes `a` to JSON, decodes JSON to `a`, and describes the JSON.
///
/// A codec holds each of its inputs once, so sending it to another process
/// copies about its own size. It builds its operations each time it is used.
pub opaque type Codec(a) {
  // One thunk per combinator: it captures the combinator's arguments once and
  // builds the operations when the codec is used, so no captured value is
  // held by several stored closures.
  Codec(ops: fn() -> Ops(a))
}

fn ops(codec: Codec(a)) -> Ops(a) {
  codec.ops()
}

/// The operations of a codec, built on demand and never stored in a codec.
type Ops(a) {
  Ops(
    text_encode: Option(fn(a) -> Result(String, EncodeError)),
    encode: fn(a) -> Result(Value, EncodeError),
    decode: fn(Value) -> Result(a, DecodeError),
    native_decode: fn(native.Raw) -> Result(a, DecodeError),
    // The schema, `None` when unknown, or the first definition mistake.
    // Computed on demand, so record codecs built inside a decode stay cheap.
    definition: fn() -> Result(Option(Tree), DefinitionError),
    // A value of `a` for describing records and for failed `decoder` runs.
    placeholder: fn() -> a,
    fields: Option(Fields(a)),
  )
}

/// The fields of a record codec built by `field`, `optional_field` and
/// `success`.
type Fields(a) {
  Fields(
    // Thread visited declarations through conversion, without running
    // placeholder continuations again. Decode results count present members.
    encode: fn(a, Seen) -> Result(List(#(String, Value)), EncodeError),
    decode: fn(List(#(String, Value)), Seen) -> Result(#(a, Int), DecodeError),
    native_decode: fn(native.Raw, Seen) -> Result(#(a, Int), DecodeError),
    names: fn() -> List(String),
    properties: fn() -> Result(List(Property), DefinitionError),
  )
}

type Property {
  Property(name: String, required: Bool, schema: Option(Tree))
}

/// The schema, after panicking on a definition mistake.
fn defined(codec: Codec(a)) -> Option(Tree) {
  case ops(codec).definition() {
    Ok(schema) -> schema
    Error(error) -> definition_panic(error)
  }
}

/// Panic on a definition mistake found where the codec is used.
fn ensure(defect: Option(DefinitionError)) -> Nil {
  case defect {
    Some(error) -> definition_panic(error)
    None -> Nil
  }
}

fn definition_panic(error: DefinitionError) -> b {
  panic as {
    "json_blueprint: invalid codec definition: "
    <> describe_definition_error(error)
  }
}

/// Report a definition mistake without panicking. Use it for codecs built
/// from runtime data, such as enum labels or bounds loaded at runtime; the
/// other functions panic on the same mistake.
pub fn check(codec: Codec(a)) -> Result(Codec(a), DefinitionError) {
  case ops(codec).definition() {
    Ok(_) -> Ok(codec)
    Error(error) -> Error(error)
  }
}

// --- use ---------------------------------------------------------------------

/// Encode to a `Value`.
pub fn encode(codec: Codec(a), item: a) -> Result(Value, EncodeError) {
  ops(codec).encode(item)
}

/// Decode a `Value`.
pub fn decode(codec: Codec(a), raw: Value) -> Result(a, DecodeError) {
  ops(codec).decode(raw)
}

/// Encode to compact JSON text.
pub fn encode_json(codec: Codec(a), item: a) -> Result(String, EncodeError) {
  let found = ops(codec)
  case found.text_encode {
    Some(encode) -> encode(item)
    None -> found.encode(item) |> result.map(value.to_string)
  }
}

/// Parse JSON text within the default byte bound and decode it.
/// Duplicate keys are rejected; numeric projection follows the selected codec.
/// A parse failure is
/// `DecodeError([], InvalidJson(error))`.
pub fn decode_json(codec: Codec(a), text: String) -> Result(a, DecodeError) {
  decode_json_with_limits(codec, text, value.default_limits())
}

/// Like `decode_json`, with a caller-selected byte bound.
pub fn decode_json_with_limits(
  codec: Codec(a),
  text: String,
  limits: value.Limits,
) -> Result(a, DecodeError) {
  use raw <- result.try(
    value.parse_native(text, limits)
    |> result.map_error(fn(error) { DecodeError([], InvalidJson(error)) }),
  )
  ops(codec).native_decode(raw)
}

/// Encode to `gleam/json`, for libraries that take `json.Json`. Numbers are
/// exact: a number with no exact `gleam/json` form, such as `1e400`, fails
/// with `UnrepresentableNumber`. Codecs of `Int`, `Float` and `String`
/// never produce one.
pub fn to_json(codec: Codec(a), item: a) -> Result(json.Json, EncodeError) {
  use encoded <- result.try(encode(codec, item))
  value_to_json(encoded, [])
}

fn value_to_json(
  raw: Value,
  path: List(PathSegment),
) -> Result(json.Json, EncodeError) {
  case raw {
    value.Number(item) ->
      value.to_json(raw)
      |> result.replace_error(EncodeError(
        list.reverse(path),
        UnrepresentableNumber(item),
      ))
    value.Array(items) ->
      list.index_map(items, fn(item, index) { #(index, item) })
      |> list.try_map(fn(pair) {
        value_to_json(pair.1, [Index(pair.0), ..path])
      })
      |> result.map(json.preprocessed_array)
    value.Object(members) ->
      members
      |> list.try_map(fn(member) {
        value_to_json(member.1, [Field(member.0), ..path])
        |> result.map(fn(converted) { #(member.0, converted) })
      })
      |> result.map(json.object)
    _ -> {
      let assert Ok(converted) = value.to_json(raw)
      Ok(converted)
    }
  }
}

/// A `gleam/dynamic/decode` decoder, for libraries that take one, such as
/// `json.parse(text, codec.decoder(user_codec()))`.
///
/// The parser that produced the data owns duplicate keys, number precision
/// and size limits; see `value.decoder`. A failure is one `decode.DecodeError`
/// whose `expected` is the `describe_decode_error` text.
pub fn decoder(codec: Codec(a)) -> decode.Decoder(a) {
  value.decoder()
  |> decode.then(fn(raw) {
    let found = ops(codec)
    case found.decode(raw) {
      Ok(item) -> decode.success(item)
      Error(error) ->
        decode.failure(found.placeholder(), describe_decode_error(error))
    }
  })
}

/// A value of `a` that the codec holds for describing itself, for a generic
/// wrapper that needs one without input: the `placeholder` of a `try_map`
/// or `custom` over this codec, or `decode.failure` in a hand-written
/// `gleam/dynamic/decode` decoder. It is the value the codec was built
/// with, such as `""` for `string()`, `minimum` for `integer_between`, the
/// first variant of a union or the record built from its fields'
/// placeholders. It need not be valid input and is not a default: never
/// encode it as data.
///
/// ```gleam
/// pub fn non_empty(inner: Codec(List(a))) -> Codec(List(a)) {
///   codec.try_map(
///     inner,
///     decode: fn(items) {
///       case items {
///         [] -> Error("expected at least one item")
///         _ -> Ok(items)
///       }
///     },
///     encode: Ok,
///     placeholder: codec.placeholder(inner),
///   )
/// }
/// ```
pub fn placeholder(codec: Codec(a)) -> a {
  ops(codec).placeholder()
}

/// The codec's schema.
pub fn schema(codec: Codec(a)) -> Result(Schema, SchemaError) {
  case defined(codec) {
    Some(found) -> Ok(Schema(found))
    None -> Error(UnknownSchema)
  }
}

/// The complete Draft 2020-12 schema document as JSON text.
pub fn schema_json(codec: Codec(a)) -> Result(String, SchemaError) {
  schema(codec)
  |> result.map(fn(found) { found |> schema_document |> value.to_string })
}

// --- primitives --------------------------------------------------------------

/// A codec with no inputs: its operations are a module constant of named
/// functions, so using it allocates nothing and copying it costs nothing.
fn leaf(operations: fn() -> Ops(a)) -> Codec(a) {
  Codec(operations)
}

fn fail(reason: Reason) -> Result(a, DecodeError) {
  Error(DecodeError([], reason))
}

fn refuse(reason: Reason) -> Result(a, EncodeError) {
  Error(EncodeError([], reason))
}

/// A JSON string.
pub fn string() -> Codec(String) {
  leaf(string_ops)
}

fn string_ops() -> Ops(String) {
  string_operations
}

const string_operations =
  Ops(
    text_encode: None,
    encode: encode_string,
    decode: decode_string,
    native_decode: native_decode_string,
    definition: string_definition,
    placeholder: string_placeholder,
    fields: None,
  )

fn string_definition() -> Result(Option(Tree), DefinitionError) {
  Ok(Some(tree.StringSchema))
}

fn encode_string(item: String) -> Result(Value, EncodeError) {
  Ok(value.String(item))
}

fn decode_string(raw: Value) -> Result(String, DecodeError) {
  case raw {
    value.String(item) -> Ok(item)
    _ -> fail(ExpectedString)
  }
}

fn native_decode_string(raw: native.Raw) -> Result(String, DecodeError) {
  native.string(raw)
  |> result.replace_error(DecodeError([], ExpectedString))
}

fn string_placeholder() -> String {
  ""
}

/// A JSON integer as an `Int`, with the schema `{"type": "integer"}`.
///
/// Decoding accepts any exact integer spelling, such as `12`, `12.0` or
/// `1.2e1`, of at most 24 digits. A longer integer, a fraction, or on
/// JavaScript an integer outside ±9,007,199,254,740,991 fails with
/// `ExpectedInt`; use `number()` for larger values. Encoding also refuses
/// integers longer than 24 digits with `ExpectedInt`; unsafe JavaScript
/// integers fail with `UnsafeInteger`.
pub fn int() -> Codec(Int) {
  leaf(int_ops)
}

fn int_ops() -> Ops(Int) {
  int_operations
}

const int_operations =
  Ops(
    text_encode: None,
    encode: encode_checked_int,
    decode: decode_int,
    native_decode: native_decode_int,
    definition: int_definition,
    placeholder: int_placeholder,
    fields: None,
  )

fn int_definition() -> Result(Option(Tree), DefinitionError) {
  Ok(Some(tree.IntSchema))
}

fn encode_checked_int(item: Int) -> Result(Value, EncodeError) {
  use encoded <- result.try(encode_int(item))
  case digit_count(item) <= 24 {
    True -> Ok(encoded)
    False -> refuse(ExpectedInt)
  }
}

fn native_decode_int(raw: native.Raw) -> Result(Int, DecodeError) {
  native.int(raw)
  |> result.map_error(fn(error) { native_numeric_failure(error, ExpectedInt) })
}

fn int_placeholder() -> Int {
  0
}

fn encode_int(item: Int) -> Result(Value, EncodeError) {
  case number.from_int(item) {
    Ok(parsed) -> Ok(value.Number(parsed))
    Error(_) -> refuse(UnsafeInteger)
  }
}

fn decode_int(raw: Value) -> Result(Int, DecodeError) {
  case raw {
    value.Number(item) ->
      case number.to_int(item, 24) {
        Ok(integer) -> Ok(integer)
        Error(_) -> fail(ExpectedInt)
      }
    _ -> fail(ExpectedInt)
  }
}

/// A JSON number as a `Float`, with the schema `{"type": "number"}`.
///
/// Decoding rounds to the nearest float, so `0.1` decodes to `0.1` although
/// that float is not exactly one tenth; a number beyond the float range
/// fails with `FloatOutOfRange`. Encoding writes the shortest decimal that
/// reads back as the same float. Use `number()` to keep numbers exact.
pub fn float() -> Codec(Float) {
  leaf(float_ops)
}

fn float_ops() -> Ops(Float) {
  float_operations
}

const float_operations =
  Ops(
    text_encode: None,
    encode: encode_float,
    decode: decode_float,
    native_decode: native_decode_float,
    definition: float_definition,
    placeholder: float_placeholder,
    fields: None,
  )

fn float_definition() -> Result(Option(Tree), DefinitionError) {
  Ok(Some(tree.NumberSchema))
}

fn encode_float(item: Float) -> Result(Value, EncodeError) {
  case number.from_float(item) {
    Ok(parsed) -> Ok(value.Number(parsed))
    Error(_) -> refuse(NonFiniteFloat)
  }
}

fn decode_float(raw: Value) -> Result(Float, DecodeError) {
  case raw {
    value.Number(item) ->
      case number.to_float(item) {
        Ok(float) -> Ok(float)
        Error(_) -> fail(FloatOutOfRange)
      }
    _ -> fail(ExpectedNumber)
  }
}

fn native_decode_float(raw: native.Raw) -> Result(Float, DecodeError) {
  case native.float(raw) {
    Ok(item) -> Ok(item)
    Error(native.NotNumber) -> fail(ExpectedNumber)
    Error(native.Unrepresentable) -> fail(FloatOutOfRange)
    Error(native.ProjectionCapacity) ->
      Error(native_numeric_failure(native.ProjectionCapacity, FloatOutOfRange))
  }
}

fn float_placeholder() -> Float {
  0.0
}

/// A JSON number, exactly, as a `number.Number`.
pub fn number() -> Codec(Number) {
  leaf(number_ops)
}

fn number_ops() -> Ops(Number) {
  number_operations
}

const number_operations =
  Ops(
    text_encode: None,
    encode: encode_number,
    decode: decode_number,
    native_decode: native_number,
    definition: number_definition,
    placeholder: zero,
    fields: None,
  )

fn number_definition() -> Result(Option(Tree), DefinitionError) {
  Ok(Some(tree.NumberSchema))
}

fn encode_number(item: Number) -> Result(Value, EncodeError) {
  Ok(value.Number(item))
}

fn decode_number(raw: Value) -> Result(Number, DecodeError) {
  case raw {
    value.Number(item) -> Ok(item)
    _ -> fail(ExpectedNumber)
  }
}

fn zero() -> Number {
  let assert Ok(found) = number.from_int(0)
  found
}

// Capacity exhaustion is neither invalid JSON number syntax nor a wrong type.
fn native_numeric_failure(
  error: native.NumericError,
  fallback: Reason,
) -> DecodeError {
  case error {
    native.ProjectionCapacity ->
      DecodeError(
        [],
        InvalidJson(value.ParseError(
          value.Location(0, 0, 0),
          value.RuntimeCapacityExceeded,
        )),
      )
    _ -> DecodeError([], fallback)
  }
}

fn native_number(raw: native.Raw) -> Result(Number, DecodeError) {
  native.number(raw)
  |> result.map_error(fn(error) {
    native_numeric_failure(error, ExpectedNumber)
  })
}

fn native_value(raw: native.Raw) -> Result(Value, DecodeError) {
  value.from_native(raw)
  |> result.map_error(fn(error) { DecodeError([], InvalidJson(error)) })
}

/// A JSON boolean.
pub fn bool() -> Codec(Bool) {
  leaf(bool_ops)
}

fn bool_ops() -> Ops(Bool) {
  bool_operations
}

const bool_operations =
  Ops(
    text_encode: None,
    encode: encode_bool,
    decode: decode_bool,
    native_decode: native_decode_bool,
    definition: bool_definition,
    placeholder: bool_placeholder,
    fields: None,
  )

fn bool_definition() -> Result(Option(Tree), DefinitionError) {
  Ok(Some(tree.BoolSchema))
}

fn encode_bool(item: Bool) -> Result(Value, EncodeError) {
  Ok(value.Bool(item))
}

fn decode_bool(raw: Value) -> Result(Bool, DecodeError) {
  case raw {
    value.Bool(item) -> Ok(item)
    _ -> fail(ExpectedBool)
  }
}

fn native_decode_bool(raw: native.Raw) -> Result(Bool, DecodeError) {
  native.bool(raw) |> result.replace_error(DecodeError([], ExpectedBool))
}

fn bool_placeholder() -> Bool {
  False
}

/// Any JSON value, passed through unchanged as a `Value`: for JSON that the
/// application forwards or inspects itself, such as a tool result from a
/// remote peer. Decoding accepts every value and encoding returns it; the
/// parse limits of `decode_json` still bound it.
///
/// Its schema is `AnySchema`, which renders as `{}`, the JSON Schema that
/// accepts every value; a record with a `value()` field describes that field
/// as `{}`. When a narrower schema for the value is known, use
/// `contract.value_codec`, which validates the value on encoding and decoding.
pub fn value() -> Codec(Value) {
  leaf(value_ops)
}

fn value_ops() -> Ops(Value) {
  value_operations
}

const value_operations =
  Ops(
    text_encode: None,
    encode: pass_value,
    decode: pass_value,
    native_decode: native_value,
    definition: value_definition,
    placeholder: value_placeholder,
    fields: None,
  )

fn value_definition() -> Result(Option(Tree), DefinitionError) {
  Ok(Some(tree.AnySchema))
}

fn pass_value(item: Value) -> Result(Value, a) {
  Ok(item)
}

fn value_placeholder() -> Value {
  value.Null
}

// --- refinements -------------------------------------------------------------

/// An integer from `minimum` to `maximum` inclusive, with those bounds in the
/// schema. Reversed bounds are a definition mistake.
pub fn integer_between(minimum: Int, maximum: Int) -> Codec(Int) {
  let defect = case minimum > maximum {
    True -> Some(ReversedIntegerBounds(minimum, maximum))
    False ->
      case number.from_int(minimum), number.from_int(maximum) {
        Ok(_), Ok(_) -> None
        Error(_), _ -> Some(UnsafeIntegerBound(minimum))
        _, Error(_) -> Some(UnsafeIntegerBound(maximum))
      }
  }
  let lower = number.from_int(minimum) |> result.unwrap(zero())
  let upper = number.from_int(maximum) |> result.unwrap(zero())
  let digits = int.max(digit_count(minimum), digit_count(maximum))
  Codec(fn() {
    Ops(
      text_encode: None,
      encode: fn(item) {
        ensure(defect)
        case item >= minimum && item <= maximum {
          True -> encode_int(item)
          False -> refuse(IntegerOutsideRange(minimum, maximum))
        }
      },
      decode: fn(raw) {
        ensure(defect)
        case raw {
          value.Number(item) ->
            case number.is_integer(item) {
              False -> fail(ExpectedInt)
              True ->
                case within(item, lower, upper) {
                  False -> fail(IntegerOutsideRange(minimum, maximum))
                  True ->
                    number.to_int(item, digits)
                    |> result.replace_error(DecodeError([], ExpectedInt))
                }
            }
          _ -> fail(ExpectedInt)
        }
      },
      native_decode: fn(raw) {
        ensure(defect)
        use item <- result.try(
          native.number(raw)
          |> result.map_error(fn(error) {
            native_numeric_failure(error, ExpectedInt)
          }),
        )
        case number.is_integer(item) {
          False -> fail(ExpectedInt)
          True ->
            case within(item, lower, upper) {
              False -> fail(IntegerOutsideRange(minimum, maximum))
              True ->
                number.to_int(item, digits)
                |> result.replace_error(DecodeError([], ExpectedInt))
            }
        }
      },
      definition: fn() {
        case defect {
          Some(error) -> Error(error)
          None -> Ok(Some(tree.IntegerRangeSchema(minimum, maximum)))
        }
      },
      placeholder: fn() { minimum },
      fields: None,
    )
  })
}

fn digit_count(item: Int) -> Int {
  // Digits are ASCII, so bytes count them without walking graphemes.
  string.byte_size(int.to_string(int.absolute_value(item)))
}

fn within(item: Number, lower: Number, upper: Number) -> Bool {
  number.compare(item, lower) != order.Lt
  && number.compare(item, upper) != order.Gt
}

/// A number from `minimum` to `maximum` inclusive, exactly, with those bounds
/// in the schema. Reversed bounds are a definition mistake.
pub fn number_between(minimum: Number, maximum: Number) -> Codec(Number) {
  let defect = case number.compare(minimum, maximum) {
    order.Gt -> Some(ReversedNumberBounds(minimum, maximum))
    _ -> None
  }
  Codec(fn() {
    Ops(
      text_encode: None,
      encode: fn(item) {
        ensure(defect)
        case within(item, minimum, maximum) {
          True -> Ok(value.Number(item))
          False -> refuse(NumberOutsideRange(minimum, maximum))
        }
      },
      decode: fn(raw) {
        ensure(defect)
        case raw {
          value.Number(item) ->
            case within(item, minimum, maximum) {
              True -> Ok(item)
              False -> fail(NumberOutsideRange(minimum, maximum))
            }
          _ -> fail(ExpectedNumber)
        }
      },
      native_decode: fn(raw) {
        ensure(defect)
        use item <- result.try(native_number(raw))
        case within(item, minimum, maximum) {
          True -> Ok(item)
          False -> fail(NumberOutsideRange(minimum, maximum))
        }
      },
      definition: fn() {
        case defect {
          Some(error) -> Error(error)
          None -> Ok(Some(tree.NumberRangeSchema(minimum, maximum)))
        }
      },
      placeholder: fn() { minimum },
      fields: None,
    )
  })
}

/// A string from a fixed set of labels, each mapped to a value, such as
/// `string_enum([#("admin", Admin), #("member", Member)])`. The JSON is the
/// bare label. An empty list, a repeated label or two labels with the same
/// value are definition mistakes.
pub fn string_enum(variants: List(#(String, a))) -> Codec(a) {
  let defect = case variants {
    [] -> Some(EmptyEnum)
    _ ->
      case list.length(variants) <= small_enum {
        True -> small_enum_defect(variants, [], [])
        False -> enum_defect(variants, set.new(), set.new())
      }
  }
  Codec(fn() {
    Ops(
      text_encode: None,
      encode: fn(item) {
        ensure(defect)
        case list.find(variants, fn(variant) { variant.1 == item }) {
          Ok(#(label, _)) -> Ok(value.String(label))
          Error(Nil) -> refuse(UnknownEnumValue)
        }
      },
      decode: fn(raw) {
        ensure(defect)
        case raw {
          value.String(label) ->
            case list.key_find(variants, label) {
              Ok(item) -> Ok(item)
              Error(Nil) -> fail(UnknownEnumLabel)
            }
          _ -> fail(ExpectedString)
        }
      },
      native_decode: fn(raw) {
        ensure(defect)
        use label <- result.try(
          native.string(raw)
          |> result.replace_error(DecodeError([], ExpectedString)),
        )
        list.key_find(variants, label)
        |> result.replace_error(DecodeError([], UnknownEnumLabel))
      },
      definition: fn() {
        case defect {
          Some(error) -> Error(error)
          None ->
            Ok(
              Some(
                tree.StringEnumSchema(
                  list.map(variants, fn(variant) { variant.0 }),
                ),
              ),
            )
        }
      },
      placeholder: fn() {
        case variants {
          [#(_, first), ..] -> first
          [] -> definition_panic(EmptyEnum)
        }
      },
      fields: None,
    )
  })
}

/// Up to this many labels, scanning the earlier ones is cheaper than sets.
const small_enum = 8

/// The first repeated label or value, found by scanning the earlier ones;
/// reports the same mistake as `enum_defect`.
fn small_enum_defect(
  variants: List(#(String, a)),
  labels: List(String),
  values: List(a),
) -> Option(DefinitionError) {
  case variants {
    [] -> None
    [#(label, item), ..rest] ->
      case list.contains(labels, label), list.contains(values, item) {
        True, _ -> Some(DuplicateEnumLabel(label))
        _, True -> Some(DuplicateEnumValue(label))
        False, False ->
          small_enum_defect(rest, [label, ..labels], [item, ..values])
      }
  }
}

/// Sets keep this linear in the number of labels, which may come from
/// runtime data.
fn enum_defect(
  variants: List(#(String, a)),
  labels: Set(String),
  values: Set(a),
) -> Option(DefinitionError) {
  case variants {
    [] -> None
    [#(label, item), ..rest] ->
      case set.contains(labels, label), set.contains(values, item) {
        True, _ -> Some(DuplicateEnumLabel(label))
        _, True -> Some(DuplicateEnumValue(label))
        False, False ->
          enum_defect(rest, set.insert(labels, label), set.insert(values, item))
      }
  }
}

/// Add a JSON Schema description without changing encoding or decoding. A
/// later description at the same node replaces an earlier one.
pub fn describe(codec: Codec(a), description: String) -> Codec(a) {
  Codec(fn() {
    let inner = ops(codec)
    let definition = inner.definition
    Ops(
      ..inner,
      definition: fn() {
        use found <- result.map(definition())
        option.map(found, fn(found) {
          case found {
            tree.DescribedSchema(_, inner) ->
              tree.DescribedSchema(description, inner)
            other -> tree.DescribedSchema(description, other)
          }
        })
      },
      fields: None,
    )
  })
}

// --- collections -------------------------------------------------------------

/// A JSON array of items.
pub fn list(of item: Codec(a)) -> Codec(List(a)) {
  Codec(fn() {
    let item_ops = ops(item)
    let encode_item = item_ops.encode
    let decode_item = item_ops.decode
    let decode_native_item = item_ops.native_decode
    let item_definition = item_ops.definition
    Ops(
      text_encode: None,
      encode: fn(items) {
        list.index_map(items, fn(entry, index) { #(index, entry) })
        |> list.try_map(fn(pair) {
          encode_item(pair.1) |> at_encode(Index(pair.0))
        })
        |> result.map(value.Array)
      },
      decode: fn(raw) {
        case raw {
          value.Array(items) -> decode_items(decode_item, items, 0, [])
          _ -> fail(ExpectedArray)
        }
      },
      native_decode: fn(raw) {
        native.array_decode(
          raw,
          fn(raw, index) { decode_native_item(raw) |> at_decode(Index(index)) },
          DecodeError([], ExpectedArray),
        )
      },
      definition: fn() { item_definition() |> map_schema(tree.ListSchema) },
      placeholder: fn() { [] },
      fields: None,
    )
  })
}

fn decode_items(
  decode_item: fn(Value) -> Result(a, DecodeError),
  items: List(Value),
  index: Int,
  done: List(a),
) -> Result(List(a), DecodeError) {
  case items {
    [] -> Ok(list.reverse(done))
    [raw, ..rest] ->
      case decode_item(raw) |> at_decode(Index(index)) {
        Ok(decoded) ->
          decode_items(decode_item, rest, index + 1, [decoded, ..done])
        Error(error) -> Error(error)
      }
  }
}

/// A two-item JSON array.
pub fn pair(left: Codec(a), right: Codec(b)) -> Codec(#(a, b)) {
  Codec(fn() {
    let left_ops = ops(left)
    let right_ops = ops(right)
    let encode_left = left_ops.encode
    let encode_right = right_ops.encode
    let decode_left = left_ops.decode
    let decode_right = right_ops.decode
    let decode_native_left = left_ops.native_decode
    let decode_native_right = right_ops.native_decode
    let left_definition = left_ops.definition
    let right_definition = right_ops.definition
    let left_placeholder = left_ops.placeholder
    let right_placeholder = right_ops.placeholder
    Ops(
      text_encode: None,
      encode: fn(items: #(a, b)) {
        use first <- result.try(encode_left(items.0) |> at_encode(Index(0)))
        use second <- result.try(encode_right(items.1) |> at_encode(Index(1)))
        Ok(value.Array([first, second]))
      },
      decode: fn(raw) {
        case raw {
          value.Array([first, second]) -> {
            use first <- result.try(decode_left(first) |> at_decode(Index(0)))
            use second <- result.try(
              decode_right(second) |> at_decode(Index(1)),
            )
            Ok(#(first, second))
          }
          value.Array(items) -> fail(WrongLength(2, list.length(items)))
          _ -> fail(ExpectedArray)
        }
      },
      native_decode: fn(raw) {
        case native.array_items(raw) {
          Ok([first, second]) -> {
            use first <- result.try(
              decode_native_left(first) |> at_decode(Index(0)),
            )
            use second <- result.try(
              decode_native_right(second) |> at_decode(Index(1)),
            )
            Ok(#(first, second))
          }
          Ok(items) -> fail(WrongLength(2, list.length(items)))
          Error(Nil) -> fail(ExpectedArray)
        }
      },
      definition: fn() {
        use first <- result.try(left_definition())
        use second <- result.map(right_definition())
        case first, second {
          Some(first), Some(second) -> Some(tree.PairSchema(first, second))
          _, _ -> None
        }
      },
      placeholder: fn() { #(left_placeholder(), right_placeholder()) },
      fields: None,
    )
  })
}

/// `null` or the inner codec's JSON, as an `Option`. `Some(x)` whose inner
/// encoding is itself `null` fails with `NullInsideNullable`, because it
/// would decode as `None`.
pub fn nullable(inner: Codec(a)) -> Codec(Option(a)) {
  Codec(fn() {
    let inner_ops = ops(inner)
    let encode_inner = inner_ops.encode
    let decode_inner = inner_ops.decode
    let decode_native_inner = inner_ops.native_decode
    let inner_definition = inner_ops.definition
    Ops(
      text_encode: None,
      encode: fn(item) {
        case item {
          None -> Ok(value.Null)
          Some(item) ->
            case encode_inner(item) {
              Ok(value.Null) -> refuse(NullInsideNullable)
              other -> other
            }
        }
      },
      decode: fn(raw) {
        case raw {
          value.Null -> Ok(None)
          _ -> decode_inner(raw) |> result.map(Some)
        }
      },
      native_decode: fn(raw) {
        case native.is_null(raw) {
          True -> Ok(None)
          False -> decode_native_inner(raw) |> result.map(Some)
        }
      },
      definition: fn() { inner_definition() |> map_schema(tree.NullableSchema) },
      placeholder: fn() { None },
      fields: None,
    )
  })
}

fn map_schema(
  found: Result(Option(Tree), DefinitionError),
  wrap: fn(Tree) -> Tree,
) -> Result(Option(Tree), DefinitionError) {
  result.map(found, option.map(_, wrap))
}

fn at_encode(
  outcome: Result(a, EncodeError),
  segment: PathSegment,
) -> Result(a, EncodeError) {
  result.map_error(outcome, fn(error) {
    EncodeError([segment, ..error.path], error.reason)
  })
}

fn at_decode(
  outcome: Result(a, DecodeError),
  segment: PathSegment,
) -> Result(a, DecodeError) {
  result.map_error(outcome, fn(error) {
    DecodeError([segment, ..error.path], error.reason)
  })
}

// --- records -----------------------------------------------------------------

/// A required field of a record, followed by the rest of the record:
///
/// ```gleam
/// use name <- codec.field("name", codec.string(), get: fn(u) { u.name })
/// ```
///
/// `get` reads the field when encoding. The rest of the record is the codec
/// that `next` returns: another `field` or `optional_field`, or `success`.
///
/// Pass the getter with its `get:` label. Gleam checks arguments in
/// parameter order, and `next` (the rest of the `use` block) comes before
/// `get`, so the record type is known from `success` by the time the getter
/// is checked and the getter needs no annotation. Without the label the
/// getter fills the `then` slot and the call fails to type-check.
pub fn field(
  named name: String,
  of codec: Codec(a),
  then next: fn(a) -> Codec(r),
  get get: fn(r) -> a,
) -> Codec(r) {
  Codec(fn() {
    let codec_ops = ops(codec)
    let encode_item = codec_ops.encode
    let decode_item = codec_ops.decode
    let decode_native_item = codec_ops.native_decode
    let item_definition = codec_ops.definition
    let item_placeholder = codec_ops.placeholder
    let fields =
      Fields(
        encode: fn(record, seen) {
          let seen = visit_name(name, seen)
          let item = get(record)
          use encoded <- result.try(encode_item(item) |> at_encode(Field(name)))
          use others <- result.map(record_fields(name, next(item)).encode(
            record,
            seen,
          ))
          [#(name, encoded), ..others]
        },
        decode: fn(members, seen) {
          let seen = visit_name(name, seen)
          case list.key_find(members, name) {
            Error(Nil) -> Error(DecodeError([Field(name)], MissingField))
            Ok(raw) -> {
              use item <- result.try(decode_item(raw) |> at_decode(Field(name)))
              use #(record, used) <- result.map(record_fields(name, next(item)).decode(
                members,
                seen,
              ))
              #(record, used + 1)
            }
          }
        },
        native_decode: fn(members, seen) {
          let seen = visit_name(name, seen)
          case native.field(members, name) {
            Error(Nil) -> Error(DecodeError([Field(name)], MissingField))
            Ok(raw) -> {
              use item <- result.try(
                decode_native_item(raw) |> at_decode(Field(name)),
              )
              use #(record, used) <- result.map(record_fields(name, next(item)).native_decode(
                members,
                seen,
              ))
              #(record, used + 1)
            }
          }
        },
        names: fn() {
          prepend_name(
            name,
            record_fields(name, next(item_placeholder())).names(),
          )
        },
        properties: fn() {
          use found <- result.try(item_definition())
          let next_codec = next(item_placeholder())
          property(name, True, found, next_codec)
        },
      )
    record(fields, fn() { ops(next(item_placeholder())).placeholder() })
  })
}

/// An optional field of a record: absent decodes as `None`, and `None`
/// encodes as an absent field. JSON `null` fails to decode unless the inner
/// codec is `nullable`; with `nullable(c)`, absent, `null` and a value decode
/// as `None`, `Some(None)` and `Some(Some(x))`. Pass the getter with its
/// `get:` label, as for `field`:
///
/// ```gleam
/// use email <- codec.optional_field("email", codec.string(), get: fn(u) {
///   u.email
/// })
/// ```
pub fn optional_field(
  named name: String,
  of codec: Codec(a),
  then next: fn(Option(a)) -> Codec(r),
  get get: fn(r) -> Option(a),
) -> Codec(r) {
  Codec(fn() {
    let codec_ops = ops(codec)
    let encode_item = codec_ops.encode
    let decode_item = codec_ops.decode
    let decode_native_item = codec_ops.native_decode
    let item_definition = codec_ops.definition
    let fields =
      Fields(
        encode: fn(record, seen) {
          let seen = visit_name(name, seen)
          case get(record) {
            None -> record_fields(name, next(None)).encode(record, seen)
            Some(item) as found -> {
              use encoded <- result.try(
                encode_item(item) |> at_encode(Field(name)),
              )
              use others <- result.map(record_fields(name, next(found)).encode(
                record,
                seen,
              ))
              [#(name, encoded), ..others]
            }
          }
        },
        decode: fn(members, seen) {
          let seen = visit_name(name, seen)
          case list.key_find(members, name) {
            Error(Nil) -> record_fields(name, next(None)).decode(members, seen)
            Ok(raw) -> {
              use item <- result.try(decode_item(raw) |> at_decode(Field(name)))
              use #(record, used) <- result.map(record_fields(
                name,
                next(Some(item)),
              ).decode(members, seen))
              #(record, used + 1)
            }
          }
        },
        native_decode: fn(members, seen) {
          let seen = visit_name(name, seen)
          case native.field(members, name) {
            Error(Nil) ->
              record_fields(name, next(None)).native_decode(members, seen)
            Ok(raw) -> {
              use item <- result.try(
                decode_native_item(raw) |> at_decode(Field(name)),
              )
              use #(record, used) <- result.map(record_fields(
                name,
                next(Some(item)),
              ).native_decode(members, seen))
              #(record, used + 1)
            }
          }
        },
        names: fn() {
          prepend_name(name, record_fields(name, next(None)).names())
        },
        properties: fn() {
          use found <- result.try(item_definition())
          property(name, False, found, next(None))
        },
      )
    record(fields, fn() { ops(next(None)).placeholder() })
  })
}

/// The end of a record: the value built from the decoded fields. Alone,
/// `success(x)` is the empty object `{}`, which decodes as `x`.
pub fn success(value: r) -> Codec(r) {
  Codec(fn() {
    record(
      Fields(
        encode: fn(_, _) { Ok([]) },
        decode: fn(_, _) { Ok(#(value, 0)) },
        native_decode: fn(_, _) { Ok(#(value, 0)) },
        names: fn() { [] },
        properties: fn() { Ok([]) },
      ),
      fn() { value },
    )
  })
}

fn property(
  name: String,
  required: Bool,
  found: Option(Tree),
  next_codec: Codec(r),
) -> Result(List(Property), DefinitionError) {
  case ops(next_codec).fields {
    None -> Error(NotARecord(name))
    Some(fields) -> {
      use others <- result.try(fields.properties())
      case list.any(others, fn(other) { other.name == name }) {
        True -> Error(DuplicateFieldName(name))
        False -> Ok([Property(name, required, found), ..others])
      }
    }
  }
}

// Validate declarations during actual conversion, including omitted fields.
fn visit_name(name: String, seen: Seen) -> Seen {
  case seen {
    FewNames(names, count) ->
      case list.contains(names, name) {
        True -> definition_panic(DuplicateFieldName(name))
        False if count < 16 -> FewNames([name, ..names], count + 1)
        False ->
          ManyNames(
            list.fold([name, ..names], dict.new(), fn(found, name) {
              dict.insert(found, name, Nil)
            }),
          )
      }
    ManyNames(names) ->
      case dict.has_key(names, name) {
        True -> definition_panic(DuplicateFieldName(name))
        False -> ManyNames(dict.insert(names, name, Nil))
      }
  }
}

/// The field names a conversion has visited: a short list, which is cheaper
/// than a dictionary for most records, then a dictionary, so wide records
/// stay linear.
type Seen {
  FewNames(names: List(String), count: Int)
  ManyNames(names: Dict(String, Nil))
}

const no_names = FewNames([], 0)

fn prepend_name(name: String, others: List(String)) -> List(String) {
  case list.contains(others, name) {
    True -> definition_panic(DuplicateFieldName(name))
    False -> [name, ..others]
  }
}

fn record_fields(after: String, codec: Codec(r)) -> Fields(r) {
  case ops(codec).fields {
    Some(fields) -> fields
    None -> definition_panic(NotARecord(after))
  }
}

fn record(fields: Fields(r), placeholder: fn() -> r) -> Ops(r) {
  let Fields(
    encode: encode_fields,
    decode: decode_fields,
    native_decode: decode_native_fields,
    names:,
    properties:,
  ) = fields
  Ops(
    text_encode: None,
    encode: fn(item) {
      encode_fields(item, no_names) |> result.map(value.Object)
    },
    decode: fn(raw) {
      case raw {
        value.Object(members) -> {
          use #(record, used) <- result.try(decode_fields(members, no_names))
          case used == list.length(members) {
            True -> Ok(record)
            // A member was not used: name it, as an unknown or repeated key.
            False ->
              check_members(members, names(), [])
              |> result.replace(record)
          }
        }
        _ -> fail(ExpectedObject)
      }
    },
    native_decode: fn(raw) {
      case native.keys(raw) {
        Error(Nil) -> fail(ExpectedObject)
        Ok(present) -> {
          use #(record, used) <- result.try(decode_native_fields(raw, no_names))
          case used == list.length(present) {
            True -> Ok(record)
            False ->
              check_native_members(present, names())
              |> result.replace(record)
          }
        }
      }
    },
    definition: fn() {
      use properties <- result.map(properties())
      properties
      |> list.try_map(fn(property) {
        case property.schema {
          Some(found) ->
            Ok(tree.PropertySchema(property.name, property.required, found))
          None -> Error(Nil)
        }
      })
      |> result.map(tree.ObjectSchema)
      |> option.from_result
    },
    placeholder:,
    fields: Some(fields),
  )
}

fn check_members(
  members: List(#(String, Value)),
  names: List(String),
  seen: List(String),
) -> Result(Nil, DecodeError) {
  case members {
    [] -> Ok(Nil)
    [#(name, _), ..rest] ->
      case list.contains(seen, name), list.contains(names, name) {
        True, _ -> Error(DecodeError([Field(name)], DuplicateField))
        _, False -> Error(DecodeError([Field(name)], UnknownField))
        False, True -> check_members(rest, names, [name, ..seen])
      }
  }
}

fn check_native_members(
  names: List(String),
  allowed: List(String),
) -> Result(Nil, DecodeError) {
  case names {
    [] -> Ok(Nil)
    [name, ..rest] ->
      case list.contains(allowed, name) {
        True -> check_native_members(rest, allowed)
        False -> Error(DecodeError([Field(name)], UnknownField))
      }
  }
}

// --- unions ------------------------------------------------------------------

/// The variants of a union under construction; see `union`.
pub opaque type Union(t) {
  Union(
    // In declaration order.
    variants: List(Variant(t)),
    select: fn(t) -> Tagged(t),
    defect: Option(DefinitionError),
  )
}

/// A case of a union. One closure holds the payload codec once and builds
/// the variant's operations when the union is used.
type Variant(t) {
  Variant(
    tag: String,
    token: Identity,
    has_payload: Bool,
    ops: fn() -> VariantOps(t),
  )
}

type VariantOps(t) {
  VariantOps(
    // The payload of a value this variant tagged; see `encode_union`.
    encode: fn(Dynamic) -> Result(Value, EncodeError),
    decode: fn(Value) -> Result(t, DecodeError),
    native_decode: fn(native.Raw) -> Result(t, DecodeError),
    definition: fn() -> Result(Option(Tree), DefinitionError),
    placeholder: fn() -> t,
  )
}

/// A value of a union with its tag, made by the function that `variant` or
/// `unit_variant` passes on.
pub opaque type Tagged(t) {
  Tagged(token: Identity, payload: Option(Dynamic))
}

/// A variant's identity: an Erlang reference or a JavaScript symbol, unique
/// across runtimes and nodes, that ties a tagged value to the variant that
/// tagged it.
type Identity

@external(erlang, "erlang", "make_ref")
@external(javascript, "../../json_blueprint_ffi.mjs", "identity")
fn new_identity() -> Identity

@external(erlang, "gleam_dynamic", "identity")
@external(javascript, "../../gleam_dynamic.mjs", "identity")
fn coerce(item: a) -> b

/// A codec for a sum type. Each case is a `variant` with a payload or a
/// `unit_variant` without one, and `match` maps each value to its case:
///
/// ```gleam
/// codec.union({
///   use circle <- codec.variant("circle", codec.int(), Circle)
///   use square <- codec.variant("square", codec.int(), Square)
///   use empty <- codec.unit_variant("empty", Empty)
///   codec.match(fn(shape) {
///     case shape {
///       Circle(radius) -> circle(radius)
///       Square(side) -> square(side)
///       Empty -> empty
///     }
///   })
/// })
/// ```
///
/// The JSON is `{"tag": "circle", "value": 2}`; a unit variant has no
/// `"value"`. Gleam checks the `case` for exhaustiveness. A repeated tag or a
/// union with no variants is a definition mistake.
///
/// `match` must return only what this union's own `variant` and
/// `unit_variant` pass on. A value tagged by another union's tagging function
/// or tagged value, such as one captured from an enclosing union, panics when
/// it is encoded, and `check` cannot see it. The payload is encoded after
/// `match` returns, for the value `match` returned.
pub fn union(variants: Union(t)) -> Codec(t) {
  let Union(variants:, select:, defect:) = variants
  let defect = case defect, variants {
    Some(_), _ -> defect
    None, [] -> Some(EmptyUnion)
    None, _ -> None
  }
  Codec(fn() {
    Ops(
      text_encode: None,
      encode: fn(item) {
        ensure(defect)
        encode_union(variants, select(item))
      },
      decode: fn(raw) {
        ensure(defect)
        decode_union(variants, raw)
      },
      native_decode: fn(raw) {
        ensure(defect)
        decode_native_union(variants, raw)
      },
      definition: fn() {
        case defect {
          Some(error) -> Error(error)
          None -> union_schema(variants, [])
        }
      },
      placeholder: fn() {
        case variants {
          [first, ..] -> first.ops().placeholder()
          [] -> definition_panic(EmptyUnion)
        }
      },
      fields: None,
    )
  })
}

/// A case of a union whose JSON carries a payload. `next` receives the
/// function that tags a payload as this case, for use in `match`.
pub fn variant(
  tag: String,
  of payload: Codec(p),
  construct construct: fn(p) -> t,
  then next: fn(fn(p) -> Tagged(t)) -> Union(t),
) -> Union(t) {
  // The tagging function holds only the token, never the payload codec,
  // which the variant holds once.
  let token = new_identity()
  let rest = next(fn(item) { Tagged(token, Some(coerce(item))) })
  add_variant(
    rest,
    Variant(tag, token, True, fn() {
      let payload_ops = ops(payload)
      VariantOps(
        // `encode_union` checked the token, so the value is a `p`.
        encode: fn(item) { payload_ops.encode(coerce(item)) },
        decode: fn(raw) { payload_ops.decode(raw) |> result.map(construct) },
        native_decode: fn(raw) {
          payload_ops.native_decode(raw) |> result.map(construct)
        },
        definition: payload_ops.definition,
        placeholder: fn() { construct(payload_ops.placeholder()) },
      )
    }),
  )
}

/// A case of a union without a payload, such as `Empty`. `next` receives the
/// tagged value, for use in `match`.
pub fn unit_variant(
  tag: String,
  value item: t,
  then next: fn(Tagged(t)) -> Union(t),
) -> Union(t) {
  let token = new_identity()
  let rest = next(Tagged(token, None))
  add_variant(
    rest,
    Variant(tag, token, False, fn() {
      VariantOps(
        encode: fn(_) { Ok(value.Null) },
        decode: fn(_) { Ok(item) },
        native_decode: fn(_) { Ok(item) },
        definition: fn() { Ok(None) },
        placeholder: fn() { item },
      )
    }),
  )
}

/// The end of a union: the function that maps each value to its case,
/// using the tagging functions and tagged values this union passed on.
pub fn match(encode: fn(t) -> Tagged(t)) -> Union(t) {
  Union([], encode, None)
}

fn add_variant(rest: Union(t), variant: Variant(t)) -> Union(t) {
  let tag = variant.tag
  let repeated = list.any(rest.variants, fn(other) { other.tag == tag })
  let defect = case rest.defect, repeated {
    Some(_), _ -> rest.defect
    None, True -> Some(DuplicateTag(tag))
    None, False -> None
  }
  Union([variant, ..rest.variants], rest.select, defect)
}

fn find_variant(
  variants: List(Variant(t)),
  tag: String,
) -> Result(Variant(t), Nil) {
  list.find(variants, fn(variant) { variant.tag == tag })
}

fn encode_union(
  variants: List(Variant(t)),
  tagged: Tagged(t),
) -> Result(Value, EncodeError) {
  let Tagged(token, payload) = tagged
  case list.find(variants, fn(variant) { variant.token == token }), payload {
    Ok(Variant(tag:, has_payload: False, ..)), None ->
      Ok(value.Object([#("tag", value.String(tag))]))
    Ok(Variant(tag:, has_payload: True, ops:, ..)), Some(item) ->
      case ops().encode(item) {
        Ok(encoded) ->
          Ok(
            value.Object([
              #("tag", value.String(tag)),
              #("value", encoded),
            ]),
          )
        Error(error) -> Error(error) |> at_encode(Field("value"))
      }
    _, _ -> foreign_tag_panic(variants)
  }
}

/// A tagging function or tagged value belongs to the union whose `variant`
/// or `unit_variant` passed it on.
fn foreign_tag_panic(variants: List(Variant(t))) -> b {
  panic as {
    "json_blueprint: the union with tags "
    <> string.join(list.map(variants, fn(variant) { quote(variant.tag) }), ", ")
    <> " was given a value tagged by a tagging function or tagged value from "
    <> "another codec.union; in `match`, use only what this union's "
    <> "`variant` and `unit_variant` pass on"
  }
}

fn union_schema(
  variants: List(Variant(t)),
  done: List(tree.VariantSchema),
) -> Result(Option(Tree), DefinitionError) {
  case variants {
    [] -> Ok(Some(tree.UnionSchema(list.reverse(done))))
    [variant, ..rest] -> {
      use found <- result.try(variant.ops().definition())
      case variant.has_payload, found {
        False, _ ->
          union_schema(rest, [tree.VariantSchema(variant.tag, None), ..done])
        True, Some(payload) ->
          union_schema(rest, [
            tree.VariantSchema(variant.tag, Some(payload)),
            ..done
          ])
        // A payload without a schema leaves the union without one, but
        // later variants may still hold a definition mistake.
        True, None -> union_schema(rest, done) |> result.replace(None)
      }
    }
  }
}

fn decode_union(
  variants: List(Variant(t)),
  raw: Value,
) -> Result(t, DecodeError) {
  case raw {
    value.Object(members) -> {
      use Nil <- result.try(check_members(members, ["tag", "value"], []))
      case list.key_find(members, "tag") {
        Error(Nil) -> Error(DecodeError([Field("tag")], MissingField))
        Ok(value.String(tag)) ->
          case find_variant(variants, tag) {
            Error(Nil) -> Error(DecodeError([Field("tag")], UnknownTag))
            Ok(variant) ->
              case variant.has_payload, list.key_find(members, "value") {
                True, Ok(payload) ->
                  variant.ops().decode(payload)
                  |> at_decode(Field("value"))
                True, Error(Nil) ->
                  Error(DecodeError([Field("value")], MissingField))
                False, Ok(_) ->
                  Error(DecodeError([Field("value")], UnknownField))
                False, Error(Nil) -> variant.ops().decode(value.Null)
              }
          }
        Ok(_) -> Error(DecodeError([Field("tag")], ExpectedString))
      }
    }
    _ -> fail(ExpectedObject)
  }
}

fn decode_native_union(
  variants: List(Variant(t)),
  raw: native.Raw,
) -> Result(t, DecodeError) {
  use names <- result.try(
    native.keys(raw) |> result.replace_error(DecodeError([], ExpectedObject)),
  )
  use Nil <- result.try(check_native_members(names, ["tag", "value"]))
  use tag_raw <- result.try(
    native.field(raw, "tag")
    |> result.replace_error(DecodeError([Field("tag")], MissingField)),
  )
  use tag <- result.try(
    native.string(tag_raw)
    |> result.replace_error(DecodeError([Field("tag")], ExpectedString)),
  )
  use variant <- result.try(
    find_variant(variants, tag)
    |> result.replace_error(DecodeError([Field("tag")], UnknownTag)),
  )
  case variant.has_payload, native.field(raw, "value") {
    True, Ok(payload) ->
      variant.ops().native_decode(payload)
      |> at_decode(Field("value"))
    True, Error(Nil) -> Error(DecodeError([Field("value")], MissingField))
    False, Ok(_) -> Error(DecodeError([Field("value")], UnknownField))
    False, Error(Nil) -> variant.ops().native_decode(raw)
  }
}

// --- mapping -----------------------------------------------------------------

/// Convert a codec to another type with total conversions in both
/// directions, such as `map(codec.string(), decode: Email, encode: fn(e) {
/// e.address })`. The schema is unchanged.
pub fn map(
  codec: Codec(a),
  decode from: fn(a) -> b,
  encode to: fn(b) -> a,
) -> Codec(b) {
  Codec(fn() {
    let codec_ops = ops(codec)
    let encode_inner = codec_ops.encode
    let decode_inner = codec_ops.decode
    let decode_native_inner = codec_ops.native_decode
    let inner_placeholder = codec_ops.placeholder
    Ops(
      text_encode: None,
      encode: fn(item) { encode_inner(to(item)) },
      decode: fn(raw) { decode_inner(raw) |> result.map(from) },
      native_decode: fn(raw) { decode_native_inner(raw) |> result.map(from) },
      definition: codec_ops.definition,
      placeholder: fn() { from(inner_placeholder()) },
      fields: None,
    )
  })
}

/// Like `map`, with conversions that may fail with a message. A failure is
/// `Custom(message)` at the codec's path. `placeholder` is any value of `b`,
/// used where a value is needed without input, as `decode.failure` does.
///
/// Over a whole record, the path of a failure is the record's own, `[]` at
/// the root. To report a check across fields at the field it concerns, build
/// that field's codec inside the record from the fields decoded before it:
///
/// ```gleam
/// use items <- codec.field("items", codec.list(codec.int()), get: fn(o) {
///   o.items
/// })
/// use total <- codec.field("total", total_of(items), get: fn(o) { o.total })
/// codec.success(Order(items:, total:))
/// ```
///
/// where `total_of(items)` is a `try_map` over `codec.int()` that fails when
/// the total differs from the sum. A failure then has the path
/// `[Field("total")]`, in both directions. When the codec describes itself,
/// `total_of` receives placeholder values, so its schema must not depend on
/// them.
pub fn try_map(
  codec: Codec(a),
  decode from: fn(a) -> Result(b, String),
  encode to: fn(b) -> Result(a, String),
  placeholder placeholder: b,
) -> Codec(b) {
  Codec(fn() {
    let codec_ops = ops(codec)
    let encode_inner = codec_ops.encode
    let decode_inner = codec_ops.decode
    let decode_native_inner = codec_ops.native_decode
    Ops(
      text_encode: None,
      encode: fn(item) {
        case to(item) {
          Ok(inner) -> encode_inner(inner)
          Error(message) -> refuse(Custom(message))
        }
      },
      decode: fn(raw) {
        use inner <- result.try(decode_inner(raw))
        from(inner)
        |> result.map_error(fn(message) { DecodeError([], Custom(message)) })
      },
      native_decode: fn(raw) {
        use inner <- result.try(decode_native_inner(raw))
        from(inner)
        |> result.map_error(fn(message) { DecodeError([], Custom(message)) })
      },
      definition: codec_ops.definition,
      placeholder: fn() { placeholder },
      fields: None,
    )
  })
}

/// A codec from your own functions over `Value`. `schema` is its schema, or
/// `None` when it has none, in which case `schema` returns `UnknownSchema`
/// and so does every codec built from this one. Take the schema from the
/// codec whose JSON yours matches, such as
/// `option.from_result(codec.schema(codec.string()))`, or from a contract
/// with `contract.schema`. Build errors with `decode_failure` and
/// `encode_failure`, or return those of other codecs. `placeholder` is any
/// value of `a`.
pub fn custom(
  encode encode: fn(a) -> Result(Value, EncodeError),
  decode decode: fn(Value) -> Result(a, DecodeError),
  schema schema: Option(Schema),
  placeholder placeholder: a,
) -> Codec(a) {
  Codec(fn() {
    Ops(
      text_encode: None,
      encode:,
      decode:,
      native_decode: fn(raw) {
        use raw <- result.try(native_value(raw))
        decode(raw)
      },
      definition: fn() {
        case schema {
          None -> Ok(None)
          Some(found) ->
            validate_tree(found.tree) |> result.replace(Some(found.tree))
        }
      },
      placeholder: fn() { placeholder },
      fields: None,
    )
  })
}

/// The first definition mistake in a schema tree. Every `Schema` that this
/// package hands out passes; `contract.load` checks parsed documents with it.
@internal
pub fn validate_tree(schema: Tree) -> Result(Nil, DefinitionError) {
  case schema {
    tree.DescribedSchema(_, inner)
    | tree.ListSchema(inner)
    | tree.NullableSchema(inner) -> validate_tree(inner)
    tree.StringSchema
    | tree.IntSchema
    | tree.NumberSchema
    | tree.BoolSchema
    | tree.AnySchema -> Ok(Nil)
    tree.StringEnumSchema([]) -> Error(EmptyEnum)
    tree.StringEnumSchema(labels) ->
      case first_repeated(labels, set.new()) {
        Some(label) -> Error(DuplicateEnumLabel(label))
        None -> Ok(Nil)
      }
    tree.PairSchema(left, right) -> {
      use Nil <- result.try(validate_tree(left))
      validate_tree(right)
    }
    tree.ObjectSchema(properties) -> {
      let names = list.map(properties, fn(property) { property.name })
      case first_repeated(names, set.new()) {
        Some(name) -> Error(DuplicateFieldName(name))
        None ->
          list.try_each(properties, fn(property) {
            validate_tree(property.schema)
          })
      }
    }
    tree.UnionSchema([]) -> Error(EmptyUnion)
    tree.UnionSchema(variants) -> {
      let tags = list.map(variants, fn(variant) { variant.tag })
      case first_repeated(tags, set.new()) {
        Some(tag) -> Error(DuplicateTag(tag))
        None ->
          list.try_each(variants, fn(variant) {
            case variant.payload {
              Some(payload) -> validate_tree(payload)
              None -> Ok(Nil)
            }
          })
      }
    }
    tree.IntegerRangeSchema(minimum, maximum) if minimum > maximum ->
      Error(ReversedIntegerBounds(minimum, maximum))
    tree.IntegerRangeSchema(_, _) -> Ok(Nil)
    tree.NumberRangeSchema(minimum, maximum) ->
      case number.compare(minimum, maximum) {
        order.Gt -> Error(ReversedNumberBounds(minimum, maximum))
        _ -> Ok(Nil)
      }
  }
}

fn first_repeated(items: List(String), seen: Set(String)) -> Option(String) {
  case items {
    [] -> None
    [item, ..rest] ->
      case set.contains(seen, item) {
        True -> Some(item)
        False -> first_repeated(rest, set.insert(seen, item))
      }
  }
}

// --- rendering ---------------------------------------------------------------

/// Render a decode error as text such as
/// `$["user"]["age"]: integer outside range 0 to 150`. The library writes the
/// path and the text of its own reasons, which contain no input values and no
/// unknown or repeated keys from the input. A `Custom(message)` renders as
/// the message, verbatim, such as `$["total"]: total 4 differs from 3`, so
/// leave input values out of the messages that must not show them. An empty
/// message renders as `custom validation failed`.
pub fn describe_decode_error(error: DecodeError) -> String {
  describe_failure(error.path, error.reason)
}

/// Render an encode error as text such as
/// `$["role"]: value is not in the enum`, like `describe_decode_error`.
pub fn describe_encode_error(error: EncodeError) -> String {
  describe_failure(error.path, error.reason)
}

fn describe_failure(path: List(PathSegment), reason: Reason) -> String {
  case reason {
    InvalidJson(error) -> value.describe_parse_error(error)
    // The last segment of these is a key from the input.
    UnknownField | DuplicateField ->
      path_text(list.take(path, list.length(path) - 1))
      <> ": "
      <> describe_reason(reason)
    _ -> path_text(path) <> ": " <> describe_reason(reason)
  }
}

fn path_text(path: List(PathSegment)) -> String {
  list.fold(path, "$", fn(text, segment) {
    case segment {
      Field(name) -> text <> "[" <> json.to_string(json.string(name)) <> "]"
      Index(index) -> text <> "[" <> int.to_string(index) <> "]"
    }
  })
}

fn describe_reason(reason: Reason) -> String {
  case reason {
    InvalidJson(error) -> value.describe_parse_error(error)
    ExpectedString -> "expected a string"
    ExpectedInt -> "expected an integer"
    ExpectedNumber -> "expected a number"
    ExpectedBool -> "expected a boolean"
    ExpectedArray -> "expected an array"
    ExpectedObject -> "expected an object"
    WrongLength(expected, _) ->
      "expected exactly " <> int.to_string(expected) <> " items"
    MissingField -> "missing field"
    UnknownField -> "unknown field"
    DuplicateField -> "duplicate field"
    UnknownEnumLabel -> "unknown enum label"
    UnknownTag -> "unknown tag"
    FloatOutOfRange -> "number outside the float range"
    ContractMismatch -> "the codec's schema differs from the contract's"
    UnknownEnumValue -> "value is not in the enum"
    UnsafeInteger -> "integer outside the JavaScript safe range"
    NonFiniteFloat -> "float is not finite"
    NullInsideNullable -> "the inner value of a nullable encoded as null"
    UnrepresentableNumber(_) -> "number has no exact gleam/json form"
    IntegerOutsideRange(minimum, maximum) ->
      "integer outside range "
      <> int.to_string(minimum)
      <> " to "
      <> int.to_string(maximum)
    NumberOutsideRange(minimum, maximum) ->
      "number outside range "
      <> number.to_string(minimum)
      <> " to "
      <> number.to_string(maximum)
    Custom("") -> "custom validation failed"
    Custom(message) -> message
  }
}

/// Render a definition error as text such as `field "name" appears twice`.
pub fn describe_definition_error(error: DefinitionError) -> String {
  case error {
    DuplicateFieldName(name) -> "field " <> quote(name) <> " appears twice"
    NotARecord(after) ->
      "the codec after field "
      <> quote(after)
      <> " is not another field or success"
    DuplicateTag(tag) -> "union tag " <> quote(tag) <> " appears twice"
    EmptyUnion -> "union has no variants"
    EmptyEnum -> "string enum has no labels"
    DuplicateEnumLabel(label) ->
      "enum label " <> quote(label) <> " appears twice"
    DuplicateEnumValue(label) ->
      "enum label " <> quote(label) <> " repeats the value of an earlier label"
    ReversedIntegerBounds(minimum, maximum) ->
      "integer bounds "
      <> int.to_string(minimum)
      <> " to "
      <> int.to_string(maximum)
      <> " are reversed"
    ReversedNumberBounds(minimum, maximum) ->
      "number bounds "
      <> number.to_string(minimum)
      <> " to "
      <> number.to_string(maximum)
      <> " are reversed"
    UnsafeIntegerBound(bound) ->
      "integer bound "
      <> int.to_string(bound)
      <> " is outside the JavaScript safe range"
  }
}

fn quote(text: String) -> String {
  json.to_string(json.string(text))
}

/// Whether decoding failed because the text exceeded a parse limit, such as
/// the 1 MiB byte limit, rather than being invalid.
pub fn is_limit_exceeded(error: DecodeError) -> Bool {
  case error.reason {
    InvalidJson(parse_error) -> value.is_limit_exceeded(parse_error)
    _ -> False
  }
}

// --- schema documents --------------------------------------------------------

/// The schema as a JSON Schema object, without `$schema`. `AnySchema` is
/// `{}`.
pub fn schema_value(schema: Schema) -> Value {
  tree_value(schema.tree)
}

fn tree_value(schema: Tree) -> Value {
  case schema {
    tree.DescribedSchema(description, tree.DescribedSchema(_, inner)) ->
      tree_value(tree.DescribedSchema(description, inner))
    tree.DescribedSchema(description, inner) -> {
      let assert value.Object(members) = tree_value(inner)
      value.Object([#("description", value.String(description)), ..members])
    }
    tree.StringSchema -> typed("string", [])
    tree.StringEnumSchema(labels) ->
      typed("string", [#("enum", value.Array(list.map(labels, value.String)))])
    tree.IntSchema -> typed("integer", [])
    tree.NumberSchema -> typed("number", [])
    tree.BoolSchema -> typed("boolean", [])
    tree.PairSchema(left, right) ->
      typed("array", [
        #("prefixItems", value.Array([tree_value(left), tree_value(right)])),
        #("minItems", integer(2)),
        #("maxItems", integer(2)),
      ])
    tree.ListSchema(items) -> typed("array", [#("items", tree_value(items))])
    tree.NullableSchema(inner) ->
      value.Object([
        #("anyOf", value.Array([typed("null", []), tree_value(inner)])),
      ])
    tree.ObjectSchema(properties) ->
      closed_object(
        list.map(properties, fn(property) {
          #(property.name, tree_value(property.schema))
        }),
        list.filter_map(properties, fn(property) {
          case property.required {
            True -> Ok(property.name)
            False -> Error(Nil)
          }
        }),
      )
    tree.UnionSchema(variants) ->
      typed("object", [
        #("oneOf", value.Array(list.map(variants, variant_schema_value))),
      ])
    tree.IntegerRangeSchema(minimum, maximum) ->
      typed("integer", [
        #("minimum", integer(minimum)),
        #("maximum", integer(maximum)),
      ])
    tree.NumberRangeSchema(minimum, maximum) ->
      typed("number", [
        #("minimum", value.Number(minimum)),
        #("maximum", value.Number(maximum)),
      ])
    tree.AnySchema -> value.Object([])
  }
}

/// The complete Draft 2020-12 schema document: `schema_value` with `$schema`.
pub fn schema_document(schema: Schema) -> Value {
  let assert value.Object(members) = schema_value(schema)
  value.Object([
    #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
    ..members
  ])
}

fn typed(kind: String, members: List(#(String, Value))) -> Value {
  value.Object([#("type", value.String(kind)), ..members])
}

fn integer(item: Int) -> Value {
  let assert Ok(found) = number.from_int(item)
  value.Number(found)
}

fn closed_object(
  properties: List(#(String, Value)),
  required: List(String),
) -> Value {
  typed("object", [
    #("properties", value.Object(properties)),
    #("required", value.Array(list.map(required, value.String))),
    #("additionalProperties", value.Bool(False)),
  ])
}

fn variant_schema_value(variant: tree.VariantSchema) -> Value {
  let tag = #("tag", value.Object([#("const", value.String(variant.tag))]))
  case variant.payload {
    None -> closed_object([tag], ["tag"])
    Some(payload) ->
      closed_object([tag, #("value", tree_value(payload))], ["tag", "value"])
  }
}

/// Register compiler-checked generated operations and their checked schema.
/// Generated modules share the strict parser and decode its retained evidence
/// directly. The placeholder stays lazy, as it is for ordinary codecs.
@internal
pub fn generated(
  encode encode: fn(a) -> Result(Value, EncodeError),
  decode decode: fn(Value) -> Result(a, DecodeError),
  strict_decode strict_decode: fn(native.Raw) -> Result(a, DecodeError),
  text_encode text_encode: fn(a) -> Result(String, EncodeError),
  schema schema: Schema,
  placeholder placeholder: fn() -> a,
) -> Codec(a) {
  Codec(fn() {
    Ops(
      text_encode: Some(text_encode),
      encode:,
      decode:,
      native_decode: strict_decode,
      definition: fn() { Ok(Some(schema.tree)) },
      placeholder:,
      fields: None,
    )
  })
}
