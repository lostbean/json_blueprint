//// Application-owned policy and envelope around the generated wire record.

import commerce/order
import gleam/list
import gleam/result
import json/blueprint/codec

pub type Submission {
  Submission(correlation_id: String, order: order.Order)
}

pub type AcceptanceError {
  InvalidWire(codec.DecodeError)
  InactiveOrder
  EmptyOrder
}

pub fn submission_codec() -> codec.Codec(Submission) {
  let order_codec = order.order_codec()
  let correlation_codec = codec.string()
  use correlation_id <- codec.field(
    "correlationId",
    correlation_codec,
    get: fn(s) { s.correlation_id },
  )
  use order <- codec.field("order", order_codec, get: fn(s) { s.order })
  codec.success(Submission(correlation_id:, order:))
}

/// JSON conversion owns schema checks; the application owns dispatch policy.
pub fn accept(text: String) -> Result(Submission, AcceptanceError) {
  use submission <- result.try(
    codec.decode_json(submission_codec(), text) |> result.map_error(InvalidWire),
  )
  case submission.order.active, list.is_empty(submission.order.items) {
    False, _ -> Error(InactiveOrder)
    True, True -> Error(EmptyOrder)
    True, False -> Ok(submission)
  }
}
