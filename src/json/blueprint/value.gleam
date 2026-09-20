import json/blueprint/number.{type Number}

pub type Value {
  Null
  Bool(Bool)
  String(String)
  Number(Number)
  Array(List(Value))
  Object(List(#(String, Value)))
}

pub type ObjectKeyPolicy {
  RejectDuplicates
}

pub type ValueError {
  DuplicateObjectKey(String)
}

pub fn object(
  _entries: List(#(String, Value)),
  _policy: ObjectKeyPolicy,
) -> Result(Value, ValueError) {
  todo as "construct validated object with key policy"
}
