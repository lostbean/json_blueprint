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

pub type Order {
  Order(
    order_id: Int,
    items: List(#(String, Int)),
    note: codec.Optional(codec.Nullable(String)),
    active: Bool,
    status: OrderStatus,
  )
}

pub fn order_from_fields(
  raw: #(
    #(
      #(#(Int, List(#(String, Int))), codec.Optional(codec.Nullable(String))),
      Bool,
    ),
    OrderStatus,
  ),
) -> Order {
  Order(raw.0.0.0.0, raw.0.0.0.1, raw.0.0.1, raw.0.1, raw.1)
}

pub fn order_to_fields(
  order: Order,
) -> #(
  #(
    #(#(Int, List(#(String, Int))), codec.Optional(codec.Nullable(String))),
    Bool,
  ),
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

  let assert Ok(id) = codegen.integer_between(1, 999_999)
  let items = codegen.list(codegen.pair(codegen.string(), codegen.int()))
  let note = codegen.nullable(codegen.string())

  let assert Ok(p1) =
    codegen.combine(
      codegen.required("order_id", id),
      codegen.required("items_\"list\"", items),
    )
  let assert Ok(p2) =
    codegen.combine(p1, codegen.optional("customer\n\r\f\t\\note", note))
  let assert Ok(p3) =
    codegen.combine(p2, codegen.required("type", codegen.bool()))
  let assert Ok(properties) =
    codegen.combine(p3, codegen.required("status", status))

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
}

pub fn build_decision_codec() -> codec.Codec(Decision) {
  let assert Ok(quantity_c) = codec.integer_between(1, 100)
  let ratio_c = codec.number()

  let assert Ok(approve_props) =
    codec.combine(
      codec.required("quantity", quantity_c),
      codec.required("ratio", ratio_c),
    )
  let approve_obj =
    codec.imap(
      codec.object(approve_props),
      fn(pair: #(Int, number.Number)) { ApprovePayload(pair.0, pair.1) },
      fn(a: ApprovePayload) { #(a.quantity, a.ratio) },
    )

  let assert Ok(decline_props) =
    codec.combine(
      codec.required("reason", codec.string()),
      codec.required("code", codec.int()),
    )
  let decline_obj =
    codec.imap(
      codec.object(decline_props),
      fn(pair: #(String, Int)) { DeclinePayload(pair.0, pair.1) },
      fn(d: DeclinePayload) { #(d.reason, d.code) },
    )

  let assert Ok(tagged_c) =
    codec.tagged(
      "approve \"let\"",
      approve_obj,
      "decline \n\r\f\t\\import",
      decline_obj,
    )

  codec.imap(
    tagged_c,
    fn(choice) {
      case choice {
        codec.Left(app) -> Approve(app)
        codec.Right(dec) -> Decline(dec)
      }
    },
    fn(d: Decision) {
      case d {
        Approve(app) -> codec.Left(app)
        Decline(dec) -> codec.Right(dec)
      }
    },
  )
}

pub fn build_custom_unknown_codec() -> codec.Codec(Int) {
  codec.new(
    fn(i: Int) {
      let assert Ok(num) = number.from_int(i)
      Ok(value.Number(num))
    },
    fn(_) { Ok(1) },
  )
}

pub fn build_number_range_codec() -> codec.Codec(number.Number) {
  let assert Ok(min_num) = number.from_int(0)
  let assert Ok(max_num) = number.from_int(100)
  let assert Ok(range_c) = codec.number_between(min_num, max_num)
  range_c
}
