//// Building child codecs where they are used.
////
//// `use … <- codec.field` turns the rest of a record into a continuation; on
//// 2.1.x a record codec kept that continuation in several callbacks. A value bound
//// with `let` before the chain and used by a later field is captured by the
//// continuation. Inside one process that capture is shared, but a process copy
//// (a message, a spawn argument, a child specification) does not preserve
//// sharing. From 2.2.0 a record holds its continuation once, so the captured
//// child codec is copied once; on 2.1.x it was copied once per callback that
//// held the continuation.
////
//// Code that may still resolve 2.1.x builds each child codec in the field that
//// uses it, by calling a function in the field's codec argument. Both codecs
//// below convert and describe the same JSON; `captured_answer_codec` shows the
//// pattern to avoid on 2.1.x, and the examples test measures both copies.

import gleam/option.{type Option}
import json/blueprint/codec.{type Codec}

pub type Contact {
  Contact(
    name: Option(String),
    email: Option(String),
    phone: Option(String),
    company: Option(String),
    role: Option(String),
    city: Option(String),
  )
}

pub type Answer {
  Answer(summary: String, primary: Contact, backup: Option(Contact))
}

fn text(
  name: String,
  description: String,
  get: fn(Contact) -> Option(String),
  next: fn(Option(String)) -> Codec(Contact),
) -> Codec(Contact) {
  codec.optional_field(
    name,
    codec.string() |> codec.describe(description),
    get:,
    then: next,
  )
}

pub fn contact_codec() -> Codec(Contact) {
  use name <- text("name", "The person's full name", fn(c) { c.name })
  use email <- text("email", "A work email address", fn(c) { c.email })
  use phone <- text("phone", "A phone number with country code", fn(c) {
    c.phone
  })
  use company <- text("company", "The company's legal name", fn(c) { c.company })
  use role <- text("role", "The person's role at the company", fn(c) { c.role })
  use city <- text("city", "The city the person works from", fn(c) { c.city })
  codec.success(Contact(name:, email:, phone:, company:, role:, city:))
}

// snips-start: built-in-fields
/// Each field builds its child codec by calling `contact_codec`.
pub fn answer_codec() -> Codec(Answer) {
  use summary <- codec.field("summary", codec.string(), get: fn(a) { a.summary })
  use primary <- codec.field("primary", contact_codec(), get: fn(a) {
    a.primary
  })
  use backup <- codec.optional_field("backup", contact_codec(), get: fn(a) {
    a.backup
  })
  codec.success(Answer(summary:, primary:, backup:))
}

// snips-end: built-in-fields

// snips-start: let-bound
/// Avoid on 2.1.x: `contact` is bound before the chain and used by later
/// fields, so every continuation after the first field captures it. From
/// 2.2.0 it is copied once.
pub fn captured_answer_codec() -> Codec(Answer) {
  let contact = contact_codec()
  use summary <- codec.field("summary", codec.string(), get: fn(a) { a.summary })
  use primary <- codec.field("primary", contact, get: fn(a) { a.primary })
  use backup <- codec.optional_field("backup", contact, get: fn(a) { a.backup })
  codec.success(Answer(summary:, primary:, backup:))
}

// snips-end: let-bound

/// A reply that carries a caller's answer, whose codec arrives as a parameter.
pub type Reply(a) {
  Reply(id: String, answer: a)
}

// snips-start: parameter
/// Avoid on 2.1.x when the codec is sent: the `answer` parameter is used by a
/// later field, so every continuation after the first field captures it, as a
/// `let`-bound child codec would be. From 2.2.0 it is copied once.
pub fn captured_reply_codec(answer: Codec(a)) -> Codec(Reply(a)) {
  use id <- codec.field("id", codec.string(), get: fn(r) { r.id })
  use answer <- codec.field("answer", answer, get: fn(r) { r.answer })
  codec.success(Reply(id:, answer:))
}

/// On 2.1.x the first field keeps only the operations its callbacks call, so
/// no continuation captures the parameter; from 2.2.0 either order copies the
/// parameter once. This changes the order of the encoded members and of the
/// schema's properties; decoding accepts members in any order.
pub fn reply_codec(answer: Codec(a)) -> Codec(Reply(a)) {
  use answer <- codec.field("answer", answer, get: fn(r) { r.answer })
  use id <- codec.field("id", codec.string(), get: fn(r) { r.id })
  codec.success(Reply(id:, answer:))
}

// snips-end: parameter

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  let contact =
    Contact(
      name: option.Some("Ada"),
      email: option.Some("ada@example.com"),
      phone: option.None,
      company: option.None,
      role: option.None,
      city: option.None,
    )
  let answer = Answer("Found the owner", contact, option.None)
  let assert Ok(text) = codec.encode_json(answer_codec(), answer)
  // The two codecs agree on every conversion and on the schema.
  assert codec.encode_json(captured_answer_codec(), answer) == Ok(text)
  assert codec.decode_json(answer_codec(), text) == Ok(answer)
  assert codec.decode_json(captured_answer_codec(), text) == Ok(answer)
  assert codec.schema_json(answer_codec())
    == codec.schema_json(captured_answer_codec())
  // Both reply codecs decode the same JSON, whatever the member order.
  let reply = Reply("r-1", contact)
  let assert Ok(reply_text) =
    codec.encode_json(captured_reply_codec(contact_codec()), reply)
  assert codec.decode_json(reply_codec(contact_codec()), reply_text)
    == Ok(reply)
  "encoded: " <> text
}
