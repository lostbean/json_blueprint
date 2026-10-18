//// Your own types and dependent fields.
////
//// `codec.map` converts with total functions, `codec.try_map` with functions
//// that may fail, and `codec.custom` builds a codec from functions over
//// `Value`. `try_map` and `custom` take a placeholder: any value of the type,
//// used where a value is needed without input, as `decode.failure` does.
////
//// A failed conversion is the reason `Custom(message)` at the codec's path.
//// A `try_map` over a whole record fails at the record's own path, `[]` at
//// the root. To report a check across fields at the field it concerns, build
//// that field's codec inside the record from the fields decoded before it, as
//// `order_codec` does. When the codec describes itself, `total_of` receives
//// placeholder values, so its schema must not depend on them.

import gleam/int
import gleam/string
import json/blueprint/codec.{type Codec}

pub type Email {
  Email(address: String)
}

pub fn email_codec() -> Codec(Email) {
  codec.try_map(
    codec.string(),
    decode: fn(text) {
      case string.contains(text, "@") {
        True -> Ok(Email(text))
        False -> Error("an email address needs an @")
      }
    },
    encode: fn(email: Email) { Ok(email.address) },
    placeholder: Email(""),
  )
}

pub type Order {
  Order(items: List(Int), total: Int)
}

pub fn order_codec() -> Codec(Order) {
  use items <- codec.field("items", codec.list(codec.int()), get: fn(o) {
    o.items
  })
  use total <- codec.field("total", total_of(items), get: fn(o) { o.total })
  codec.success(Order(items:, total:))
}

fn total_of(items: List(Int)) -> Codec(Int) {
  let sum = int.sum(items)
  let check = fn(total) {
    case total == sum {
      True -> Ok(total)
      False ->
        Error(
          "total "
          <> int.to_string(total)
          <> " differs from the item sum "
          <> int.to_string(sum),
        )
    }
  }
  codec.try_map(codec.int(), decode: check, encode: check, placeholder: sum)
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  assert codec.decode_json(email_codec(), "\"a@b\"") == Ok(Email("a@b"))
  let assert Error(email_error) = codec.decode_json(email_codec(), "\"ab\"")
  assert codec.describe_decode_error(email_error)
    == "$: an email address needs an @"

  assert codec.decode_json(order_codec(), "{\"items\":[1,2],\"total\":3}")
    == Ok(Order([1, 2], 3))
  let assert Error(order_error) =
    codec.decode_json(order_codec(), "{\"items\":[1,2],\"total\":4}")
  assert order_error
    == codec.DecodeError(
      [codec.Field("total")],
      codec.Custom("total 4 differs from the item sum 3"),
    )
  let assert Error(encode_error) =
    codec.encode_json(order_codec(), Order([1, 2], 4))
  codec.describe_encode_error(encode_error)
}
