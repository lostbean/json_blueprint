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

pub fn imap(_codec: Codec(a), _from: fn(a) -> b, _to: fn(b) -> a) -> Codec(b) {
  todo as "imap total bidirectional mapping"
}

pub fn string() -> Codec(String) {
  todo as "primitive string codec"
}

pub fn int() -> Codec(Int) {
  todo as "primitive int codec"
}

pub fn number() -> Codec(Number) {
  todo as "primitive exact number codec"
}

pub fn bool() -> Codec(Bool) {
  todo as "primitive bool codec"
}

pub fn pair(_left: Codec(a), _right: Codec(b)) -> Codec(#(a, b)) {
  todo as "exact pair codec"
}

pub fn list(_inner: Codec(a)) -> Codec(List(a)) {
  todo as "list codec"
}

pub type Nullable(a) {
  Null
  NonNull(a)
}

pub fn nullable(_inner: Codec(a)) -> Codec(Nullable(a)) {
  todo as "nullable codec"
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
  todo as "empty object properties"
}

pub fn required(_name: String, _codec: Codec(a)) -> Properties(a) {
  todo as "required object property"
}

pub fn optional(_name: String, _codec: Codec(a)) -> Properties(Optional(a)) {
  todo as "optional object property"
}

pub fn combine(
  _left: Properties(a),
  _right: Properties(b),
) -> Result(Properties(#(a, b)), PropertyError) {
  todo as "combine object properties"
}

pub fn object(_properties: Properties(a)) -> Codec(a) {
  todo as "closed object codec"
}

pub fn field(_name: String, _inner: Codec(a)) -> Codec(a) {
  todo as "single field object codec"
}

pub type EnumError {
  EmptyEnum
  DuplicateEnumLabel(String)
  DuplicateEnumValue(first_index: Int, repeated_index: Int)
}

pub fn string_enum(
  _variants: List(#(String, a)),
) -> Result(Codec(a), EnumError) {
  todo as "finite string enum codec from lookup table"
}

pub type Either(left, right) {
  Left(left)
  Right(right)
}

pub type UnionError {
  DuplicateTag(String)
}

pub fn tagged(
  _left_tag: String,
  _left: Codec(a),
  _right_tag: String,
  _right: Codec(b),
) -> Result(Codec(Either(a, b)), UnionError) {
  todo as "binary tagged alternative codec"
}

pub type ConstraintError {
  InvalidIntegerBounds(min: Int, max: Int)
  ReversedNumberBounds(min: Number, max: Number)
}

pub fn integer_between(
  _min: Int,
  _max: Int,
) -> Result(Codec(Int), ConstraintError) {
  todo as "inclusive bounded integer codec"
}

pub fn number_between(
  _min: Number,
  _max: Number,
) -> Result(Codec(Number), ConstraintError) {
  todo as "inclusive bounded number codec"
}

pub fn schema_value(_schema: Schema) -> Value {
  todo as "render schema AST to Value"
}

pub fn schema_document(_schema: Schema) -> Value {
  todo as "render Draft 2020-12 schema document to Value"
}
