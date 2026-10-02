import gleam/option.{type Option, None}
import json/blueprint/codec
import json/blueprint/codegen
import json/blueprint/number
import json/blueprint/value

pub type OrderStatus {
  Pending
  Processing
  ShippedQuoted
  DeliveredUnicode
  Unmapped
}

/// `note` is absent (`None`), `null` (`Some(None)`) or a string
/// (`Some(Some(text))`).
pub type Order {
  Order(
    order_id: Int,
    items: List(#(String, Int)),
    note: Option(Option(String)),
    active: Bool,
    status: OrderStatus,
  )
}

pub fn order_from_fields(
  raw: #(
    #(#(#(Int, List(#(String, Int))), Option(Option(String))), Bool),
    OrderStatus,
  ),
) -> Order {
  Order(raw.0.0.0.0, raw.0.0.0.1, raw.0.0.1, raw.0.1, raw.1)
}

pub fn order_to_fields(
  order: Order,
) -> #(
  #(#(#(Int, List(#(String, Int))), Option(Option(String))), Bool),
  OrderStatus,
) {
  #(
    #(#(#(order.order_id, order.items), order.note), order.active),
    order.status,
  )
}

pub fn order_definition() -> codegen.Definition(Order) {
  let assert Ok(pending) =
    codegen.enum_variant("pending", Pending, "materialize_fixtures.Pending")
  let assert Ok(processing) =
    codegen.enum_variant(
      "processing",
      Processing,
      "materialize_fixtures.Processing",
    )
  let assert Ok(shipped) =
    codegen.enum_variant(
      "shipped\n\r\f\t\"quoted\"",
      ShippedQuoted,
      "materialize_fixtures.ShippedQuoted",
    )
  let assert Ok(delivered) =
    codegen.enum_variant(
      "delivered 🚀 fn",
      DeliveredUnicode,
      "materialize_fixtures.DeliveredUnicode",
    )
  let assert Ok(status) =
    codegen.string_enum("materialize_fixtures.OrderStatus", [
      pending,
      processing,
      shipped,
      delivered,
    ])

  let id = codegen.integer_between(1, 999_999)
  let items = codegen.list(codegen.pair(codegen.string(), codegen.int()))
  let note = codegen.nullable(codegen.string())

  let properties =
    codegen.combine(
      codegen.required("order_id", id),
      codegen.required("items_\"list\"", items),
    )
    |> codegen.combine(codegen.optional("customer\n\r\f\t\\note", note))
    |> codegen.combine(codegen.required("type", codegen.bool()))
    |> codegen.combine(codegen.required("status", status))

  let assert Ok(mapping) =
    codegen.named_mapping(
      order_from_fields,
      "materialize_fixtures.order_from_fields",
      order_to_fields,
      "materialize_fixtures.order_to_fields",
    )
  let assert Ok(definition) =
    codegen.imap(
      codegen.object(properties),
      "materialize_fixtures.Order",
      mapping,
    )
  definition
}

pub fn build_order_codec() -> codec.Codec(Order) {
  codegen.runtime(order_definition())
}

pub type ApprovePayload {
  ApprovePayload(quantity: Int, ratio: number.Number)
}

pub type DeclinePayload {
  DeclinePayload(reason: String, code: Int)
}

pub type Decision {
  Approve(ApprovePayload)
  Decline(DeclinePayload)
  Defer
}

pub fn build_decision_codec() -> codec.Codec(Decision) {
  let approve = {
    use quantity <- codec.field(
      "quantity",
      codec.integer_between(1, 100),
      fn(a: ApprovePayload) { a.quantity },
    )
    use ratio <- codec.field("ratio", codec.number(), fn(a: ApprovePayload) {
      a.ratio
    })
    codec.success(ApprovePayload(quantity:, ratio:))
  }
  let decline = {
    use reason <- codec.field("reason", codec.string(), fn(d: DeclinePayload) {
      d.reason
    })
    use code <- codec.field("code", codec.int(), fn(d: DeclinePayload) {
      d.code
    })
    codec.success(DeclinePayload(reason:, code:))
  }

  codec.union({
    use approve <- codec.variant("approve \"let\"", approve, Approve)
    use decline <- codec.variant("decline \n\r\f\t\\import", decline, Decline)
    use defer <- codec.unit_variant("defer", Defer)
    codec.match(fn(decision) {
      case decision {
        Approve(payload) -> approve(payload)
        Decline(payload) -> decline(payload)
        Defer -> defer
      }
    })
  })
}

pub fn build_custom_unknown_codec() -> codec.Codec(Int) {
  codec.custom(
    encode: fn(i: Int) {
      let assert Ok(num) = number.from_int(i)
      Ok(value.Number(num))
    },
    decode: fn(_) { Ok(1) },
    schema: None,
    placeholder: 0,
  )
}

pub fn build_number_range_codec() -> codec.Codec(number.Number) {
  let assert Ok(min_num) = number.from_int(0)
  let assert Ok(max_num) = number.from_int(100)
  codec.number_between(min_num, max_num)
}
