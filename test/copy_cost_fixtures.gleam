//// Record-heavy codecs shaped like a tool input, shared by the copy-cost
//// tests and the benchmark: a record holding a list of records whose first
//// field is a record of optional fields.

import gleam/option.{type Option, None, Some}
import json/blueprint/codec.{type Codec}

pub type Regime {
  Simples
  Presumido
  Real
}

pub type Stage {
  Lead
  Active
  Churned
}

pub type Channel {
  Whatsapp
  Email
  Phone
}

pub type Profile {
  Profile(
    regime: Option(Regime),
    stage: Option(Stage),
    channel: Option(Channel),
    legal_name: Option(String),
    trade_name: Option(String),
    document: Option(String),
    city: Option(String),
    state: Option(String),
    employees: Option(Int),
    revenue: Option(Int),
    partner: Option(Bool),
    notes: Option(List(String)),
  )
}

pub type Entry {
  Entry(profile: Profile, id: Int, tags: List(String))
}

pub type AgentInput {
  AgentInput(entries: List(Entry))
}

pub type Batch(a) {
  Batch(items: List(a), cursor: Option(String))
}

pub type Maybe(a) {
  Maybe(item: Option(a), label: String)
}

pub type Envelope(a) {
  Envelope(body: a, label: String)
}

pub type WideEnvelope(a) {
  WideEnvelope(
    body: a,
    one: String,
    two: Int,
    three: Bool,
    four: Option(String),
    five: List(Int),
    six: Option(Regime),
  )
}

pub type Choice(a) {
  Chosen(a)
  Declined(String)
  Skipped
}

fn regime_codec() -> Codec(Regime) {
  codec.string_enum([
    #("simples", Simples),
    #("presumido", Presumido),
    #("real", Real),
  ])
}

fn stage_codec() -> Codec(Stage) {
  codec.string_enum([
    #("lead", Lead),
    #("active", Active),
    #("churned", Churned),
  ])
}

fn channel_codec() -> Codec(Channel) {
  codec.string_enum([
    #("whatsapp", Whatsapp),
    #("email", Email),
    #("phone", Phone),
  ])
}

pub fn profile_codec() -> Codec(Profile) {
  use regime <- codec.optional_field("regime", regime_codec(), get: fn(p) {
    p.regime
  })
  use stage <- codec.optional_field("stage", stage_codec(), get: fn(p) {
    p.stage
  })
  use channel <- codec.optional_field("channel", channel_codec(), get: fn(p) {
    p.channel
  })
  use legal_name <- codec.optional_field(
    "legal_name",
    codec.string(),
    get: fn(p) { p.legal_name },
  )
  use trade_name <- codec.optional_field(
    "trade_name",
    codec.string(),
    get: fn(p) { p.trade_name },
  )
  use document <- codec.optional_field("document", codec.string(), get: fn(p) {
    p.document
  })
  use city <- codec.optional_field("city", codec.string(), get: fn(p) { p.city })
  use state <- codec.optional_field("state", codec.string(), get: fn(p) {
    p.state
  })
  use employees <- codec.optional_field("employees", codec.int(), get: fn(p) {
    p.employees
  })
  use revenue <- codec.optional_field("revenue", codec.int(), get: fn(p) {
    p.revenue
  })
  use partner <- codec.optional_field("partner", codec.bool(), get: fn(p) {
    p.partner
  })
  use notes <- codec.optional_field(
    "notes",
    codec.list(codec.string()),
    get: fn(p) { p.notes },
  )
  codec.success(Profile(
    regime:,
    stage:,
    channel:,
    legal_name:,
    trade_name:,
    document:,
    city:,
    state:,
    employees:,
    revenue:,
    partner:,
    notes:,
  ))
}

pub fn entry_codec() -> Codec(Entry) {
  use profile <- codec.field("profile", profile_codec(), get: fn(e) {
    e.profile
  })
  use id <- codec.field("id", codec.int(), get: fn(e) { e.id })
  use tags <- codec.field("tags", codec.list(codec.string()), get: fn(e) {
    e.tags
  })
  codec.success(Entry(profile:, id:, tags:))
}

pub fn agent_input_codec() -> Codec(AgentInput) {
  use entries <- codec.field("entries", codec.list(entry_codec()), get: fn(i) {
    i.entries
  })
  codec.success(AgentInput(entries:))
}

/// A record whose first field is a list of `item`.
pub fn batch(item: Codec(a)) -> Codec(Batch(a)) {
  use items <- codec.field("items", codec.list(item), get: fn(b: Batch(a)) {
    b.items
  })
  use cursor <- codec.optional_field("cursor", codec.string(), get: fn(b) {
    b.cursor
  })
  codec.success(Batch(items:, cursor:))
}

/// A record whose first field is an optional `item`.
pub fn maybe(item: Codec(a)) -> Codec(Maybe(a)) {
  use item <- codec.optional_field("item", item, get: fn(m: Maybe(a)) { m.item })
  use label <- codec.field("label", codec.string(), get: fn(m) { m.label })
  codec.success(Maybe(item:, label:))
}

/// A record whose first field is `body`.
pub fn envelope(body: Codec(a)) -> Codec(Envelope(a)) {
  use body <- codec.field("body", body, get: fn(e: Envelope(a)) { e.body })
  use label <- codec.field("label", codec.string(), get: fn(e) { e.label })
  codec.success(Envelope(body:, label:))
}

/// Like `envelope`, with six more fields after the first.
pub fn wide_envelope(body: Codec(a)) -> Codec(WideEnvelope(a)) {
  use body <- codec.field("body", body, get: fn(e: WideEnvelope(a)) { e.body })
  use one <- codec.field("one", codec.string(), get: fn(e) { e.one })
  use two <- codec.field("two", codec.int(), get: fn(e) { e.two })
  use three <- codec.field("three", codec.bool(), get: fn(e) { e.three })
  use four <- codec.optional_field("four", codec.string(), get: fn(e) { e.four })
  use five <- codec.field("five", codec.list(codec.int()), get: fn(e) { e.five })
  use six <- codec.optional_field("six", regime_codec(), get: fn(e) { e.six })
  codec.success(WideEnvelope(body:, one:, two:, three:, four:, five:, six:))
}

/// A union with a payload variant of `item`.
pub fn choice(item: Codec(a)) -> Codec(Choice(a)) {
  codec.union({
    use chosen <- codec.variant("chosen", item, Chosen)
    use declined <- codec.variant("declined", codec.string(), Declined)
    use skipped <- codec.unit_variant("skipped", Skipped)
    codec.match(fn(choice) {
      case choice {
        Chosen(item) -> chosen(item)
        Declined(reason) -> declined(reason)
        Skipped -> skipped
      }
    })
  })
}

pub fn nobody() -> Profile {
  Profile(
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
    None,
  )
}

pub fn somebody(seed: Int) -> Profile {
  Profile(
    regime: Some(Presumido),
    stage: Some(Active),
    channel: None,
    legal_name: Some("Padaria Estrela do Norte Ltda"),
    trade_name: Some("Estrela do Norte"),
    document: Some("12.345.678/0001-90"),
    city: Some("Belo Horizonte"),
    state: None,
    employees: Some(seed),
    revenue: Some(seed * 1000),
    partner: Some(True),
    notes: Some([
      "prefere mensagens de manhã",
      "contador anterior: Contabilizei",
    ]),
  )
}

pub fn agent_input(count: Int) -> AgentInput {
  AgentInput(entries: entries(count, []))
}

fn entries(count: Int, done: List(Entry)) -> List(Entry) {
  case count <= 0 {
    True -> done
    False ->
      entries(count - 1, [
        Entry(profile: somebody(count), id: count, tags: ["novo", "prioridade"]),
        ..done
      ])
  }
}
