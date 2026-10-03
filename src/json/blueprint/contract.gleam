//// Schema contracts: a JSON Schema accepted at runtime, values validated
//// against it, and decoding of validated values.
////
//// Build a `Contract` from a codec (`from_codec`), from a `codec.Schema`
//// (`from_schema`), or from a Draft 2020-12 schema document (`load` for a
//// parsed `Value`, `parse` for text). A document must stay inside the finite
//// profile that codecs describe: closed objects, pairs, lists, nullable
//// values, bounded integers and numbers, string enums, tagged unions and
//// any value (`{}`, or the boolean schema `true`).
////
//// `validate` checks a `Value` and returns a `ValidatedValue` or a
//// `ValidationError` with the path of the first failure; validation uses the
//// same `codec.Reason` vocabulary as decoding. `decode` decodes a validated
//// value with a codec whose schema matches the contract, and fails with
//// `ContractMismatch` otherwise. `value_codec` is a `Codec(Value)` that
//// validates while decoding, for passing schema-checked JSON through.
////
//// Use this module when a schema arrives at runtime, such as a tool schema
//// from a remote server. To decode JSON text with a known codec,
//// `codec.decode_json` is enough. Validation walks an already parsed value,
//// so its cost is bounded by the parse limits.
////
//// ```gleam
//// import json/blueprint/codec
//// import json/blueprint/contract
//// import json/blueprint/value
////
//// pub fn example() {
////   let names = codec.list(codec.string())
////   let schema_text =
////     "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
////     <> "\"type\":\"array\",\"items\":{\"type\":\"string\"}}"
////   let assert Ok(remote) = contract.parse(schema_text, value.default_limits())
////   let assert Ok(parsed) = value.parse("[\"a\"]", value.default_limits())
////   let assert Ok(validated) = contract.validate(remote, parsed)
////   let assert Ok(["a"]) = contract.decode(names, validated)
//// }
//// ```

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string
import json/blueprint/codec.{
  type Codec, type DecodeError, type DefinitionError, type PathSegment,
  type Schema, Field, Index,
}
import json/blueprint/internal/schema_tree.{
  type PropertySchema, type Tree, type VariantSchema,
} as tree
import json/blueprint/number.{type Number}
import json/blueprint/value.{type Value}

/// A schema accepted for validation, normalized so that member and label
/// order does not matter.
pub opaque type Contract {
  Contract(schema: Tree)
}

/// A value that passed `validate`, with the schema it passed.
pub opaque type ValidatedValue {
  ValidatedValue(value: Value, schema: Tree)
}

/// The first failure of `validate`, at `path`. Read fields by label.
pub type ValidationError {
  ValidationError(path: List(PathSegment), reason: codec.Reason)
}

// --- building ----------------------------------------------------------------

/// The contract of a codec's schema. Panics on a definition mistake, like
/// other uses of the codec.
pub fn from_codec(codec: Codec(a)) -> Result(Contract, codec.SchemaError) {
  use found <- result.map(codec.schema(codec))
  from_schema(found)
}

/// The contract of a schema, such as one that a tool declaration holds.
/// Every `Schema` comes from a codec or a contract and is already checked,
/// so this cannot fail.
pub fn from_schema(schema: Schema) -> Contract {
  Contract(normalize(codec.to_tree(schema)))
}

/// The contract's schema, normalized.
pub fn schema(contract: Contract) -> Schema {
  codec.from_tree(contract.schema)
}

/// Whether two contracts accept the same values. Descriptions and the order
/// of properties, labels and variants do not matter.
pub fn same_schema(left: Contract, right: Contract) -> Bool {
  shape(left.schema) == shape(right.schema)
}

fn normalize(schema: Tree) -> Tree {
  case schema {
    tree.DescribedSchema(description, tree.DescribedSchema(_, inner)) ->
      normalize(tree.DescribedSchema(description, inner))
    tree.DescribedSchema(description, inner) ->
      tree.DescribedSchema(description, normalize(inner))
    tree.StringEnumSchema(labels) ->
      tree.StringEnumSchema(list.sort(labels, string.compare))
    tree.PairSchema(left, right) ->
      tree.PairSchema(normalize(left), normalize(right))
    tree.ListSchema(items) -> tree.ListSchema(normalize(items))
    tree.NullableSchema(inner) -> tree.NullableSchema(normalize(inner))
    tree.ObjectSchema(properties) ->
      properties
      |> list.map(fn(property) {
        tree.PropertySchema(..property, schema: normalize(property.schema))
      })
      |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
      |> tree.ObjectSchema
    tree.UnionSchema(variants) ->
      variants
      |> list.map(fn(variant) {
        tree.VariantSchema(
          ..variant,
          payload: option.map(variant.payload, normalize),
        )
      })
      |> list.sort(fn(a, b) { string.compare(a.tag, b.tag) })
      |> tree.UnionSchema
    other -> other
  }
}

/// The schema without descriptions, which do not affect validation.
fn shape(schema: Tree) -> Tree {
  case schema {
    tree.DescribedSchema(_, inner) -> shape(inner)
    tree.PairSchema(left, right) -> tree.PairSchema(shape(left), shape(right))
    tree.ListSchema(items) -> tree.ListSchema(shape(items))
    tree.NullableSchema(inner) -> tree.NullableSchema(shape(inner))
    tree.ObjectSchema(properties) ->
      tree.ObjectSchema(
        list.map(properties, fn(property) {
          tree.PropertySchema(..property, schema: shape(property.schema))
        }),
      )
    tree.UnionSchema(variants) ->
      tree.UnionSchema(
        list.map(variants, fn(variant) {
          tree.VariantSchema(
            ..variant,
            payload: option.map(variant.payload, shape),
          )
        }),
      )
    other -> other
  }
}

// --- validating and decoding -------------------------------------------------

/// Check a value against the contract.
pub fn validate(
  contract: Contract,
  item: Value,
) -> Result(ValidatedValue, ValidationError) {
  use Nil <- result.map(validate_at(contract.schema, item, []))
  ValidatedValue(item, contract.schema)
}

/// The value that passed validation.
pub fn value(validated: ValidatedValue) -> Value {
  validated.value
}

/// Decode a validated value with a codec whose schema accepts the same values
/// as the contract that validated it. A codec with another schema, or none,
/// fails with `DecodeError([], ContractMismatch)`.
pub fn decode(
  codec: Codec(a),
  validated: ValidatedValue,
) -> Result(a, DecodeError) {
  case codec.schema(codec) {
    Ok(found) ->
      case shape(normalize(codec.to_tree(found))) == shape(validated.schema) {
        True -> codec.decode(codec, validated.value)
        False -> Error(codec.DecodeError([], codec.ContractMismatch))
      }
    Error(codec.UnknownSchema) ->
      Error(codec.DecodeError([], codec.ContractMismatch))
  }
}

/// A `Codec(Value)` with the contract's schema. Decoding validates against
/// the contract and fails with the validation error's path and reason;
/// encoding passes the value through unchanged.
pub fn value_codec(contract: Contract) -> Codec(Value) {
  codec.custom(
    encode: Ok,
    decode: fn(raw) {
      case validate(contract, raw) {
        Ok(validated) -> Ok(validated.value)
        Error(ValidationError(path, reason)) ->
          Error(codec.DecodeError(path, reason))
      }
    },
    schema: Some(codec.from_tree(contract.schema)),
    placeholder: value.Null,
  )
}

/// Render a validation error like `codec.describe_decode_error`, such as
/// `$["limit"]: integer outside range 1 to 10`.
pub fn describe_validation_error(error: ValidationError) -> String {
  codec.describe_decode_error(codec.DecodeError(error.path, error.reason))
}

fn invalid(
  path: List(PathSegment),
  reason: codec.Reason,
) -> Result(Nil, ValidationError) {
  Error(ValidationError(list.reverse(path), reason))
}

/// `path` is reversed.
fn validate_at(
  schema: Tree,
  item: Value,
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  case schema, item {
    tree.DescribedSchema(_, inner), _ -> validate_at(inner, item, path)
    tree.StringSchema, value.String(_) -> Ok(Nil)
    tree.StringSchema, _ -> invalid(path, codec.ExpectedString)

    tree.StringEnumSchema(labels), value.String(label) ->
      case list.contains(labels, label) {
        True -> Ok(Nil)
        False -> invalid(path, codec.UnknownEnumLabel)
      }
    tree.StringEnumSchema(_), _ -> invalid(path, codec.ExpectedString)

    tree.IntSchema, value.Number(found) ->
      case number.is_integer(found) {
        True -> Ok(Nil)
        False -> invalid(path, codec.ExpectedInt)
      }
    tree.IntSchema, _ -> invalid(path, codec.ExpectedInt)

    tree.NumberSchema, value.Number(_) -> Ok(Nil)
    tree.NumberSchema, _ -> invalid(path, codec.ExpectedNumber)

    tree.BoolSchema, value.Bool(_) -> Ok(Nil)
    tree.BoolSchema, _ -> invalid(path, codec.ExpectedBool)

    tree.PairSchema(left, right), value.Array([first, second]) -> {
      use Nil <- result.try(validate_at(left, first, [Index(0), ..path]))
      validate_at(right, second, [Index(1), ..path])
    }
    tree.PairSchema(_, _), value.Array(items) ->
      invalid(path, codec.WrongLength(2, list.length(items)))
    tree.PairSchema(_, _), _ -> invalid(path, codec.ExpectedArray)

    tree.ListSchema(inner), value.Array(items) ->
      validate_items(inner, items, 0, path)
    tree.ListSchema(_), _ -> invalid(path, codec.ExpectedArray)

    tree.NullableSchema(_), value.Null -> Ok(Nil)
    tree.NullableSchema(inner), _ -> validate_at(inner, item, path)

    tree.ObjectSchema(properties), value.Object(members) ->
      validate_object(properties, members, path)
    tree.ObjectSchema(_), _ -> invalid(path, codec.ExpectedObject)

    tree.UnionSchema(variants), value.Object(members) ->
      validate_union(variants, members, path)
    tree.UnionSchema(_), _ -> invalid(path, codec.ExpectedObject)

    tree.IntegerRangeSchema(minimum, maximum), value.Number(found) ->
      case number.is_integer(found) {
        False -> invalid(path, codec.ExpectedInt)
        True ->
          case within_integers(found, minimum, maximum) {
            True -> Ok(Nil)
            False -> invalid(path, codec.IntegerOutsideRange(minimum, maximum))
          }
      }
    tree.IntegerRangeSchema(_, _), _ -> invalid(path, codec.ExpectedInt)

    tree.NumberRangeSchema(minimum, maximum), value.Number(found) ->
      case within(found, minimum, maximum) {
        True -> Ok(Nil)
        False -> invalid(path, codec.NumberOutsideRange(minimum, maximum))
      }
    tree.NumberRangeSchema(_, _), _ -> invalid(path, codec.ExpectedNumber)

    tree.AnySchema, _ -> Ok(Nil)
  }
}

fn within(found: Number, minimum: Number, maximum: Number) -> Bool {
  number.compare(found, minimum) != order.Lt
  && number.compare(found, maximum) != order.Gt
}

fn within_integers(found: Number, minimum: Int, maximum: Int) -> Bool {
  case number.from_int(minimum), number.from_int(maximum) {
    Ok(lower), Ok(upper) -> within(found, lower, upper)
    _, _ -> False
  }
}

fn validate_items(
  schema: Tree,
  items: List(Value),
  index: Int,
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  // A plain `case` keeps the recursion a tail call, so a long array cannot
  // exhaust the JavaScript stack.
  case items {
    [] -> Ok(Nil)
    [item, ..rest] ->
      case validate_at(schema, item, [Index(index), ..path]) {
        Ok(Nil) -> validate_items(schema, rest, index + 1, path)
        Error(error) -> Error(error)
      }
  }
}

fn check_members(
  members: List(#(String, Value)),
  allowed: List(String),
  seen: List(String),
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  case members {
    [] -> Ok(Nil)
    [#(name, _), ..rest] ->
      case list.contains(seen, name), list.contains(allowed, name) {
        True, _ -> invalid([Field(name), ..path], codec.DuplicateField)
        _, False -> invalid([Field(name), ..path], codec.UnknownField)
        False, True -> check_members(rest, allowed, [name, ..seen], path)
      }
  }
}

fn validate_object(
  properties: List(PropertySchema),
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  let names = list.map(properties, fn(property) { property.name })
  use Nil <- result.try(check_members(members, names, [], path))
  list.try_each(properties, fn(property) {
    let at = [Field(property.name), ..path]
    case list.key_find(members, property.name), property.required {
      Ok(found), _ -> validate_at(property.schema, found, at)
      Error(Nil), True -> invalid(at, codec.MissingField)
      Error(Nil), False -> Ok(Nil)
    }
  })
}

fn validate_union(
  variants: List(VariantSchema),
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  use Nil <- result.try(check_members(members, ["tag", "value"], [], path))
  let tag_path = [Field("tag"), ..path]
  let value_path = [Field("value"), ..path]
  case list.key_find(members, "tag") {
    Error(Nil) -> invalid(tag_path, codec.MissingField)
    Ok(value.String(tag)) ->
      case list.find(variants, fn(variant) { variant.tag == tag }) {
        Error(Nil) -> invalid(tag_path, codec.UnknownTag)
        Ok(variant) ->
          case variant.payload, list.key_find(members, "value") {
            Some(payload), Ok(found) -> validate_at(payload, found, value_path)
            Some(_), Error(Nil) -> invalid(value_path, codec.MissingField)
            None, Ok(_) -> invalid(value_path, codec.UnknownField)
            None, Error(Nil) -> Ok(Nil)
          }
      }
    Ok(_) -> invalid(tag_path, codec.ExpectedString)
  }
}

// --- schema documents --------------------------------------------------------

const draft_2020_12 = "https://json-schema.org/draft/2020-12/schema"

/// Why a schema document is malformed: a keyword has the wrong JSON type or
/// an incomplete shape.
pub type MalformedReason {
  ExpectedObject
  ExpectedText
  ExpectedInteger
  ExpectedNumber
  ExpectedBoolean
  ExpectedArray
  MissingKeyword(name: String)
  DuplicateKey(name: String)
  DuplicateRequiredName(name: String)
  UndeclaredRequiredName(name: String)
  InvalidNullableAlternatives
  InvalidTaggedAlternatives
  InvalidTupleShape
  IncompleteIntegerRange
  IncompleteNumberRange
  ExpectedObjectSchema
  ExpectedClosedTag
}

/// Why a well-formed schema document is outside the codec profile.
pub type UnsupportedReason {
  UnsupportedKeyword(name: String)
  NestedDialect
  UnsupportedSchemaForm
  OpenObject
  ArbitraryUnion
  UnboundedArray
  UnsupportedTupleForm
  UnsupportedTaggedShape
}

/// Why `load` refused a schema document, at `path` within the document. The
/// strings name keywords and dialects from the document.
pub type DocumentError {
  MalformedDocument(path: List(PathSegment), reason: MalformedReason)
  UnsupportedDocument(path: List(PathSegment), reason: UnsupportedReason)
  UnsupportedDialect(path: List(PathSegment), dialect: String)
  /// The document is well formed but contradicts itself, such as an enum
  /// label listed twice or a reversed range.
  InvalidDefinition(path: List(PathSegment), error: DefinitionError)
}

/// Why `parse` refused schema text.
pub type LoadError {
  InvalidJson(value.ParseError)
  InvalidDocument(DocumentError)
}

/// Parse a schema document within `limits` and `load` it.
pub fn parse(
  text: String,
  limits: value.Limits,
) -> Result(Contract, LoadError) {
  case value.parse(text, limits) {
    Error(error) -> Error(InvalidJson(error))
    Ok(document) -> load(document) |> result.map_error(InvalidDocument)
  }
}

/// Load a Draft 2020-12 schema document. Its `$schema` must be the Draft
/// 2020-12 URI, and it must stay inside the codec profile; `description`
/// keywords are kept. A schema with no keywords but `description`, or the
/// boolean schema `true`, accepts any value, like `codec.value()`.
pub fn load(document: Value) -> Result(Contract, DocumentError) {
  use members <- result.try(object_members(document, []))
  use dialect <- result.try(required_member(members, "$schema", []))
  case dialect {
    value.String(found) if found == draft_2020_12 -> {
      let schema_members = without_member(members, "$schema")
      use parsed <- result.try(parse_schema(value.Object(schema_members), []))
      case codec.validate_tree(parsed.schema) {
        Ok(Nil) -> Ok(Contract(normalize(parsed.schema)))
        Error(error) ->
          Error(InvalidDefinition(
            invariant_path(error, parsed.invariants),
            error,
          ))
      }
    }
    value.String(found) -> Error(UnsupportedDialect([Field("$schema")], found))
    _ -> Error(MalformedDocument([Field("$schema")], ExpectedText))
  }
}

/// Render a document error as text such as
/// `$["properties"]["age"]["format"]: unsupported keyword "format"`.
pub fn describe_document_error(error: DocumentError) -> String {
  let #(path, text) = case error {
    MalformedDocument(path, reason) -> #(path, describe_malformed(reason))
    UnsupportedDocument(path, reason) -> #(path, describe_unsupported(reason))
    UnsupportedDialect(path, dialect) -> #(
      path,
      "unsupported dialect " <> quote(dialect),
    )
    InvalidDefinition(path, error) -> #(
      path,
      codec.describe_definition_error(error),
    )
  }
  path_text(path) <> ": " <> text
}

/// Render a load error: a parse error or a document error.
pub fn describe_load_error(error: LoadError) -> String {
  case error {
    InvalidJson(error) -> value.describe_parse_error(error)
    InvalidDocument(error) -> describe_document_error(error)
  }
}

fn describe_malformed(reason: MalformedReason) -> String {
  case reason {
    ExpectedObject -> "expected an object"
    ExpectedText -> "expected a string"
    ExpectedInteger -> "expected an integer"
    ExpectedNumber -> "expected a number"
    ExpectedBoolean -> "expected a boolean"
    ExpectedArray -> "expected an array"
    MissingKeyword(name) -> "missing keyword " <> quote(name)
    DuplicateKey(name) -> "duplicate key " <> quote(name)
    DuplicateRequiredName(name) -> "required name " <> quote(name) <> " repeats"
    UndeclaredRequiredName(name) ->
      "required name " <> quote(name) <> " is not a property"
    InvalidNullableAlternatives -> "invalid nullable alternatives"
    InvalidTaggedAlternatives -> "invalid tagged alternatives"
    InvalidTupleShape -> "invalid tuple shape"
    IncompleteIntegerRange -> "integer range needs minimum and maximum"
    IncompleteNumberRange -> "number range needs minimum and maximum"
    ExpectedObjectSchema -> "expected an object schema"
    ExpectedClosedTag -> "expected a closed tag and value"
  }
}

fn describe_unsupported(reason: UnsupportedReason) -> String {
  case reason {
    UnsupportedKeyword(name) -> "unsupported keyword " <> quote(name)
    NestedDialect -> "nested $schema"
    UnsupportedSchemaForm -> "unsupported schema form"
    OpenObject -> "open object"
    ArbitraryUnion -> "untagged union"
    UnboundedArray -> "array without items"
    UnsupportedTupleForm -> "unsupported tuple form"
    UnsupportedTaggedShape -> "unsupported tagged shape"
  }
}

fn quote(text: String) -> String {
  "\"" <> text <> "\""
}

fn path_text(path: List(PathSegment)) -> String {
  list.fold(path, "$", fn(text, segment) {
    case segment {
      Field(name) -> text <> "[" <> quote(name) <> "]"
      Index(index) -> text <> "[" <> int.to_string(index) <> "]"
    }
  })
}

type ParsedSchema {
  ParsedSchema(schema: Tree, invariants: List(InvariantLocation))
}

/// Where a definition mistake found by `from_schema` sits in the document.
type InvariantLocation {
  InvariantLocation(error: DefinitionError, path: List(PathSegment))
}

fn at(path: List(PathSegment), segment: PathSegment) -> List(PathSegment) {
  list.append(path, [segment])
}

fn parse_schema(
  document: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case document {
    // The boolean schema `true` accepts every value, like `{}`.
    value.Bool(True) -> Ok(ParsedSchema(tree.AnySchema, []))
    _ -> parse_schema_object(document, path)
  }
}

fn parse_schema_object(
  document: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use members <- result.try(object_members(document, path))
  let description = list.key_find(members, "description")
  let schema_members = without_member(members, "description")
  use parsed <- result.try(parse_schema_members(schema_members, path))
  case description {
    Error(Nil) -> Ok(parsed)
    Ok(value.String(text)) ->
      Ok(ParsedSchema(
        tree.DescribedSchema(text, parsed.schema),
        parsed.invariants,
      ))
    Ok(_) ->
      Error(MalformedDocument(at(path, Field("description")), ExpectedText))
  }
}

fn parse_schema_members(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case members {
    // `{}`, or only a description: any value.
    [] -> Ok(ParsedSchema(tree.AnySchema, []))
    _ -> parse_constrained(members, path)
  }
}

fn parse_constrained(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use Nil <- result.try(only_members(
    members,
    [
      "type", "enum", "minimum", "maximum", "properties", "required",
      "additionalProperties", "items", "prefixItems", "minItems", "maxItems",
      "anyOf", "oneOf",
    ],
    path,
  ))
  case list.key_find(members, "anyOf") {
    Ok(alternatives) -> {
      use Nil <- result.try(only_members(members, ["anyOf"], path))
      parse_nullable(alternatives, at(path, Field("anyOf")))
    }
    Error(Nil) -> {
      use kind <- result.try(required_member(members, "type", path))
      case kind {
        value.String("string") -> parse_string_schema(members, path)
        value.String("integer") -> parse_integer(members, path)
        value.String("number") -> parse_number_schema(members, path)
        value.String("boolean") ->
          parse_primitive(members, path, tree.BoolSchema)
        value.String("object") -> parse_object_or_union(members, path)
        value.String("array") -> parse_array(members, path)
        value.String(_) ->
          Error(UnsupportedDocument(path, UnsupportedSchemaForm))
        _ -> Error(MalformedDocument(at(path, Field("type")), ExpectedText))
      }
    }
  }
}

fn parse_string_schema(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case list.key_find(members, "enum") {
    Error(Nil) -> parse_primitive(members, path, tree.StringSchema)
    Ok(raw) -> {
      use Nil <- result.try(only_members(members, ["type", "enum"], path))
      let enum_path = at(path, Field("enum"))
      use labels <- result.try(text_items(raw, enum_path))
      let invariants = case labels {
        [] -> [InvariantLocation(codec.EmptyEnum, enum_path)]
        _ ->
          case repeated_at(labels, set.new(), 0) {
            None -> []
            Some(#(label, index)) -> [
              InvariantLocation(
                codec.DuplicateEnumLabel(label),
                at(enum_path, Index(index)),
              ),
            ]
          }
      }
      Ok(ParsedSchema(tree.StringEnumSchema(labels), invariants))
    }
  }
}

fn text_items(
  raw: Value,
  path: List(PathSegment),
) -> Result(List(String), DocumentError) {
  case raw {
    value.Array(items) ->
      list.index_map(items, fn(item, index) { #(item, index) })
      |> list.try_map(fn(pair) {
        case pair.0 {
          value.String(text) -> Ok(text)
          _ -> Error(MalformedDocument(at(path, Index(pair.1)), ExpectedText))
        }
      })
    _ -> Error(MalformedDocument(path, ExpectedArray))
  }
}

/// The first item that repeats an earlier one, with its index. A set keeps
/// this linear in the size of a hostile document.
fn repeated_at(
  items: List(String),
  seen: Set(String),
  index: Int,
) -> Option(#(String, Int)) {
  case items {
    [] -> None
    [item, ..rest] ->
      case set.contains(seen, item) {
        True -> Some(#(item, index))
        False -> repeated_at(rest, set.insert(seen, item), index + 1)
      }
  }
}

fn parse_primitive(
  members: List(#(String, Value)),
  path: List(PathSegment),
  schema: Tree,
) -> Result(ParsedSchema, DocumentError) {
  use Nil <- result.try(only_members(members, ["type"], path))
  Ok(ParsedSchema(schema, []))
}

fn parse_integer(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use Nil <- result.try(only_members(
    members,
    ["type", "minimum", "maximum"],
    path,
  ))
  case list.key_find(members, "minimum"), list.key_find(members, "maximum") {
    Error(Nil), Error(Nil) -> Ok(ParsedSchema(tree.IntSchema, []))
    Ok(minimum), Ok(maximum) -> {
      let minimum_path = at(path, Field("minimum"))
      use minimum <- result.try(expect_integer(minimum, minimum_path))
      use maximum <- result.try(expect_integer(
        maximum,
        at(path, Field("maximum")),
      ))
      let invariants = case minimum > maximum {
        True -> [
          InvariantLocation(
            codec.ReversedIntegerBounds(minimum, maximum),
            minimum_path,
          ),
        ]
        False -> []
      }
      Ok(ParsedSchema(tree.IntegerRangeSchema(minimum, maximum), invariants))
    }
    _, _ -> Error(MalformedDocument(path, IncompleteIntegerRange))
  }
}

fn parse_number_schema(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use Nil <- result.try(only_members(
    members,
    ["type", "minimum", "maximum"],
    path,
  ))
  case list.key_find(members, "minimum"), list.key_find(members, "maximum") {
    Error(Nil), Error(Nil) -> Ok(ParsedSchema(tree.NumberSchema, []))
    Ok(minimum), Ok(maximum) -> {
      let minimum_path = at(path, Field("minimum"))
      use minimum <- result.try(expect_number(minimum, minimum_path))
      use maximum <- result.try(expect_number(
        maximum,
        at(path, Field("maximum")),
      ))
      let invariants = case number.compare(minimum, maximum) {
        order.Gt -> [
          InvariantLocation(
            codec.ReversedNumberBounds(minimum, maximum),
            minimum_path,
          ),
        ]
        _ -> []
      }
      Ok(ParsedSchema(tree.NumberRangeSchema(minimum, maximum), invariants))
    }
    _, _ -> Error(MalformedDocument(path, IncompleteNumberRange))
  }
}

fn parse_object_or_union(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case list.key_find(members, "oneOf") {
    Ok(alternatives) -> {
      use Nil <- result.try(only_members(members, ["type", "oneOf"], path))
      parse_union(alternatives, at(path, Field("oneOf")))
    }
    Error(Nil) -> parse_object(members, path)
  }
}

/// The `properties` and `required` names of a closed object schema.
fn closed_object_parts(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(#(List(#(String, Value)), List(String)), DocumentError) {
  use properties_value <- result.try(required_member(
    members,
    "properties",
    path,
  ))
  use required_value <- result.try(required_member(members, "required", path))
  use additional <- result.try(required_member(
    members,
    "additionalProperties",
    path,
  ))
  use Nil <- result.try(check_closed_object(
    additional,
    at(path, Field("additionalProperties")),
  ))
  use properties <- result.try(object_members(
    properties_value,
    at(path, Field("properties")),
  ))
  let required_path = at(path, Field("required"))
  use required <- result.try(required_names(required_value, required_path))
  let declared =
    set.from_list(list.map(properties, fn(property) { property.0 }))
  use Nil <- result.try(check_declared_required(
    required,
    declared,
    required_path,
    0,
  ))
  Ok(#(properties, required))
}

fn parse_object(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use Nil <- result.try(only_members(
    members,
    ["type", "properties", "required", "additionalProperties"],
    path,
  ))
  use #(properties, required) <- result.try(closed_object_parts(members, path))
  let required = set.from_list(required)
  use parsed <- result.try(
    list.try_map(properties, fn(property) {
      let #(name, raw) = property
      use parsed <- result.map(parse_schema(
        raw,
        at(at(path, Field("properties")), Field(name)),
      ))
      #(
        tree.PropertySchema(name, set.contains(required, name), parsed.schema),
        parsed.invariants,
      )
    }),
  )
  Ok(ParsedSchema(
    tree.ObjectSchema(list.map(parsed, fn(pair) { pair.0 })),
    list.flat_map(parsed, fn(pair) { pair.1 }),
  ))
}

fn parse_array(
  members: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case list.key_find(members, "items"), list.key_find(members, "prefixItems") {
    Ok(items), Error(Nil) -> {
      use Nil <- result.try(only_members(members, ["type", "items"], path))
      use parsed <- result.map(parse_schema(items, at(path, Field("items"))))
      ParsedSchema(tree.ListSchema(parsed.schema), parsed.invariants)
    }
    Error(Nil), Ok(prefix_items) -> parse_tuple(members, prefix_items, path)
    Error(Nil), Error(Nil) -> Error(UnsupportedDocument(path, UnboundedArray))
    Ok(_), Ok(_) -> Error(UnsupportedDocument(path, UnsupportedTupleForm))
  }
}

fn parse_tuple(
  members: List(#(String, Value)),
  prefix_items: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use Nil <- result.try(only_members(
    members,
    ["type", "prefixItems", "minItems", "maxItems"],
    path,
  ))
  use minimum <- result.try(required_member(members, "minItems", path))
  use maximum <- result.try(required_member(members, "maxItems", path))
  use minimum <- result.try(expect_integer(minimum, at(path, Field("minItems"))))
  use maximum <- result.try(expect_integer(maximum, at(path, Field("maxItems"))))
  let items_path = at(path, Field("prefixItems"))
  case prefix_items, minimum, maximum {
    value.Array([first, second]), 2, 2 -> {
      use left <- result.try(parse_schema(first, at(items_path, Index(0))))
      use right <- result.map(parse_schema(second, at(items_path, Index(1))))
      ParsedSchema(
        tree.PairSchema(left.schema, right.schema),
        list.append(left.invariants, right.invariants),
      )
    }
    value.Array(_), _, _ ->
      Error(UnsupportedDocument(path, UnsupportedTupleForm))
    _, _, _ -> Error(MalformedDocument(items_path, ExpectedArray))
  }
}

fn parse_nullable(
  alternatives: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case alternatives {
    value.Array([left, right]) -> {
      let left_path = at(path, Index(0))
      let right_path = at(path, Index(1))
      use left_members <- result.try(object_members(left, left_path))
      use right_members <- result.try(object_members(right, right_path))
      case is_null_schema(left_members), is_null_schema(right_members) {
        True, False -> {
          use parsed <- result.map(parse_schema(right, right_path))
          ParsedSchema(tree.NullableSchema(parsed.schema), parsed.invariants)
        }
        False, True -> {
          use parsed <- result.map(parse_schema(left, left_path))
          ParsedSchema(tree.NullableSchema(parsed.schema), parsed.invariants)
        }
        _, _ -> Error(UnsupportedDocument(path, ArbitraryUnion))
      }
    }
    value.Array(_) -> Error(UnsupportedDocument(path, ArbitraryUnion))
    _ -> Error(MalformedDocument(path, ExpectedArray))
  }
}

fn is_null_schema(members: List(#(String, Value))) -> Bool {
  case members {
    [#("type", value.String("null"))] -> True
    _ -> False
  }
}

fn parse_union(
  alternatives: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case alternatives {
    value.Array([]) -> Error(MalformedDocument(path, InvalidTaggedAlternatives))
    value.Array(items) -> {
      use parsed <- result.try(
        list.index_map(items, fn(item, index) { #(item, index) })
        |> list.try_map(fn(pair) {
          parse_variant(pair.0, at(path, Index(pair.1)))
        }),
      )
      let tags = list.map(parsed, fn(variant) { variant.0.tag })
      let duplicate = case repeated_at(tags, set.new(), 0) {
        None -> []
        Some(#(tag, index)) -> [
          InvariantLocation(
            codec.DuplicateTag(tag),
            at(path, Index(index))
              |> at(Field("properties"))
              |> at(Field("tag"))
              |> at(Field("const")),
          ),
        ]
      }
      Ok(ParsedSchema(
        tree.UnionSchema(list.map(parsed, fn(variant) { variant.0 })),
        list.append(duplicate, list.flat_map(parsed, fn(variant) { variant.1 })),
      ))
    }
    _ -> Error(MalformedDocument(path, ExpectedArray))
  }
}

fn parse_variant(
  alternative: Value,
  path: List(PathSegment),
) -> Result(#(VariantSchema, List(InvariantLocation)), DocumentError) {
  use members <- result.try(object_members(alternative, path))
  use Nil <- result.try(only_members(
    members,
    ["type", "properties", "required", "additionalProperties"],
    path,
  ))
  use kind <- result.try(required_member(members, "type", path))
  use Nil <- result.try(case kind {
    value.String("object") -> Ok(Nil)
    _ -> Error(MalformedDocument(at(path, Field("type")), ExpectedObjectSchema))
  })
  use #(properties, required) <- result.try(closed_object_parts(members, path))
  let properties_path = at(path, Field("properties"))
  use tag <- result.try(case list.key_find(properties, "tag") {
    Ok(tag_schema) -> parse_tag(tag_schema, at(properties_path, Field("tag")))
    Error(Nil) -> Error(MalformedDocument(properties_path, ExpectedClosedTag))
  })
  let names = list.map(properties, fn(property) { property.0 })
  let required_path = at(path, Field("required"))
  case list.key_find(properties, "value"), list.length(names) {
    Ok(payload), 2 -> {
      use Nil <- result.try(case list.sort(required, string.compare) {
        ["tag", "value"] -> Ok(Nil)
        _ -> Error(MalformedDocument(required_path, InvalidTaggedAlternatives))
      })
      use parsed <- result.map(parse_schema(
        payload,
        at(properties_path, Field("value")),
      ))
      #(tree.VariantSchema(tag, Some(parsed.schema)), parsed.invariants)
    }
    Error(Nil), 1 ->
      case required {
        ["tag"] -> Ok(#(tree.VariantSchema(tag, None), []))
        _ -> Error(MalformedDocument(required_path, InvalidTaggedAlternatives))
      }
    _, _ -> Error(UnsupportedDocument(path, UnsupportedTaggedShape))
  }
}

fn parse_tag(
  tag_schema: Value,
  path: List(PathSegment),
) -> Result(String, DocumentError) {
  use members <- result.try(object_members(tag_schema, path))
  use Nil <- result.try(only_members(members, ["const"], path))
  use tag <- result.try(required_member(members, "const", path))
  case tag {
    value.String(text) -> Ok(text)
    _ -> Error(MalformedDocument(at(path, Field("const")), ExpectedText))
  }
}

fn check_closed_object(
  additional: Value,
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  case additional {
    value.Bool(False) -> Ok(Nil)
    value.Bool(True) -> Error(UnsupportedDocument(path, OpenObject))
    _ -> Error(MalformedDocument(path, ExpectedBoolean))
  }
}

fn required_names(
  raw: Value,
  path: List(PathSegment),
) -> Result(List(String), DocumentError) {
  use names <- result.try(text_items(raw, path))
  case repeated_at(names, set.new(), 0) {
    Some(#(name, index)) ->
      Error(MalformedDocument(
        at(path, Index(index)),
        DuplicateRequiredName(name),
      ))
    None -> Ok(names)
  }
}

fn check_declared_required(
  required: List(String),
  declared: Set(String),
  path: List(PathSegment),
  index: Int,
) -> Result(Nil, DocumentError) {
  case required {
    [] -> Ok(Nil)
    [name, ..rest] ->
      case set.contains(declared, name) {
        True -> check_declared_required(rest, declared, path, index + 1)
        False ->
          Error(MalformedDocument(
            at(path, Index(index)),
            UndeclaredRequiredName(name),
          ))
      }
  }
}

fn expect_integer(
  raw: Value,
  path: List(PathSegment),
) -> Result(Int, DocumentError) {
  case raw {
    value.Number(found) ->
      // The parse limits bound a number to 800 digits and exponent 1,200.
      number.to_int(found, 2000)
      |> result.replace_error(MalformedDocument(path, ExpectedInteger))
    _ -> Error(MalformedDocument(path, ExpectedInteger))
  }
}

fn expect_number(
  raw: Value,
  path: List(PathSegment),
) -> Result(Number, DocumentError) {
  case raw {
    value.Number(found) -> Ok(found)
    _ -> Error(MalformedDocument(path, ExpectedNumber))
  }
}

fn object_members(
  raw: Value,
  path: List(PathSegment),
) -> Result(List(#(String, Value)), DocumentError) {
  case raw {
    value.Object(members) ->
      case
        repeated_at(list.map(members, fn(member) { member.0 }), set.new(), 0)
      {
        Some(#(name, _)) ->
          Error(MalformedDocument(at(path, Field(name)), DuplicateKey(name)))
        None -> Ok(members)
      }
    _ -> Error(MalformedDocument(path, ExpectedObject))
  }
}

fn only_members(
  members: List(#(String, Value)),
  allowed: List(String),
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  list.try_each(members, fn(member) {
    case member.0 {
      "$schema" ->
        Error(UnsupportedDocument(at(path, Field("$schema")), NestedDialect))
      name ->
        case list.contains(allowed, name) {
          True -> Ok(Nil)
          False ->
            Error(UnsupportedDocument(
              at(path, Field(name)),
              UnsupportedKeyword(name),
            ))
        }
    }
  })
}

fn required_member(
  members: List(#(String, Value)),
  name: String,
  path: List(PathSegment),
) -> Result(Value, DocumentError) {
  list.key_find(members, name)
  |> result.replace_error(MalformedDocument(
    at(path, Field(name)),
    MissingKeyword(name),
  ))
}

fn without_member(
  members: List(#(String, Value)),
  name: String,
) -> List(#(String, Value)) {
  list.filter(members, fn(member) { member.0 != name })
}

fn invariant_path(
  error: DefinitionError,
  locations: List(InvariantLocation),
) -> List(PathSegment) {
  case list.find(locations, fn(location) { location.error == error }) {
    Ok(location) -> location.path
    Error(Nil) -> []
  }
}
