import gleam/list
import json/blueprint/codec.{type Schema}
import json/blueprint/number.{type Number}
import json/blueprint/runtime.{type ContractError, type RuntimeContract}
import json/blueprint/value.{type Value}

const draft_2020_12 = "https://json-schema.org/draft/2020-12/schema"

pub type PathSegment {
  Property(String)
  Index(Int)
}

pub type MalformedReason {
  ExpectedObject
  ExpectedText
  ExpectedInteger
  ExpectedNumber
  ExpectedBoolean
  ExpectedArray
  MissingField(String)
  DuplicateKey(String)
  DuplicateRequiredName(String)
  UndeclaredRequiredName(String)
  InvalidNullableAlternatives
  InvalidTaggedAlternatives
  InvalidTupleShape
  IncompleteIntegerRange
  IncompleteNumberRange
  ExpectedObjectSchema
  ExpectedClosedTag
}

pub type UnsupportedReason {
  UnsupportedKeyword(String)
  NestedDialect
  UnsupportedSchemaForm
  OpenObject
  ArbitraryUnion
  UnboundedArray
  UnsupportedTupleForm
  UnsupportedTaggedShape
}

pub type DocumentError {
  MalformedDocument(path: List(PathSegment), reason: MalformedReason)
  UnsupportedDocument(path: List(PathSegment), reason: UnsupportedReason)
  UnsupportedDialect(path: List(PathSegment), actual: String)
  SchemaInvariant(path: List(PathSegment), reason: ContractError)
}

type Maybe(a) {
  Nothing
  Something(a)
}

type ParsedSchema {
  ParsedSchema(schema: Schema, invariants: List(InvariantLocation))
}

type InvariantLocation {
  InvariantLocation(reason: ContractError, path: List(PathSegment))
}

pub fn load(document: Value) -> Result(RuntimeContract, DocumentError) {
  use fields <- bind(object_fields(document, []))
  use dialect <- bind(required_field(fields, "$schema", []))
  case dialect {
    value.String(actual) if actual == draft_2020_12 -> {
      let schema_fields = without_field(fields, "$schema")
      use parsed <- bind(parse_schema(value.Object(schema_fields), []))
      case runtime.from_schema(parsed.schema) {
        Ok(contract) -> Ok(contract)
        Error(reason) ->
          Error(SchemaInvariant(
            invariant_path(reason, parsed.invariants),
            reason,
          ))
      }
    }
    value.String(actual) ->
      Error(UnsupportedDialect([Property("$schema")], actual))
    _ -> Error(MalformedDocument([Property("$schema")], ExpectedText))
  }
}

fn parse_schema(
  document: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use fields <- bind(object_fields(document, path))
  use _ <- bind(known_schema_keywords(fields, path))
  case lookup(fields, "anyOf") {
    Something(alternatives) -> {
      use _ <- bind(only_fields(fields, ["anyOf"], path))
      parse_nullable(alternatives, append_path(path, Property("anyOf")))
    }
    Nothing -> {
      use kind <- bind(required_field(fields, "type", path))
      case kind {
        value.String("string") -> parse_string_schema(fields, path)
        value.String("integer") -> parse_integer(fields, path)
        value.String("number") -> parse_number_schema(fields, path)
        value.String("boolean") ->
          parse_primitive(fields, path, codec.BoolSchema)
        value.String("object") -> parse_object_or_tagged(fields, path)
        value.String("array") -> parse_array(fields, path)
        value.String(_) ->
          Error(UnsupportedDocument(path, UnsupportedSchemaForm))
        _ ->
          Error(MalformedDocument(
            append_path(path, Property("type")),
            ExpectedText,
          ))
      }
    }
  }
}

fn known_schema_keywords(
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  check_known_keywords(
    fields,
    [
      "type",
      "enum",
      "minimum",
      "maximum",
      "properties",
      "required",
      "additionalProperties",
      "items",
      "prefixItems",
      "minItems",
      "maxItems",
      "anyOf",
      "oneOf",
    ],
    path,
  )
}

fn parse_string_schema(
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case lookup(fields, "enum") {
    Nothing -> parse_primitive(fields, path, codec.StringSchema)
    Something(raw) -> {
      use _ <- bind(only_fields(fields, ["type", "enum"], path))
      let enum_path = append_path(path, Property("enum"))
      use labels <- bind(parse_enum_labels(raw, enum_path))
      let invariants = case labels {
        [] -> [InvariantLocation(runtime.EmptyStringEnum, enum_path)]
        [_, ..] ->
          case duplicate_enum_label(labels, [], 0) {
            Nothing -> []
            Something(#(label, index)) -> [
              InvariantLocation(
                runtime.DuplicateSchemaEnumLabel(label),
                append_path(enum_path, Index(index)),
              ),
            ]
          }
      }
      Ok(ParsedSchema(codec.StringEnumSchema(labels), invariants))
    }
  }
}

fn parse_enum_labels(
  raw: Value,
  path: List(PathSegment),
) -> Result(List(String), DocumentError) {
  case raw {
    value.Array(items) -> parse_enum_label_items(items, path, 0, [])
    _ -> Error(MalformedDocument(path, ExpectedArray))
  }
}

fn parse_enum_label_items(
  items: List(Value),
  path: List(PathSegment),
  index: Int,
  reversed: List(String),
) -> Result(List(String), DocumentError) {
  case items {
    [] -> Ok(list.reverse(reversed))
    [value.String(label), ..rest] ->
      parse_enum_label_items(rest, path, index + 1, [label, ..reversed])
    [_, ..] ->
      Error(MalformedDocument(append_path(path, Index(index)), ExpectedText))
  }
}

fn duplicate_enum_label(
  labels: List(String),
  seen: List(String),
  index: Int,
) -> Maybe(#(String, Int)) {
  case labels {
    [] -> Nothing
    [label, ..rest] ->
      case list.contains(seen, label) {
        True -> Something(#(label, index))
        False -> duplicate_enum_label(rest, [label, ..seen], index + 1)
      }
  }
}

fn check_known_keywords(
  fields: List(#(String, Value)),
  known: List(String),
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  case fields {
    [] -> Ok(Nil)
    [#("$schema", _), ..] ->
      Error(UnsupportedDocument(
        append_path(path, Property("$schema")),
        NestedDialect,
      ))
    [#(name, _), ..rest] ->
      case list.contains(known, name) {
        True -> check_known_keywords(rest, known, path)
        False ->
          Error(UnsupportedDocument(
            append_path(path, Property(name)),
            UnsupportedKeyword(name),
          ))
      }
  }
}

fn parse_primitive(
  fields: List(#(String, Value)),
  path: List(PathSegment),
  schema: Schema,
) -> Result(ParsedSchema, DocumentError) {
  use _ <- bind(only_fields(fields, ["type"], path))
  Ok(ParsedSchema(schema, []))
}

fn parse_integer(
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use _ <- bind(only_fields(fields, ["type", "minimum", "maximum"], path))
  case lookup(fields, "minimum"), lookup(fields, "maximum") {
    Nothing, Nothing -> Ok(ParsedSchema(codec.IntSchema, []))
    Something(minimum), Something(maximum) -> {
      use min_val <- bind(expect_integer(
        minimum,
        append_path(path, Property("minimum")),
      ))
      use max_val <- bind(expect_integer(
        maximum,
        append_path(path, Property("maximum")),
      ))
      let schema = codec.IntegerRangeSchema(min_val, max_val)
      let invariants = case min_val > max_val {
        True -> [
          InvariantLocation(
            runtime.ReversedIntegerRange(min_val, max_val),
            append_path(path, Property("minimum")),
          ),
        ]
        False -> []
      }
      Ok(ParsedSchema(schema, invariants))
    }
    _, _ -> Error(MalformedDocument(path, IncompleteIntegerRange))
  }
}

fn parse_number_schema(
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use _ <- bind(only_fields(fields, ["type", "minimum", "maximum"], path))
  case lookup(fields, "minimum"), lookup(fields, "maximum") {
    Nothing, Nothing -> Ok(ParsedSchema(codec.NumberSchema, []))
    Something(minimum), Something(maximum) -> {
      use min_val <- bind(expect_number(
        minimum,
        append_path(path, Property("minimum")),
      ))
      use max_val <- bind(expect_number(
        maximum,
        append_path(path, Property("maximum")),
      ))
      let schema = codec.NumberRangeSchema(min_val, max_val)
      let invariants = case number.compare(min_val, max_val) {
        number.GreaterThan -> [
          InvariantLocation(
            runtime.ReversedNumberRange(min_val, max_val),
            append_path(path, Property("minimum")),
          ),
        ]
        _ -> []
      }
      Ok(ParsedSchema(schema, invariants))
    }
    _, _ -> Error(MalformedDocument(path, IncompleteNumberRange))
  }
}

fn parse_object_or_tagged(
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case lookup(fields, "oneOf") {
    Something(alternatives) -> {
      use _ <- bind(only_fields(fields, ["type", "oneOf"], path))
      parse_tagged(alternatives, append_path(path, Property("oneOf")))
    }
    Nothing -> parse_object(fields, path)
  }
}

fn parse_object(
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use _ <- bind(only_fields(
    fields,
    ["type", "properties", "required", "additionalProperties"],
    path,
  ))
  use properties_value <- bind(required_field(fields, "properties", path))
  use required_value <- bind(required_field(fields, "required", path))
  use additional <- bind(required_field(fields, "additionalProperties", path))
  use _ <- bind(check_closed_object(
    additional,
    append_path(path, Property("additionalProperties")),
  ))
  use properties <- bind(object_fields(
    properties_value,
    append_path(path, Property("properties")),
  ))
  use required <- bind(required_names(
    required_value,
    append_path(path, Property("required")),
  ))
  use _ <- bind(check_declared_required(
    required,
    properties,
    append_path(path, Property("required")),
    0,
  ))
  use parsed <- bind(parse_properties(
    properties,
    required,
    append_path(path, Property("properties")),
  ))
  Ok(ParsedSchema(codec.ObjectSchema(parsed.0), parsed.1))
}

fn parse_properties(
  properties: List(#(String, Value)),
  required: List(String),
  path: List(PathSegment),
) -> Result(
  #(List(codec.PropertySchema), List(InvariantLocation)),
  DocumentError,
) {
  case properties {
    [] -> Ok(#([], []))
    [#(name, raw), ..rest] -> {
      use parsed <- bind(parse_schema(raw, append_path(path, Property(name))))
      use tail <- bind(parse_properties(rest, required, path))
      Ok(#(
        [
          codec.PropertySchema(
            name,
            list.contains(required, name),
            parsed.schema,
          ),
          ..tail.0
        ],
        append_locations(parsed.invariants, tail.1),
      ))
    }
  }
}

fn parse_array(
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case lookup(fields, "items"), lookup(fields, "prefixItems") {
    Something(items), Nothing -> {
      use _ <- bind(only_fields(fields, ["type", "items"], path))
      use parsed <- bind(parse_schema(
        items,
        append_path(path, Property("items")),
      ))
      Ok(ParsedSchema(codec.ListSchema(parsed.schema), parsed.invariants))
    }
    Nothing, Something(prefix_items) -> parse_tuple(fields, prefix_items, path)
    Nothing, Nothing -> Error(UnsupportedDocument(path, UnboundedArray))
    Something(_), Something(_) ->
      Error(UnsupportedDocument(path, UnsupportedTupleForm))
  }
}

fn parse_tuple(
  fields: List(#(String, Value)),
  prefix_items: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  use _ <- bind(only_fields(
    fields,
    ["type", "prefixItems", "minItems", "maxItems"],
    path,
  ))
  use minimum <- bind(required_field(fields, "minItems", path))
  use maximum <- bind(required_field(fields, "maxItems", path))
  use minimum <- bind(expect_integer(
    minimum,
    append_path(path, Property("minItems")),
  ))
  use maximum <- bind(expect_integer(
    maximum,
    append_path(path, Property("maxItems")),
  ))
  case prefix_items, minimum, maximum {
    value.Array([first, second]), 2, 2 -> {
      use left <- bind(parse_schema(
        first,
        append_path(append_path(path, Property("prefixItems")), Index(0)),
      ))
      use right <- bind(parse_schema(
        second,
        append_path(append_path(path, Property("prefixItems")), Index(1)),
      ))
      Ok(ParsedSchema(
        codec.PairSchema(left.schema, right.schema),
        append_locations(left.invariants, right.invariants),
      ))
    }
    value.Array(_), _, _ ->
      Error(UnsupportedDocument(path, UnsupportedTupleForm))
    _, _, _ ->
      Error(MalformedDocument(
        append_path(path, Property("prefixItems")),
        ExpectedArray,
      ))
  }
}

fn parse_nullable(
  alternatives: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case alternatives {
    value.Array([left, right]) -> {
      let left_path = append_path(path, Index(0))
      let right_path = append_path(path, Index(1))
      use left_fields <- bind(object_fields(left, left_path))
      use right_fields <- bind(object_fields(right, right_path))
      case is_null_schema(left_fields), is_null_schema(right_fields) {
        True, False -> {
          use parsed <- bind(parse_schema(right, right_path))
          Ok(ParsedSchema(
            codec.NullableSchema(parsed.schema),
            parsed.invariants,
          ))
        }
        False, True -> {
          use parsed <- bind(parse_schema(left, left_path))
          Ok(ParsedSchema(
            codec.NullableSchema(parsed.schema),
            parsed.invariants,
          ))
        }
        _, _ -> Error(UnsupportedDocument(path, ArbitraryUnion))
      }
    }
    value.Array(_) -> Error(UnsupportedDocument(path, ArbitraryUnion))
    _ -> Error(MalformedDocument(path, ExpectedArray))
  }
}

fn is_null_schema(fields: List(#(String, Value))) -> Bool {
  case fields {
    [#("type", value.String("null"))] -> True
    _ -> False
  }
}

fn parse_tagged(
  alternatives: Value,
  path: List(PathSegment),
) -> Result(ParsedSchema, DocumentError) {
  case alternatives {
    value.Array([left, right]) -> {
      let left_path = append_path(path, Index(0))
      let right_path = append_path(path, Index(1))
      use parsed_left <- bind(parse_tagged_alternative(left, left_path))
      use parsed_right <- bind(parse_tagged_alternative(right, right_path))
      let duplicate = case parsed_left.0 == parsed_right.0 {
        True -> [
          InvariantLocation(
            runtime.DuplicateSchemaTag(parsed_left.0),
            append_path(
              append_path(
                append_path(right_path, Property("properties")),
                Property("tag"),
              ),
              Property("const"),
            ),
          ),
        ]
        False -> []
      }
      Ok(ParsedSchema(
        codec.TaggedSchema(
          parsed_left.0,
          parsed_left.1.schema,
          parsed_right.0,
          parsed_right.1.schema,
        ),
        append_locations(
          duplicate,
          append_locations(parsed_left.1.invariants, parsed_right.1.invariants),
        ),
      ))
    }
    value.Array(_) -> Error(MalformedDocument(path, InvalidTaggedAlternatives))
    _ -> Error(MalformedDocument(path, ExpectedArray))
  }
}

fn parse_tagged_alternative(
  alternative: Value,
  path: List(PathSegment),
) -> Result(#(String, ParsedSchema), DocumentError) {
  use fields <- bind(object_fields(alternative, path))
  use _ <- bind(only_fields(
    fields,
    ["type", "properties", "required", "additionalProperties"],
    path,
  ))
  use kind <- bind(required_field(fields, "type", path))
  use _ <- bind(check_object_kind(kind, append_path(path, Property("type"))))
  use properties_value <- bind(required_field(fields, "properties", path))
  use required_value <- bind(required_field(fields, "required", path))
  use additional <- bind(required_field(fields, "additionalProperties", path))
  use _ <- bind(check_closed_object(
    additional,
    append_path(path, Property("additionalProperties")),
  ))
  let properties_path = append_path(path, Property("properties"))
  use properties <- bind(object_fields(properties_value, properties_path))
  use required <- bind(required_names(
    required_value,
    append_path(path, Property("required")),
  ))
  use _ <- bind(check_declared_required(
    required,
    properties,
    append_path(path, Property("required")),
    0,
  ))
  case lookup(properties, "tag"), lookup(properties, "value") {
    Something(tag_schema), Something(payload_schema) -> {
      use _ <- bind(check_tag_properties(properties, path))
      use _ <- bind(check_tag_required(
        required,
        append_path(path, Property("required")),
      ))
      let tag_path = append_path(properties_path, Property("tag"))
      let payload_path = append_path(properties_path, Property("value"))
      use tag_fields <- bind(object_fields(tag_schema, tag_path))
      use _ <- bind(only_fields(tag_fields, ["const"], tag_path))
      use tag_value <- bind(required_field(tag_fields, "const", tag_path))
      use tag <- bind(expect_text(
        tag_value,
        append_path(tag_path, Property("const")),
      ))
      use parsed_payload <- bind(parse_schema(payload_schema, payload_path))
      Ok(#(tag, parsed_payload))
    }
    _, _ -> Error(MalformedDocument(properties_path, ExpectedClosedTag))
  }
}

fn check_tag_required(
  required: List(String),
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  case
    list.contains(required, "tag"),
    list.contains(required, "value"),
    list.length(required)
  {
    True, True, 2 -> Ok(Nil)
    _, _, _ -> Error(MalformedDocument(path, InvalidTaggedAlternatives))
  }
}

fn check_tag_properties(
  properties: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  case list.length(properties) {
    2 -> Ok(Nil)
    _ -> Error(UnsupportedDocument(path, UnsupportedTaggedShape))
  }
}

fn check_object_kind(
  kind: Value,
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  case kind {
    value.String("object") -> Ok(Nil)
    _ -> Error(MalformedDocument(path, ExpectedObjectSchema))
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
  val: Value,
  path: List(PathSegment),
) -> Result(List(String), DocumentError) {
  case val {
    value.Array(items) -> parse_required_names(items, path, 0, [])
    _ -> Error(MalformedDocument(path, ExpectedArray))
  }
}

fn parse_required_names(
  items: List(Value),
  path: List(PathSegment),
  index: Int,
  seen: List(String),
) -> Result(List(String), DocumentError) {
  case items {
    [] -> Ok(list.reverse(seen))
    [value.String(name), ..rest] -> {
      let item_path = append_path(path, Index(index))
      case list.contains(seen, name) {
        True -> Error(MalformedDocument(item_path, DuplicateRequiredName(name)))
        False -> parse_required_names(rest, path, index + 1, [name, ..seen])
      }
    }
    [_, ..] ->
      Error(MalformedDocument(append_path(path, Index(index)), ExpectedText))
  }
}

fn check_declared_required(
  required: List(String),
  properties: List(#(String, Value)),
  path: List(PathSegment),
  index: Int,
) -> Result(Nil, DocumentError) {
  case required {
    [] -> Ok(Nil)
    [name, ..rest] ->
      case has_key(properties, name) {
        True -> check_declared_required(rest, properties, path, index + 1)
        False ->
          Error(MalformedDocument(
            append_path(path, Index(index)),
            UndeclaredRequiredName(name),
          ))
      }
  }
}

fn expect_integer(
  val: Value,
  path: List(PathSegment),
) -> Result(Int, DocumentError) {
  case val {
    value.Number(num) -> {
      let assert Ok(limit) = number.integer_projection_limit(24)
      case number.to_int_exact(num, limit) {
        Ok(integer) -> Ok(integer)
        Error(_) -> Error(MalformedDocument(path, ExpectedInteger))
      }
    }
    _ -> Error(MalformedDocument(path, ExpectedInteger))
  }
}

fn expect_number(
  val: Value,
  path: List(PathSegment),
) -> Result(Number, DocumentError) {
  case val {
    value.Number(num) -> Ok(num)
    _ -> Error(MalformedDocument(path, ExpectedNumber))
  }
}

fn expect_text(
  val: Value,
  path: List(PathSegment),
) -> Result(String, DocumentError) {
  case val {
    value.String(text) -> Ok(text)
    _ -> Error(MalformedDocument(path, ExpectedText))
  }
}

fn object_fields(
  val: Value,
  path: List(PathSegment),
) -> Result(List(#(String, Value)), DocumentError) {
  case val {
    value.Object(fields) -> check_duplicate_keys(fields, path, [])
    _ -> Error(MalformedDocument(path, ExpectedObject))
  }
}

fn check_duplicate_keys(
  fields: List(#(String, Value)),
  path: List(PathSegment),
  seen: List(String),
) -> Result(List(#(String, Value)), DocumentError) {
  case fields {
    [] -> Ok([])
    [#(name, val), ..rest] -> {
      let key_path = append_path(path, Property(name))
      case list.contains(seen, name) {
        True -> Error(MalformedDocument(key_path, DuplicateKey(name)))
        False -> {
          use checked <- bind(check_duplicate_keys(rest, path, [name, ..seen]))
          Ok([#(name, val), ..checked])
        }
      }
    }
  }
}

fn only_fields(
  fields: List(#(String, Value)),
  allowed: List(String),
  path: List(PathSegment),
) -> Result(Nil, DocumentError) {
  case fields {
    [] -> Ok(Nil)
    [#("$schema", _), ..] ->
      Error(UnsupportedDocument(
        append_path(path, Property("$schema")),
        NestedDialect,
      ))
    [#(name, _), ..rest] ->
      case list.contains(allowed, name) {
        True -> only_fields(rest, allowed, path)
        False ->
          Error(UnsupportedDocument(
            append_path(path, Property(name)),
            UnsupportedKeyword(name),
          ))
      }
  }
}

fn required_field(
  fields: List(#(String, Value)),
  name: String,
  path: List(PathSegment),
) -> Result(Value, DocumentError) {
  case lookup(fields, name) {
    Something(val) -> Ok(val)
    Nothing ->
      Error(MalformedDocument(
        append_path(path, Property(name)),
        MissingField(name),
      ))
  }
}

fn lookup(fields: List(#(String, Value)), name: String) -> Maybe(Value) {
  case fields {
    [] -> Nothing
    [#(key, val), ..rest] ->
      case key == name {
        True -> Something(val)
        False -> lookup(rest, name)
      }
  }
}

fn without_field(
  fields: List(#(String, Value)),
  name: String,
) -> List(#(String, Value)) {
  case fields {
    [] -> []
    [#(key, val), ..rest] ->
      case key == name {
        True -> without_field(rest, name)
        False -> [#(key, val), ..without_field(rest, name)]
      }
  }
}

fn has_key(fields: List(#(String, Value)), name: String) -> Bool {
  case fields {
    [] -> False
    [#(key, _), ..rest] -> key == name || has_key(rest, name)
  }
}

fn append_path(
  path: List(PathSegment),
  segment: PathSegment,
) -> List(PathSegment) {
  list.append(path, [segment])
}

fn append_locations(
  left: List(InvariantLocation),
  right: List(InvariantLocation),
) -> List(InvariantLocation) {
  list.append(left, right)
}

fn invariant_path(
  reason: ContractError,
  locations: List(InvariantLocation),
) -> List(PathSegment) {
  case locations {
    [] -> []
    [InvariantLocation(candidate, path), ..rest] ->
      case same_contract_error(reason, candidate) {
        True -> path
        False -> invariant_path(reason, rest)
      }
  }
}

fn same_contract_error(left: ContractError, right: ContractError) -> Bool {
  case left, right {
    runtime.UnknownSchema, runtime.UnknownSchema -> True
    runtime.ReversedIntegerRange(left_min, left_max),
      runtime.ReversedIntegerRange(right_min, right_max)
    -> left_min == right_min && left_max == right_max
    runtime.ReversedNumberRange(left_min, left_max),
      runtime.ReversedNumberRange(right_min, right_max)
    ->
      number.compare(left_min, right_min) == number.EqualTo
      && number.compare(left_max, right_max) == number.EqualTo
    runtime.DuplicateSchemaProperty(left_name),
      runtime.DuplicateSchemaProperty(right_name)
    -> left_name == right_name
    runtime.DuplicateSchemaTag(left_tag), runtime.DuplicateSchemaTag(right_tag)
    -> left_tag == right_tag
    runtime.EmptyStringEnum, runtime.EmptyStringEnum -> True
    runtime.DuplicateSchemaEnumLabel(left_label),
      runtime.DuplicateSchemaEnumLabel(right_label)
    -> left_label == right_label
    _, _ -> False
  }
}

fn bind(
  result: Result(a, DocumentError),
  next: fn(a) -> Result(b, DocumentError),
) -> Result(b, DocumentError) {
  case result {
    Error(error) -> Error(error)
    Ok(val) -> next(val)
  }
}
