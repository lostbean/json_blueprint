import json/blueprint/codec.{type Codec, type DecodeError, type Schema}
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

pub fn from_schema(_schema: Schema) -> Result(RuntimeContract, ContractError) {
  todo as "construct normalized runtime contract from schema AST"
}

pub fn from_codec(_codec: Codec(a)) -> Result(RuntimeContract, ContractError) {
  todo as "construct runtime contract from retained codec schema"
}

pub fn schema(_contract: RuntimeContract) -> Schema {
  todo as "extract normalized schema from runtime contract"
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
  _contract: RuntimeContract,
  _value: Value,
) -> Result(ValidatedValue, ValidationError) {
  todo as "validate parsed value against runtime contract"
}

pub fn encoded(_value: ValidatedValue) -> Value {
  todo as "extract validated underlying value"
}

pub fn matches(_contract: RuntimeContract, _value: ValidatedValue) -> Bool {
  todo as "test if validated value matches runtime contract schema"
}

pub fn same_schema(_left: RuntimeContract, _right: RuntimeContract) -> Bool {
  todo as "exact normalized structural equality of runtime contracts"
}

pub fn decode(
  _codec: Codec(a),
  _value: ValidatedValue,
) -> Result(a, DecodeError) {
  todo as "decode native value from validated value using retained codec"
}
