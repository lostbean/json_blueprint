import gleam/list
import json/blueprint/number.{type Number}
import json/blueprint/value.{type Value}

pub type EncodeReason {
  EncodeUnknownEnumLabel(String)
  EncodeUnknownEnumValue(String)
  EncodeUnknownTag(String)
  EncodeUnknownProperty(String)
  EncodeWrongTupleLength(expected: Int, actual: Int)
  EncodeInvalidNativeValue(String)
  EncodeIntegerOutsideRange(minimum: Int, maximum: Int, actual: Int)
  EncodeNumberOutsideRange(minimum: Number, maximum: Number, actual: Number)
  CustomEncodeReason(String)
}

pub type EncodeError {
  CannotEncode(reason: EncodeReason)
  EncodeAtField(field: String, inner: EncodeError)
  EncodeAtIndex(index: Int, inner: EncodeError)
}

pub type DecodeReason {
  DecodeExpectedString
  DecodeExpectedInt
  DecodeExpectedNumber
  DecodeExpectedBool
  DecodeExpectedArray
  DecodeExpectedObject
  DecodeUnknownEnumLabel(String)
  DecodeUnknownTag(String)
  DecodeMissingTag
  DecodeMissingTagPayload(String)
  DecodeExpectedTaggedObject
  DecodeMissingProperty(String)
  DecodeUnknownProperty(String)
  DecodeDuplicateProperty(String)
  DecodeWrongTupleLength(expected: Int, actual: Int)
  DecodeInvalidWireValue(String)
  DecodeIntegerOutsideRange(minimum: Int, maximum: Int, actual: Int)
  DecodeNumberOutsideRange(minimum: Number, maximum: Number, actual: Number)
  CustomDecodeReason(String)
}

pub type DecodeError {
  CannotDecode(reason: DecodeReason)
  DecodeAtField(field: String, inner: DecodeError)
  DecodeAtIndex(index: Int, inner: DecodeError)
}

pub type SchemaError {
  UnknownSchema
}

pub type Schema {
  StringSchema
  StringEnumSchema(List(String))
  IntSchema
  NumberSchema
  BoolSchema
  PairSchema(Schema, Schema)
  FieldSchema(String, Schema)
  ListSchema(Schema)
  NullableSchema(Schema)
  ObjectSchema(List(PropertySchema))
  TaggedSchema(String, Schema, String, Schema)
  IntegerRangeSchema(Int, Int)
  NumberRangeSchema(Number, Number)
}

pub type PropertySchema {
  PropertySchema(name: String, required: Bool, schema: Schema)
}

pub opaque type Codec(a) {
  Codec(
    encoder: fn(a) -> Result(Value, EncodeError),
    decoder: fn(Value) -> Result(a, DecodeError),
    schema: Result(Schema, SchemaError),
  )
}

pub fn new(
  encode: fn(a) -> Result(Value, EncodeError),
  decode: fn(Value) -> Result(a, DecodeError),
) -> Codec(a) {
  Codec(encode, decode, Error(UnknownSchema))
}

pub fn encode(codec: Codec(a), item: a) -> Result(Value, EncodeError) {
  codec.encoder(item)
}

pub fn decode(codec: Codec(a), item: Value) -> Result(a, DecodeError) {
  codec.decoder(item)
}

pub fn schema(codec: Codec(a)) -> Result(Schema, SchemaError) {
  codec.schema
}

pub fn imap(codec: Codec(a), from: fn(a) -> b, to: fn(b) -> a) -> Codec(b) {
  let mapped =
    new(fn(value) { encode(codec, to(value)) }, fn(raw) {
      case decode(codec, raw) {
        Ok(value) -> Ok(from(value))
        Error(error) -> Error(error)
      }
    })
  Codec(..mapped, schema: codec.schema)
}

pub fn string() -> Codec(String) {
  let codec =
    new(fn(s) { Ok(value.String(s)) }, fn(v) {
      case v {
        value.String(s) -> Ok(s)
        _ -> Error(CannotDecode(DecodeExpectedString))
      }
    })
  Codec(..codec, schema: Ok(StringSchema))
}

pub fn int() -> Codec(Int) {
  let codec =
    new(
      fn(n) {
        case number.from_int(n) {
          Ok(num) -> Ok(value.Number(num))
          Error(number.NonFiniteInteger) ->
            Error(CannotEncode(EncodeInvalidNativeValue("NonFiniteInteger")))
          Error(number.NonIntegerValue) ->
            Error(CannotEncode(EncodeInvalidNativeValue("NonIntegerValue")))
          Error(number.UnsafeNativeInteger) ->
            Error(CannotEncode(EncodeInvalidNativeValue("UnsafeNativeInteger")))
        }
      },
      fn(v) {
        case v {
          value.Number(num) -> {
            let assert Ok(limit) = number.integer_projection_limit(24)
            case number.to_int_exact(num, limit) {
              Ok(i) -> Ok(i)
              Error(_) -> Error(CannotDecode(DecodeExpectedInt))
            }
          }
          _ -> Error(CannotDecode(DecodeExpectedInt))
        }
      },
    )
  Codec(..codec, schema: Ok(IntSchema))
}

pub fn number() -> Codec(Number) {
  let codec =
    new(fn(n) { Ok(value.Number(n)) }, fn(v) {
      case v {
        value.Number(n) -> Ok(n)
        _ -> Error(CannotDecode(DecodeExpectedNumber))
      }
    })
  Codec(..codec, schema: Ok(NumberSchema))
}

pub fn bool() -> Codec(Bool) {
  let codec =
    new(fn(b) { Ok(value.Bool(b)) }, fn(v) {
      case v {
        value.Bool(b) -> Ok(b)
        _ -> Error(CannotDecode(DecodeExpectedBool))
      }
    })
  Codec(..codec, schema: Ok(BoolSchema))
}

pub fn pair(left: Codec(a), right: Codec(b)) -> Codec(#(a, b)) {
  let paired =
    new(
      fn(p: #(a, b)) {
        case encode(left, p.0) {
          Error(error) -> Error(EncodeAtIndex(0, error))
          Ok(a) ->
            case encode(right, p.1) {
              Error(error) -> Error(EncodeAtIndex(1, error))
              Ok(b) -> Ok(value.Array([a, b]))
            }
        }
      },
      fn(raw) {
        case raw {
          value.Array([a, b]) ->
            case decode(left, a) {
              Error(error) -> Error(DecodeAtIndex(0, error))
              Ok(a) ->
                case decode(right, b) {
                  Error(error) -> Error(DecodeAtIndex(1, error))
                  Ok(b) -> Ok(#(a, b))
                }
            }
          value.Array(items) ->
            Error(CannotDecode(DecodeWrongTupleLength(2, list.length(items))))
          _ -> Error(CannotDecode(DecodeExpectedArray))
        }
      },
    )
  let description = case left.schema, right.schema {
    Ok(a), Ok(b) -> Ok(PairSchema(a, b))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  Codec(..paired, schema: description)
}

pub fn list(inner: Codec(a)) -> Codec(List(a)) {
  let codec =
    new(
      fn(items) {
        case encode_items(inner, items, 0) {
          Ok(items) -> Ok(value.Array(items))
          Error(error) -> Error(error)
        }
      },
      fn(raw) {
        case raw {
          value.Array(items) -> decode_items(inner, items, 0)
          _ -> Error(CannotDecode(DecodeExpectedArray))
        }
      },
    )
  let description = case inner.schema {
    Ok(schema) -> Ok(ListSchema(schema))
    Error(error) -> Error(error)
  }
  Codec(..codec, schema: description)
}

fn encode_items(
  codec: Codec(a),
  items: List(a),
  index: Int,
) -> Result(List(Value), EncodeError) {
  case items {
    [] -> Ok([])
    [item, ..rest] ->
      case encode(codec, item) {
        Error(error) -> Error(EncodeAtIndex(index, error))
        Ok(raw) ->
          case encode_items(codec, rest, index + 1) {
            Ok(rest) -> Ok([raw, ..rest])
            Error(error) -> Error(error)
          }
      }
  }
}

fn decode_items(
  codec: Codec(a),
  items: List(Value),
  index: Int,
) -> Result(List(a), DecodeError) {
  case items {
    [] -> Ok([])
    [item, ..rest] ->
      case decode(codec, item) {
        Error(error) -> Error(DecodeAtIndex(index, error))
        Ok(decoded) ->
          case decode_items(codec, rest, index + 1) {
            Ok(rest) -> Ok([decoded, ..rest])
            Error(error) -> Error(error)
          }
      }
  }
}

pub type Nullable(a) {
  Null
  NonNull(a)
}

pub fn nullable(inner: Codec(a)) -> Codec(Nullable(a)) {
  let codec =
    new(
      fn(item) {
        case item {
          Null -> Ok(value.Null)
          NonNull(item) ->
            case encode(inner, item) {
              Ok(value.Null) ->
                Error(
                  CannotEncode(CustomEncodeReason(
                    "NonNull must encode a non-null value",
                  )),
                )
              other -> other
            }
        }
      },
      fn(raw) {
        case raw {
          value.Null -> Ok(Null)
          _ ->
            case decode(inner, raw) {
              Ok(item) -> Ok(NonNull(item))
              Error(error) -> Error(error)
            }
        }
      },
    )
  let description = case inner.schema {
    Ok(schema) -> Ok(NullableSchema(schema))
    Error(error) -> Error(error)
  }
  Codec(..codec, schema: description)
}

pub type Optional(a) {
  Missing
  Present(a)
}

pub type PropertyError {
  DuplicateProperty(String)
}

pub opaque type Properties(a) {
  Properties(
    encode: fn(a) -> Result(List(#(String, Value)), EncodeError),
    decode: fn(List(#(String, Value))) -> Result(a, DecodeError),
    names: List(String),
    schemas: Result(List(PropertySchema), SchemaError),
  )
}

pub fn empty() -> Properties(Nil) {
  Properties(fn(_) { Ok([]) }, fn(_) { Ok(Nil) }, [], Ok([]))
}

pub fn required(name: String, codec: Codec(a)) -> Properties(a) {
  Properties(
    fn(item) { encode_property(name, codec, item) },
    fn(fields) {
      case lookup(fields, name) {
        Missing ->
          Error(DecodeAtField(name, CannotDecode(DecodeMissingProperty(name))))
        Present(raw) -> decode_property(name, codec, raw)
      }
    },
    [name],
    property_description(name, True, codec),
  )
}

pub fn optional(name: String, codec: Codec(a)) -> Properties(Optional(a)) {
  Properties(
    fn(item) {
      case item {
        Missing -> Ok([])
        Present(item) -> encode_property(name, codec, item)
      }
    },
    fn(fields) {
      case lookup(fields, name) {
        Missing -> Ok(Missing)
        Present(raw) ->
          case decode_property(name, codec, raw) {
            Ok(item) -> Ok(Present(item))
            Error(error) -> Error(error)
          }
      }
    },
    [name],
    property_description(name, False, codec),
  )
}

pub fn combine(
  left: Properties(a),
  right: Properties(b),
) -> Result(Properties(#(a, b)), PropertyError) {
  case overlap(left.names, right.names) {
    Present(name) -> Error(DuplicateProperty(name))
    Missing ->
      Ok(
        Properties(
          fn(items: #(a, b)) {
            case left.encode(items.0) {
              Error(error) -> Error(error)
              Ok(a) ->
                case right.encode(items.1) {
                  Error(error) -> Error(error)
                  Ok(b) -> Ok(list.append(a, b))
                }
            }
          },
          fn(fields) {
            case left.decode(fields) {
              Error(error) -> Error(error)
              Ok(a) ->
                case right.decode(fields) {
                  Error(error) -> Error(error)
                  Ok(b) -> Ok(#(a, b))
                }
            }
          },
          list.append(left.names, right.names),
          case left.schemas, right.schemas {
            Ok(a), Ok(b) -> Ok(list.append(a, b))
            Error(error), _ -> Error(error)
            _, Error(error) -> Error(error)
          },
        ),
      )
  }
}

pub fn object(properties: Properties(a)) -> Codec(a) {
  Codec(
    fn(item) {
      case properties.encode(item) {
        Ok(fields) -> Ok(value.Object(fields))
        Error(error) -> Error(error)
      }
    },
    fn(raw) {
      case raw {
        value.Object(fields) ->
          case check_object_keys(fields, properties.names, []) {
            Ok(Nil) -> properties.decode(fields)
            Error(error) -> Error(error)
          }
        _ -> Error(CannotDecode(DecodeExpectedObject))
      }
    },
    case properties.schemas {
      Ok(props) -> Ok(ObjectSchema(props))
      Error(error) -> Error(error)
    },
  )
}

pub fn field(name: String, inner: Codec(a)) -> Codec(a) {
  let codec = object(required(name, inner))
  let description = case inner.schema {
    Ok(schema) -> Ok(FieldSchema(name, schema))
    Error(error) -> Error(error)
  }
  Codec(..codec, schema: description)
}

fn property_description(
  name: String,
  required: Bool,
  codec: Codec(a),
) -> Result(List(PropertySchema), SchemaError) {
  case codec.schema {
    Ok(schema) -> Ok([PropertySchema(name, required, schema)])
    Error(error) -> Error(error)
  }
}

fn encode_property(
  name: String,
  codec: Codec(a),
  item: a,
) -> Result(List(#(String, Value)), EncodeError) {
  case encode(codec, item) {
    Ok(raw) -> Ok([#(name, raw)])
    Error(error) -> Error(EncodeAtField(name, error))
  }
}

fn decode_property(
  name: String,
  codec: Codec(a),
  raw: Value,
) -> Result(a, DecodeError) {
  case decode(codec, raw) {
    Ok(item) -> Ok(item)
    Error(error) -> Error(DecodeAtField(name, error))
  }
}

fn lookup(fields: List(#(String, Value)), name: String) -> Optional(Value) {
  case fields {
    [] -> Missing
    [#(key, raw), ..] if key == name -> Present(raw)
    [_, ..rest] -> lookup(rest, name)
  }
}

fn overlap(left: List(String), right: List(String)) -> Optional(String) {
  case left {
    [] -> Missing
    [head, ..rest] ->
      case list.contains(right, head) {
        True -> Present(head)
        False -> overlap(rest, right)
      }
  }
}

fn check_object_keys(
  fields: List(#(String, Value)),
  names: List(String),
  seen: List(String),
) -> Result(Nil, DecodeError) {
  case fields {
    [] -> Ok(Nil)
    [#(name, _), ..rest] ->
      case list.contains(seen, name), list.contains(names, name) {
        True, _ ->
          Error(DecodeAtField(name, CannotDecode(DecodeDuplicateProperty(name))))
        _, False ->
          Error(DecodeAtField(name, CannotDecode(DecodeUnknownProperty(name))))
        False, True -> check_object_keys(rest, names, [name, ..seen])
      }
  }
}

pub type EnumError {
  EmptyEnum
  DuplicateEnumLabel(String)
  DuplicateEnumValue(first_index: Int, repeated_index: Int)
}

type EnumValueIndex {
  NoEnumValue
  EnumValueAt(Int)
}

pub fn string_enum(
  variants: List(#(String, a)),
) -> Result(Codec(a), EnumError) {
  case validate_enum(variants, 0, [], []) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let labels = enum_labels(variants)
      let codec =
        new(fn(item) { encode_enum(item, variants) }, fn(raw) {
          case raw {
            value.String(label) -> decode_enum(label, variants)
            _ -> Error(CannotDecode(DecodeExpectedString))
          }
        })
      Ok(Codec(..codec, schema: Ok(StringEnumSchema(labels))))
    }
  }
}

fn validate_enum(
  variants: List(#(String, a)),
  index: Int,
  seen_labels: List(String),
  seen_values: List(#(Int, a)),
) -> Result(Nil, EnumError) {
  case variants {
    [] ->
      case index {
        0 -> Error(EmptyEnum)
        _ -> Ok(Nil)
      }
    [#(label, item), ..rest] ->
      case list.contains(seen_labels, label) {
        True -> Error(DuplicateEnumLabel(label))
        False ->
          case enum_value_index(item, seen_values) {
            EnumValueAt(first_index) ->
              Error(DuplicateEnumValue(first_index, index))
            NoEnumValue ->
              validate_enum(rest, index + 1, [label, ..seen_labels], [
                #(index, item),
                ..seen_values
              ])
          }
      }
  }
}

fn enum_value_index(item: a, seen_values: List(#(Int, a))) -> EnumValueIndex {
  case seen_values {
    [] -> NoEnumValue
    [#(index, seen), ..rest] ->
      case item == seen {
        True -> EnumValueAt(index)
        False -> enum_value_index(item, rest)
      }
  }
}

fn enum_labels(variants: List(#(String, a))) -> List(String) {
  case variants {
    [] -> []
    [#(label, _), ..rest] -> [label, ..enum_labels(rest)]
  }
}

fn encode_enum(
  item: a,
  variants: List(#(String, a)),
) -> Result(Value, EncodeError) {
  case variants {
    [] ->
      Error(
        CannotEncode(EncodeUnknownEnumValue("Value is not in the string enum")),
      )
    [#(label, candidate), ..rest] ->
      case item == candidate {
        True -> Ok(value.String(label))
        False -> encode_enum(item, rest)
      }
  }
}

fn decode_enum(
  label: String,
  variants: List(#(String, a)),
) -> Result(a, DecodeError) {
  case variants {
    [] -> Error(CannotDecode(DecodeUnknownEnumLabel(label)))
    [#(candidate, item), ..rest] ->
      case label == candidate {
        True -> Ok(item)
        False -> decode_enum(label, rest)
      }
  }
}

pub type Either(left, right) {
  Left(left)
  Right(right)
}

pub type UnionError {
  DuplicateTag(String)
}

pub fn tagged(
  left_tag: String,
  left: Codec(a),
  right_tag: String,
  right: Codec(b),
) -> Result(Codec(Either(a, b)), UnionError) {
  case left_tag == right_tag {
    True -> Error(DuplicateTag(left_tag))
    False ->
      Ok(
        Codec(
          fn(item) {
            case item {
              Left(item) -> encode_tagged(left_tag, left, item)
              Right(item) -> encode_tagged(right_tag, right, item)
            }
          },
          fn(raw) {
            case tagged_parts(raw) {
              Error(error) -> Error(error)
              Ok(#(tag, payload)) ->
                case tag {
                  tag if tag == left_tag ->
                    case decode_property("value", left, payload) {
                      Ok(item) -> Ok(Left(item))
                      Error(error) -> Error(error)
                    }
                  tag if tag == right_tag ->
                    case decode_property("value", right, payload) {
                      Ok(item) -> Ok(Right(item))
                      Error(error) -> Error(error)
                    }
                  _ ->
                    Error(DecodeAtField(
                      "tag",
                      CannotDecode(DecodeUnknownTag(tag)),
                    ))
                }
            }
          },
          case left.schema, right.schema {
            Ok(a), Ok(b) -> Ok(TaggedSchema(left_tag, a, right_tag, b))
            Error(error), _ -> Error(error)
            _, Error(error) -> Error(error)
          },
        ),
      )
  }
}

fn encode_tagged(
  tag: String,
  codec: Codec(a),
  item: a,
) -> Result(Value, EncodeError) {
  case encode(codec, item) {
    Ok(raw) -> Ok(value.Object([#("tag", value.String(tag)), #("value", raw)]))
    Error(error) -> Error(EncodeAtField("value", error))
  }
}

fn tagged_parts(raw: Value) -> Result(#(String, Value), DecodeError) {
  case raw {
    value.Object(fields) ->
      case check_object_keys(fields, ["tag", "value"], []) {
        Error(error) -> Error(error)
        Ok(Nil) ->
          case lookup(fields, "tag"), lookup(fields, "value") {
            Present(value.String(tag)), Present(payload) -> Ok(#(tag, payload))
            Present(value.String(_)), Missing ->
              Error(DecodeAtField(
                "value",
                CannotDecode(DecodeMissingTagPayload("Missing payload")),
              ))
            Present(_), _ ->
              Error(DecodeAtField("tag", CannotDecode(DecodeExpectedString)))
            Missing, _ ->
              Error(DecodeAtField("tag", CannotDecode(DecodeMissingTag)))
          }
      }
    _ -> Error(CannotDecode(DecodeExpectedTaggedObject))
  }
}

pub type ConstraintError {
  InvalidIntegerBounds(min: Int, max: Int)
  ReversedNumberBounds(min: Number, max: Number)
}

pub fn integer_between(
  min: Int,
  max: Int,
) -> Result(Codec(Int), ConstraintError) {
  case min > max {
    True -> Error(InvalidIntegerBounds(min, max))
    False ->
      case number.from_int(min), number.from_int(max) {
        Ok(_), Ok(_) ->
          Ok(Codec(
            fn(item) {
              case item >= min && item <= max {
                True ->
                  case number.from_int(item) {
                    Ok(num) -> Ok(value.Number(num))
                    Error(_) ->
                      Error(
                        CannotEncode(EncodeIntegerOutsideRange(min, max, item)),
                      )
                  }
                False ->
                  Error(CannotEncode(EncodeIntegerOutsideRange(min, max, item)))
              }
            },
            fn(raw) {
              case raw {
                value.Number(num) -> {
                  let assert Ok(limit) = number.integer_projection_limit(24)
                  case number.to_int_exact(num, limit) {
                    Ok(item) if item >= min && item <= max -> Ok(item)
                    Ok(item) ->
                      Error(
                        CannotDecode(DecodeIntegerOutsideRange(min, max, item)),
                      )
                    Error(_) -> Error(CannotDecode(DecodeExpectedInt))
                  }
                }
                _ -> Error(CannotDecode(DecodeExpectedInt))
              }
            },
            Ok(IntegerRangeSchema(min, max)),
          ))
        _, _ -> Error(InvalidIntegerBounds(min, max))
      }
  }
}

pub fn number_between(
  min: Number,
  max: Number,
) -> Result(Codec(Number), ConstraintError) {
  case number.compare(min, max) {
    number.GreaterThan -> Error(ReversedNumberBounds(min, max))
    _ ->
      Ok(Codec(
        fn(item) {
          case
            number.compare(item, min) != number.LessThan
            && number.compare(item, max) != number.GreaterThan
          {
            True -> Ok(value.Number(item))
            False ->
              Error(CannotEncode(EncodeNumberOutsideRange(min, max, item)))
          }
        },
        fn(raw) {
          case raw {
            value.Number(item) ->
              case
                number.compare(item, min) != number.LessThan
                && number.compare(item, max) != number.GreaterThan
              {
                True -> Ok(item)
                False ->
                  Error(CannotDecode(DecodeNumberOutsideRange(min, max, item)))
              }
            _ -> Error(CannotDecode(DecodeExpectedNumber))
          }
        },
        Ok(NumberRangeSchema(min, max)),
      ))
  }
}

pub fn schema_value(schema: Schema) -> Value {
  case schema {
    StringSchema -> value.Object([#("type", value.String("string"))])
    StringEnumSchema(labels) ->
      value.Object([
        #("type", value.String("string")),
        #("enum", value.Array(list.map(labels, value.String))),
      ])
    IntSchema -> value.Object([#("type", value.String("integer"))])
    NumberSchema -> value.Object([#("type", value.String("number"))])
    BoolSchema -> value.Object([#("type", value.String("boolean"))])
    PairSchema(a, b) -> {
      let assert Ok(two) = number.from_int(2)
      value.Object([
        #("type", value.String("array")),
        #("prefixItems", value.Array([schema_value(a), schema_value(b)])),
        #("minItems", value.Number(two)),
        #("maxItems", value.Number(two)),
      ])
    }
    FieldSchema(name, inner) ->
      value.Object([
        #("type", value.String("object")),
        #("properties", value.Object([#(name, schema_value(inner))])),
        #("required", value.Array([value.String(name)])),
        #("additionalProperties", value.Bool(False)),
      ])
    ListSchema(inner) ->
      value.Object([
        #("type", value.String("array")),
        #("items", schema_value(inner)),
      ])
    NullableSchema(inner) ->
      value.Object([
        #(
          "anyOf",
          value.Array([
            value.Object([#("type", value.String("null"))]),
            schema_value(inner),
          ]),
        ),
      ])
    ObjectSchema(properties) ->
      value.Object([
        #("type", value.String("object")),
        #("properties", value.Object(property_schemas(properties))),
        #("required", value.Array(required_names(properties))),
        #("additionalProperties", value.Bool(False)),
      ])
    TaggedSchema(left_tag, left, right_tag, right) ->
      value.Object([
        #("type", value.String("object")),
        #(
          "oneOf",
          value.Array([
            tagged_schema(left_tag, left),
            tagged_schema(right_tag, right),
          ]),
        ),
      ])
    IntegerRangeSchema(min, max) -> {
      let assert Ok(min_num) = number.from_int(min)
      let assert Ok(max_num) = number.from_int(max)
      value.Object([
        #("type", value.String("integer")),
        #("minimum", value.Number(min_num)),
        #("maximum", value.Number(max_num)),
      ])
    }
    NumberRangeSchema(min, max) ->
      value.Object([
        #("type", value.String("number")),
        #("minimum", value.Number(min)),
        #("maximum", value.Number(max)),
      ])
  }
}

pub fn schema_document(schema: Schema) -> Value {
  let assert value.Object(fields) = schema_value(schema)
  value.Object([
    #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
    ..fields
  ])
}

fn property_schemas(
  properties: List(PropertySchema),
) -> List(#(String, Value)) {
  case properties {
    [] -> []
    [PropertySchema(name, _, schema), ..rest] -> [
      #(name, schema_value(schema)),
      ..property_schemas(rest)
    ]
  }
}

fn required_names(properties: List(PropertySchema)) -> List(Value) {
  case properties {
    [] -> []
    [PropertySchema(name, True, _), ..rest] -> [
      value.String(name),
      ..required_names(rest)
    ]
    [_, ..rest] -> required_names(rest)
  }
}

fn tagged_schema(tag: String, payload: Schema) -> Value {
  value.Object([
    #("type", value.String("object")),
    #(
      "properties",
      value.Object([
        #("tag", value.Object([#("const", value.String(tag))])),
        #("value", schema_value(payload)),
      ]),
    ),
    #("required", value.Array([value.String("tag"), value.String("value")])),
    #("additionalProperties", value.Bool(False)),
  ])
}
