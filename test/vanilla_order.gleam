import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import json/blueprint/codec
import materialize_fixtures

// Hand-written gleam/json baseline for the same wire shape as the canonical
// Blueprint Order definition. This is intentionally separate from the single
// maintained Blueprint definition and exists only for comparative benchmarks.
pub fn encode(
  order: materialize_fixtures.Order,
) -> Result(json.Json, codec.EncodeError) {
  case order.order_id >= 1 && order.order_id <= 999_999 {
    False ->
      Error(codec.EncodeAtField(
        "order_id",
        codec.CannotEncode(codec.EncodeIntegerOutsideRange(
          1,
          999_999,
          order.order_id,
        )),
      ))
    True ->
      case status_label(order.status) {
        Error(error) -> Error(error)
        Ok(status) -> {
          let note = case order.note {
            codec.Missing -> []
            codec.Present(codec.Null) -> [
              #("customer\n\r\f\t\\note", json.null()),
            ]
            codec.Present(codec.NonNull(value)) -> [
              #("customer\n\r\f\t\\note", json.string(value)),
            ]
          }
          let items =
            json.array(order.items, fn(item) {
              let #(name, quantity) = item
              json.preprocessed_array([json.string(name), json.int(quantity)])
            })
          Ok(
            json.object(list.append(
              [
                #("order_id", json.int(order.order_id)),
                #("items_\"list\"", items),
              ],
              list.append(note, [
                #("type", json.bool(order.active)),
                #("status", json.string(status)),
              ]),
            )),
          )
        }
      }
  }
}

pub fn decoder() -> decode.Decoder(materialize_fixtures.Order) {
  {
    use order_id <- decode.field("order_id", bounded_order_id())
    use items <- decode.field("items_\"list\"", decode.list(of: item_pair()))
    use note <- decode.optional_field(
      "customer\n\r\f\t\\note",
      codec.Missing,
      nullable_string_as_present(),
    )
    use active <- decode.field("type", decode.bool)
    use status <- decode.field("status", order_status())
    decode.success(materialize_fixtures.Order(
      order_id,
      items,
      note,
      active,
      status,
    ))
  }
}

fn bounded_order_id() -> decode.Decoder(Int) {
  decode.int
  |> decode.then(fn(order_id) {
    case order_id >= 1 && order_id <= 999_999 {
      True -> decode.success(order_id)
      False -> decode.failure(0, expected: "OrderId(1..999999)")
    }
  })
}

fn item_pair() -> decode.Decoder(#(String, Int)) {
  decode.new_primitive_decoder("OrderItem", fn(raw) {
    case decode.run(raw, decode.list(of: decode.dynamic)) {
      Ok([name, quantity]) ->
        case decode.run(name, decode.string), decode.run(quantity, decode.int) {
          Ok(name), Ok(quantity) -> Ok(#(name, quantity))
          _, _ -> Error(#("", 0))
        }
      Ok(_) -> Error(#("", 0))
      Error(_) -> Error(#("", 0))
    }
  })
}

fn nullable_string_as_present() -> decode.Decoder(
  codec.Optional(codec.Nullable(String)),
) {
  decode.optional(decode.string)
  |> decode.map(fn(value) {
    case value {
      Some(string) -> codec.Present(codec.NonNull(string))
      None -> codec.Present(codec.Null)
    }
  })
}

fn order_status() -> decode.Decoder(materialize_fixtures.OrderStatus) {
  decode.string
  |> decode.then(fn(label) {
    case label {
      "pending" -> decode.success(materialize_fixtures.Pending)
      "processing" -> decode.success(materialize_fixtures.Processing)
      "shipped\n\r\f\t\"quoted\"" ->
        decode.success(materialize_fixtures.ShippedQuoted)
      "delivered 🚀 fn" -> decode.success(materialize_fixtures.DeliveredUnicode)
      _ -> decode.failure(materialize_fixtures.Pending, expected: "OrderStatus")
    }
  })
}

fn status_label(
  status: materialize_fixtures.OrderStatus,
) -> Result(String, codec.EncodeError) {
  case status {
    materialize_fixtures.Pending -> Ok("pending")
    materialize_fixtures.Processing -> Ok("processing")
    materialize_fixtures.ShippedQuoted -> Ok("shipped\n\r\f\t\"quoted\"")
    materialize_fixtures.DeliveredUnicode -> Ok("delivered 🚀 fn")
    materialize_fixtures.Unmapped ->
      Error(
        codec.CannotEncode(codec.EncodeUnknownEnumValue(
          "Value is not in the string enum",
        )),
      )
  }
}
