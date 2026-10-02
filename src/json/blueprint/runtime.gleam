//// Runtime contracts: validation of a parsed `Value` against a codec schema,
//// and decoding of validated values.
////
//// `from_codec` and `from_schema` check a schema for contradictions, such as
//// a reversed range or a duplicate property, and return a `RuntimeContract`.
//// `document.load` builds the same contract from a schema document.
//// `validate` checks a `Value` and returns a `ValidatedValue` or a
//// `ValidationError` with the path of the first failure. `decode` decodes a
//// validated value with a codec whose schema has the same shape, and fails
//// otherwise.
////
//// Use this module when a value must be checked against a schema that
//// arrives at runtime, or before choosing which codec decodes it. To decode
//// JSON text with a known codec, `codec.decode_json` is enough.
////
//// ```gleam
//// import json/blueprint/codec
//// import json/blueprint/parser
//// import json/blueprint/runtime
////
//// pub fn example() {
////   let names = codec.list(codec.string())
////   let assert Ok(contract) = runtime.from_codec(names)
////   let assert Ok(parsed) =
////     parser.parse_value_from_string(parser.default_limits(), "[\"a\"]")
////   let assert Ok(validated) = runtime.validate(contract, parsed)
////   let assert Ok(["a"]) = runtime.decode(names, validated)
//// }
//// ```

import gleam/list
import gleam/order
import gleam/string
import json/blueprint/codec.{
  type Codec, type DecodeError, type PropertySchema, type Schema,
}
import json/blueprint/number.{type Number}
import json/blueprint/value.{type Value}

pub opaque type RuntimeContract {
  RuntimeContract(schema: Schema)
}

pub opaque type ValidatedValue {
  ValidatedValue(value: Value, schema: Schema)
}

pub type ContractError {
  UnknownSchema
  ReversedIntegerRange(minimum: Int, maximum: Int)
  ReversedNumberRange(minimum: Number, maximum: Number)
  DuplicateSchemaProperty(String)
  DuplicateSchemaTag(String)
  EmptyStringEnum
  DuplicateSchemaEnumLabel(String)
}

pub fn from_schema(schema: Schema) -> Result(RuntimeContract, ContractError) {
  case normalize(schema) {
    Error(error) -> Error(error)
    Ok(normalized) -> Ok(RuntimeContract(normalized))
  }
}

pub fn from_codec(codec: Codec(a)) -> Result(RuntimeContract, ContractError) {
  case codec.schema(codec) {
    Error(codec.UnknownSchema) -> Error(UnknownSchema)
    Ok(s) -> from_schema(s)
  }
}

pub fn schema(contract: RuntimeContract) -> Schema {
  contract.schema
}

pub type PathSegment {
  Property(String)
  Index(Int)
  TaggedBranch(String)
}

pub type ValidationReason {
  ExpectedString
  UnknownEnumLabel(String)
  ExpectedInteger
  ExpectedNumber
  ExpectedBoolean
  ExpectedArray
  ExpectedObject
  MissingProperty(String)
  UnknownProperty(String)
  DuplicateProperty(String)
  WrongTupleLength(expected: Int, actual: Int)
  IntegerOutsideRange(minimum: Int, maximum: Int, actual: Int)
  NumberOutsideRange(minimum: Number, maximum: Number, actual: Number)
  MissingTag
  NonStringTag
  UnknownTag(String)
}

pub type ValidationError {
  ValidationError(path: List(PathSegment), reason: ValidationReason)
}

pub fn validate(
  contract: RuntimeContract,
  value: Value,
) -> Result(ValidatedValue, ValidationError) {
  case validate_at(contract.schema, value, []) {
    Error(error) -> Error(error)
    Ok(Nil) -> Ok(ValidatedValue(value, contract.schema))
  }
}

pub fn encoded(value: ValidatedValue) -> Value {
  value.value
}

pub fn matches(contract: RuntimeContract, value: ValidatedValue) -> Bool {
  validation_shape(contract.schema) == validation_shape(value.schema)
}

pub fn same_schema(left: RuntimeContract, right: RuntimeContract) -> Bool {
  validation_shape(left.schema) == validation_shape(right.schema)
}

fn validation_shape(schema: Schema) -> Schema {
  case schema {
    codec.DescribedSchema(_, inner) -> validation_shape(inner)
    codec.PairSchema(left, right) ->
      codec.PairSchema(validation_shape(left), validation_shape(right))
    codec.FieldSchema(name, inner) ->
      codec.FieldSchema(name, validation_shape(inner))
    codec.ListSchema(inner) -> codec.ListSchema(validation_shape(inner))
    codec.NullableSchema(inner) -> codec.NullableSchema(validation_shape(inner))
    codec.ObjectSchema(properties) ->
      codec.ObjectSchema(
        list.map(properties, fn(property) {
          codec.PropertySchema(
            ..property,
            schema: validation_shape(property.schema),
          )
        }),
      )
    codec.TaggedSchema(left_tag, left, right_tag, right) ->
      codec.TaggedSchema(
        left_tag,
        validation_shape(left),
        right_tag,
        validation_shape(right),
      )
    codec.StringSchema -> codec.StringSchema
    codec.StringEnumSchema(labels) -> codec.StringEnumSchema(labels)
    codec.IntSchema -> codec.IntSchema
    codec.NumberSchema -> codec.NumberSchema
    codec.BoolSchema -> codec.BoolSchema
    codec.IntegerRangeSchema(minimum, maximum) ->
      codec.IntegerRangeSchema(minimum, maximum)
    codec.NumberRangeSchema(minimum, maximum) ->
      codec.NumberRangeSchema(minimum, maximum)
  }
}

pub fn decode(
  target_codec: Codec(a),
  value: ValidatedValue,
) -> Result(a, DecodeError) {
  case from_codec(target_codec) {
    Error(_) ->
      Error(codec.CannotDecode(codec.CustomDecodeReason("Schema mismatch")))
    Ok(contract) ->
      case matches(contract, value) {
        False ->
          Error(codec.CannotDecode(codec.CustomDecodeReason("Schema mismatch")))
        True -> codec.decode(target_codec, encoded(value))
      }
  }
}

type Maybe(a) {
  Nothing
  Something(a)
}

fn normalize(schema: Schema) -> Result(Schema, ContractError) {
  case schema {
    codec.DescribedSchema(description, codec.DescribedSchema(_, inner)) ->
      normalize(codec.DescribedSchema(description, inner))
    codec.DescribedSchema(description, inner) -> {
      use normalized <- bind(normalize(inner))
      Ok(codec.DescribedSchema(description, normalized))
    }
    codec.StringSchema -> Ok(codec.StringSchema)
    codec.StringEnumSchema(labels) -> normalize_string_enum(labels)
    codec.IntSchema -> Ok(codec.IntSchema)
    codec.NumberSchema -> Ok(codec.NumberSchema)
    codec.BoolSchema -> Ok(codec.BoolSchema)
    codec.PairSchema(left, right) -> {
      use normalized_left <- bind(normalize(left))
      use normalized_right <- bind(normalize(right))
      Ok(codec.PairSchema(normalized_left, normalized_right))
    }
    codec.FieldSchema(name, inner) -> {
      use normalized_inner <- bind(normalize(inner))
      Ok(
        codec.ObjectSchema([
          codec.PropertySchema(name, True, normalized_inner),
        ]),
      )
    }
    codec.ListSchema(inner) -> {
      use normalized <- bind(normalize(inner))
      Ok(codec.ListSchema(normalized))
    }
    codec.NullableSchema(inner) -> {
      use normalized <- bind(normalize(inner))
      Ok(codec.NullableSchema(normalized))
    }
    codec.ObjectSchema(properties) -> normalize_object(properties)
    codec.TaggedSchema(left_tag, left, right_tag, right) ->
      normalize_tagged(left_tag, left, right_tag, right)
    codec.IntegerRangeSchema(minimum, maximum) ->
      case minimum <= maximum {
        True -> Ok(codec.IntegerRangeSchema(minimum, maximum))
        False -> Error(ReversedIntegerRange(minimum, maximum))
      }
    codec.NumberRangeSchema(minimum, maximum) ->
      case number.compare(minimum, maximum) {
        number.GreaterThan -> Error(ReversedNumberRange(minimum, maximum))
        _ -> Ok(codec.NumberRangeSchema(minimum, maximum))
      }
  }
}

fn normalize_string_enum(
  labels: List(String),
) -> Result(Schema, ContractError) {
  case labels {
    [] -> Error(EmptyStringEnum)
    [_, ..] ->
      case find_duplicate_string(labels, []) {
        Something(label) -> Error(DuplicateSchemaEnumLabel(label))
        Nothing -> Ok(codec.StringEnumSchema(list.sort(labels, string.compare)))
      }
  }
}

fn find_duplicate_string(
  labels: List(String),
  seen: List(String),
) -> Maybe(String) {
  case labels {
    [] -> Nothing
    [label, ..rest] ->
      case list.contains(seen, label) {
        True -> Something(label)
        False -> find_duplicate_string(rest, [label, ..seen])
      }
  }
}

fn normalize_object(
  properties: List(PropertySchema),
) -> Result(Schema, ContractError) {
  case find_duplicate_property_name(properties, []) {
    Something(name) -> Error(DuplicateSchemaProperty(name))
    Nothing -> {
      use normalized <- bind(normalize_properties(properties))
      let sorted =
        list.sort(normalized, fn(a, b) {
          let codec.PropertySchema(a_name, _, _) = a
          let codec.PropertySchema(b_name, _, _) = b
          string.compare(a_name, b_name)
        })
      Ok(codec.ObjectSchema(sorted))
    }
  }
}

fn normalize_properties(
  properties: List(PropertySchema),
) -> Result(List(PropertySchema), ContractError) {
  case properties {
    [] -> Ok([])
    [codec.PropertySchema(name, required, prop_schema), ..rest] -> {
      use normalized_schema <- bind(normalize(prop_schema))
      use normalized_rest <- bind(normalize_properties(rest))
      Ok([
        codec.PropertySchema(name, required, normalized_schema),
        ..normalized_rest
      ])
    }
  }
}

fn find_duplicate_property_name(
  properties: List(PropertySchema),
  seen: List(String),
) -> Maybe(String) {
  case properties {
    [] -> Nothing
    [codec.PropertySchema(name, _, _), ..rest] ->
      case list.contains(seen, name) {
        True -> Something(name)
        False -> find_duplicate_property_name(rest, [name, ..seen])
      }
  }
}

fn normalize_tagged(
  left_tag: String,
  left: Schema,
  right_tag: String,
  right: Schema,
) -> Result(Schema, ContractError) {
  case left_tag == right_tag {
    True -> Error(DuplicateSchemaTag(left_tag))
    False -> {
      use normalized_left <- bind(normalize(left))
      use normalized_right <- bind(normalize(right))
      case string.compare(left_tag, right_tag) {
        order.Lt | order.Eq ->
          Ok(codec.TaggedSchema(
            left_tag,
            normalized_left,
            right_tag,
            normalized_right,
          ))
        order.Gt ->
          Ok(codec.TaggedSchema(
            right_tag,
            normalized_right,
            left_tag,
            normalized_left,
          ))
      }
    }
  }
}

fn validate_at(
  schema: Schema,
  val: Value,
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  case schema, val {
    codec.DescribedSchema(_, inner), _ -> validate_at(inner, val, path)
    codec.StringSchema, value.String(_) -> Ok(Nil)
    codec.StringSchema, _ -> invalid(path, ExpectedString)

    codec.StringEnumSchema(labels), value.String(label) ->
      case list.contains(labels, label) {
        True -> Ok(Nil)
        False -> invalid(path, UnknownEnumLabel(label))
      }
    codec.StringEnumSchema(_), _ -> invalid(path, ExpectedString)

    codec.IntSchema, value.Number(num) ->
      case number.is_integer(num) {
        True -> Ok(Nil)
        False -> invalid(path, ExpectedInteger)
      }
    codec.IntSchema, _ -> invalid(path, ExpectedInteger)

    codec.NumberSchema, value.Number(_) -> Ok(Nil)
    codec.NumberSchema, _ -> invalid(path, ExpectedNumber)

    codec.BoolSchema, value.Bool(_) -> Ok(Nil)
    codec.BoolSchema, _ -> invalid(path, ExpectedBoolean)

    codec.PairSchema(first_schema, second_schema), value.Array([first, second])
    -> {
      use _ <- bind_validation(validate_at(
        first_schema,
        first,
        extend(path, Index(0)),
      ))
      validate_at(second_schema, second, extend(path, Index(1)))
    }
    codec.PairSchema(_, _), value.Array(items) ->
      invalid(path, WrongTupleLength(2, list.length(items)))
    codec.PairSchema(_, _), _ -> invalid(path, ExpectedArray)

    codec.ListSchema(inner), value.Array(items) ->
      validate_items(inner, items, 0, path)
    codec.ListSchema(_), _ -> invalid(path, ExpectedArray)

    codec.NullableSchema(_), value.Null -> Ok(Nil)
    codec.NullableSchema(inner), _ -> validate_at(inner, val, path)

    codec.ObjectSchema(properties), value.Object(fields) ->
      validate_object(properties, fields, path)
    codec.ObjectSchema(_), _ -> invalid(path, ExpectedObject)

    codec.TaggedSchema(left_tag, left, right_tag, right), value.Object(fields)
    -> validate_tagged_value(left_tag, left, right_tag, right, fields, path)
    codec.TaggedSchema(_, _, _, _), _ -> invalid(path, ExpectedObject)

    codec.IntegerRangeSchema(minimum, maximum), value.Number(num) ->
      case number.is_integer(num) {
        True -> {
          let limit =
            number.integer_projection_limit_for_range_value(
              num,
              minimum,
              maximum,
            )
          case number.to_int_exact(num, limit) {
            Ok(actual) if actual >= minimum && actual <= maximum -> Ok(Nil)
            Ok(actual) ->
              invalid(path, IntegerOutsideRange(minimum, maximum, actual))
            Error(_) -> invalid(path, ExpectedInteger)
          }
        }
        False -> invalid(path, ExpectedInteger)
      }
    codec.IntegerRangeSchema(_, _), _ -> invalid(path, ExpectedInteger)

    codec.NumberRangeSchema(minimum, maximum), value.Number(num) ->
      case
        number.compare(num, minimum) != number.LessThan
        && number.compare(num, maximum) != number.GreaterThan
      {
        True -> Ok(Nil)
        False -> invalid(path, NumberOutsideRange(minimum, maximum, num))
      }
    codec.NumberRangeSchema(_, _), _ -> invalid(path, ExpectedNumber)

    codec.FieldSchema(_, _), _ -> invalid(path, ExpectedObject)
  }
}

fn validate_items(
  schema: Schema,
  items: List(Value),
  index: Int,
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  case items {
    [] -> Ok(Nil)
    [item, ..rest] -> {
      use _ <- bind_validation(validate_at(
        schema,
        item,
        extend(path, Index(index)),
      ))
      validate_items(schema, rest, index + 1, path)
    }
  }
}

fn validate_object(
  properties: List(PropertySchema),
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  case find_duplicate_field(fields, []) {
    Something(name) ->
      invalid(extend(path, Property(name)), DuplicateProperty(name))
    Nothing ->
      case find_unknown_field(fields, properties) {
        Something(name) ->
          invalid(extend(path, Property(name)), UnknownProperty(name))
        Nothing -> validate_properties(properties, fields, path)
      }
  }
}

fn validate_properties(
  properties: List(PropertySchema),
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  case properties {
    [] -> Ok(Nil)
    [codec.PropertySchema(name, required, prop_schema), ..rest] ->
      case lookup_field(fields, name) {
        Nothing if required ->
          invalid(extend(path, Property(name)), MissingProperty(name))
        Nothing -> validate_properties(rest, fields, path)
        Something(field_val) -> {
          use _ <- bind_validation(validate_at(
            prop_schema,
            field_val,
            extend(path, Property(name)),
          ))
          validate_properties(rest, fields, path)
        }
      }
  }
}

fn validate_tagged_value(
  left_tag: String,
  left: Schema,
  right_tag: String,
  right: Schema,
  fields: List(#(String, Value)),
  path: List(PathSegment),
) -> Result(Nil, ValidationError) {
  case find_duplicate_field(fields, []) {
    Something(name) ->
      invalid(extend(path, Property(name)), DuplicateProperty(name))
    Nothing ->
      case find_unknown_tagged_field(fields) {
        Something(name) ->
          invalid(extend(path, Property(name)), UnknownProperty(name))
        Nothing ->
          case lookup_field(fields, "tag") {
            Nothing -> invalid(extend(path, Property("tag")), MissingTag)
            Something(value.String(tag)) -> {
              let payload_schema = case tag {
                _ if tag == left_tag -> Something(left)
                _ if tag == right_tag -> Something(right)
                _ -> Nothing
              }
              case payload_schema {
                Nothing ->
                  invalid(extend(path, Property("tag")), UnknownTag(tag))
                Something(selected_schema) ->
                  case lookup_field(fields, "value") {
                    Nothing ->
                      invalid(
                        extend(
                          extend(path, Property("value")),
                          TaggedBranch(tag),
                        ),
                        MissingProperty("value"),
                      )
                    Something(payload) ->
                      validate_at(
                        selected_schema,
                        payload,
                        extend(
                          extend(path, Property("value")),
                          TaggedBranch(tag),
                        ),
                      )
                  }
              }
            }
            Something(_) -> invalid(extend(path, Property("tag")), NonStringTag)
          }
      }
  }
}

fn find_unknown_tagged_field(fields: List(#(String, Value))) -> Maybe(String) {
  case fields {
    [] -> Nothing
    [#(key, _), ..rest] ->
      case key == "tag" || key == "value" {
        True -> find_unknown_tagged_field(rest)
        False -> Something(key)
      }
  }
}

fn find_duplicate_field(
  fields: List(#(String, Value)),
  seen: List(String),
) -> Maybe(String) {
  case fields {
    [] -> Nothing
    [#(key, _), ..rest] ->
      case list.contains(seen, key) {
        True -> Something(key)
        False -> find_duplicate_field(rest, [key, ..seen])
      }
  }
}

fn find_unknown_field(
  fields: List(#(String, Value)),
  properties: List(PropertySchema),
) -> Maybe(String) {
  case fields {
    [] -> Nothing
    [#(key, _), ..rest] ->
      case has_property(properties, key) {
        True -> find_unknown_field(rest, properties)
        False -> Something(key)
      }
  }
}

fn has_property(properties: List(PropertySchema), name: String) -> Bool {
  case properties {
    [] -> False
    [codec.PropertySchema(prop_name, _, _), ..rest] ->
      prop_name == name || has_property(rest, name)
  }
}

fn lookup_field(fields: List(#(String, Value)), name: String) -> Maybe(Value) {
  case fields {
    [] -> Nothing
    [#(key, val), ..rest] ->
      case key == name {
        True -> Something(val)
        False -> lookup_field(rest, name)
      }
  }
}

fn extend(path: List(PathSegment), segment: PathSegment) -> List(PathSegment) {
  list.append(path, [segment])
}

fn invalid(
  path: List(PathSegment),
  reason: ValidationReason,
) -> Result(Nil, ValidationError) {
  Error(ValidationError(path, reason))
}

fn bind(
  res: Result(a, ContractError),
  next: fn(a) -> Result(b, ContractError),
) -> Result(b, ContractError) {
  case res {
    Error(error) -> Error(error)
    Ok(val) -> next(val)
  }
}

fn bind_validation(
  res: Result(a, ValidationError),
  next: fn(a) -> Result(b, ValidationError),
) -> Result(b, ValidationError) {
  case res {
    Error(error) -> Error(error)
    Ok(val) -> next(val)
  }
}
