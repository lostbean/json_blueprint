import commerce/order
import gleam/list
import gleam/option.{None, Some}
import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

@external(erlang, "consumer_ffi", "read_file")
@external(javascript, "./consumer_ffi.mjs", "read_file")
fn read_file(path: String) -> Result(String, String)

pub fn loaded(name: String) -> contract.Contract {
  let assert Ok(text) = read_file("schema/" <> name <> ".json")
  let assert Ok(loaded) = contract.parse(text, value.default_limits())
  loaded
}

pub fn decimal(text: String) -> number.Number {
  let assert Ok(n) = number.parse(text, number.default_limits())
  n
}

pub fn sample(count: Int) -> order.Order {
  order.Order(
    active: True,
    items: list.repeat(
      order.OrderItemsItem(
        quantity: 2,
        sku: "paper",
        unit_price: decimal("12.34567890123456789"),
      ),
      count,
    ),
    labels: Some(["office", "priority"]),
    note: Some(Some("leave at reception")),
    order_id: 42,
    reference: None,
    shipping: order.OrderShipping(address: "Example Street", coordinates: #(
      decimal("-23.55"),
      decimal("-46.63"),
    )),
  )
}

pub fn handwritten_codec() -> codec.Codec(order.Order) {
  let string_codec = codec.string()
  let number_codec = codec.number()
  let quantity_codec = codec.integer_between(1, 100)
  let price_codec = codec.number_between(decimal("0"), decimal("99999.99"))
  let coordinates_codec = codec.pair(number_codec, number_codec)
  let item = {
    use quantity <- codec.field("quantity", quantity_codec, get: fn(i) {
      i.quantity
    })
    use sku <- codec.field("sku", string_codec, get: fn(i) { i.sku })
    use unit_price <- codec.field("unitPrice", price_codec, get: fn(i) {
      i.unit_price
    })
    codec.success(order.OrderItemsItem(quantity:, sku:, unit_price:))
  }
  let shipping = {
    use address <- codec.field("address", string_codec, get: fn(s) { s.address })
    use coordinates <- codec.field("coordinates", coordinates_codec, get: fn(s) {
      s.coordinates
    })
    codec.success(order.OrderShipping(address:, coordinates:))
  }
  let active_codec = codec.bool()
  let items_codec = codec.list(item)
  let labels_codec = codec.list(string_codec)
  let nullable_string = codec.nullable(string_codec)
  let id_codec =
    codec.integer_between(1, 999_999)
    |> codec.describe("Application order identifier")
  {
    use active <- codec.field("active", active_codec, get: fn(o) { o.active })
    use items <- codec.field("items", items_codec, get: fn(o) { o.items })
    use labels <- codec.optional_field("labels", labels_codec, get: fn(o) {
      o.labels
    })
    use note <- codec.optional_field("note", nullable_string, get: fn(o) {
      o.note
    })
    use order_id <- codec.field("orderId", id_codec, get: fn(o) { o.order_id })
    use reference <- codec.field("reference", nullable_string, get: fn(o) {
      o.reference
    })
    use shipping <- codec.field("shipping", shipping, get: fn(o) { o.shipping })
    codec.success(order.Order(
      active:,
      items:,
      labels:,
      note:,
      order_id:,
      reference:,
      shipping:,
    ))
  }
  |> codec.describe("An order accepted at the application boundary")
}
