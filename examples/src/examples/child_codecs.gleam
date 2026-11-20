//// Building child codecs where they are used.
////
//// `use … <- codec.field` turns the rest of a record into a continuation, and
//// a record codec keeps that continuation in several callbacks. A value bound
//// with `let` before the chain and used by a later field is captured by the
//// continuation. Inside one process that capture is shared, but a process copy
//// (a message, a spawn argument, a child specification) does not preserve
//// sharing: the captured child codec is copied once per callback that holds it.
////
//// Build each child codec in the field that uses it, by calling a function in
//// the field's codec argument. Both codecs below convert and describe the same
//// JSON; `captured_answer_codec` shows the pattern to avoid, and the examples
//// test measures how much more it costs to copy on the BEAM.

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
/// Avoid: `contact` is bound before the chain and used by later fields, so
/// every continuation after the first field captures it.
pub fn captured_answer_codec() -> Codec(Answer) {
  let contact = contact_codec()
  use summary <- codec.field("summary", codec.string(), get: fn(a) { a.summary })
  use primary <- codec.field("primary", contact, get: fn(a) { a.primary })
  use backup <- codec.optional_field("backup", contact, get: fn(a) { a.backup })
  codec.success(Answer(summary:, primary:, backup:))
}

// snips-end: let-bound

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
  "encoded: " <> text
}
