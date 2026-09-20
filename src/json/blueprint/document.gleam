import json/blueprint/runtime.{type ContractError, type RuntimeContract}
import json/blueprint/value.{type Value}

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

pub fn load(_document: Value) -> Result(RuntimeContract, DocumentError) {
  todo as "strict loading of already-parsed Draft 2020-12 schema document"
}
