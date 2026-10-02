//// The JSON value model: null, booleans, strings, exact numbers, arrays and
//// objects.
////
//// `Value` is what the strict parser returns, what `runtime` validates and
//// what `codec.encode` and `codec.decode` exchange. Object members keep their
//// order. Construct an object with `object(entries, RejectDuplicates)` to
//// reject a repeated key; the `Object` constructor accepts any list.
//// Numbers are `number.Number`, so they are exact.

import gleam/list
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

pub fn null() -> Value {
  Null
}

pub fn bool(b: Bool) -> Value {
  Bool(b)
}

pub fn string(s: String) -> Value {
  String(s)
}

pub fn number(n: Number) -> Value {
  Number(n)
}

pub fn array(items: List(Value)) -> Value {
  Array(items)
}

pub fn object(
  entries: List(#(String, Value)),
  policy: ObjectKeyPolicy,
) -> Result(Value, ValueError) {
  case policy {
    RejectDuplicates ->
      case find_duplicate_key(entries, []) {
        Error(key) -> Error(DuplicateObjectKey(key))
        Ok(Nil) -> Ok(Object(entries))
      }
  }
}

fn find_duplicate_key(
  entries: List(#(String, Value)),
  seen: List(String),
) -> Result(Nil, String) {
  case entries {
    [] -> Ok(Nil)
    [#(key, _), ..rest] ->
      case list.contains(seen, key) {
        True -> Error(key)
        False -> find_duplicate_key(rest, [key, ..seen])
      }
  }
}
