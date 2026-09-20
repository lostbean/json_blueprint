import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value

pub type OrderStatus {
  Pending
  Processing
  ShippedQuoted
  DeliveredUnicode
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

pub fn build_order_codec() -> codec.Codec(Order) {
  let assert Ok(status_c) =
    codec.string_enum([
      #("pending", Pending),
      #("processing", Processing),
      #("shipped\n\r\f\t\"quoted\"", ShippedQuoted),
      #("delivered 🚀 fn", DeliveredUnicode),
    ])

  let assert Ok(id_c) = codec.integer_between(1, 999_999)
  let items_c = codec.list(codec.pair(codec.string(), codec.int()))
  let note_c = codec.nullable(codec.string())

  let assert Ok(p1) =
    codec.combine(
      codec.required("order_id", id_c),
      codec.required("items_\"list\"", items_c),
    )
  let assert Ok(p2) =
    codec.combine(p1, codec.optional("customer\n\r\f\t\\note", note_c))
  let assert Ok(p3) = codec.combine(p2, codec.required("type", codec.bool()))
  let assert Ok(full_props) =
    codec.combine(p3, codec.required("status", status_c))

  codec.imap(
    codec.object(full_props),
    fn(
      raw: #(
        #(
          #(
            #(Int, List(#(String, Int))),
            codec.Optional(codec.Nullable(String)),
          ),
          Bool,
        ),
        OrderStatus,
      ),
    ) {
      Order(raw.0.0.0.0, raw.0.0.0.1, raw.0.0.1, raw.0.1, raw.1)
    },
    fn(o: Order) { #(#(#(#(o.order_id, o.items), o.note), o.active), o.status) },
  )
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
