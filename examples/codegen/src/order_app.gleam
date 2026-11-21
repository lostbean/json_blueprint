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

/// Each child codec is built in its field: on 2.1.x one bound before the
/// `use` chain would be captured by every later continuation and copied once
/// per callback when the codec is sent to another process.
pub fn submission_codec() -> codec.Codec(Submission) {
  use correlation_id <- codec.field("correlationId", codec.string(), get: fn(s) {
    s.correlation_id
  })
  use order <- codec.field("order", order.order_codec(), get: fn(s) { s.order })
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
