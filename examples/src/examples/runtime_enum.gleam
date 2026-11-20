//// A choice whose labels are known only at run time.
////
//// Some enums come from data: the source ids offered to one model call, the
//// stages configured for one tenant. The typed-definition generator cannot
//// produce them, so build them with combinators. Capture the small data, the
//// label pairs converted once, and build `codec.string_enum` inside the field
//// that uses it. A prebuilt enum codec bound before the `use` chain would be
//// captured by every later continuation and copied once per callback when
//// the codec is sent to another process. Rebuilding the enum costs
//// microseconds per conversion.
////
//// Labels from data can repeat, so check the codec once where the data
//// arrives; `codec.check` returns the problem instead of panicking later.

import gleam/list
import gleam/option.{type Option}
import gleam/result
import json/blueprint/codec.{type Codec}

pub type Citation {
  Citation(claim: String, source_ids: List(String), note: Option(String))
}

// snips-start: citation-codec
/// The citation codec for one run, which may cite only `offered` sources.
pub fn citation_codec(offered: List(String)) -> Codec(Citation) {
  // Small data: one label pair per offered id, converted once.
  let labels = list.map(offered, fn(id) { #(id, id) })
  use claim <- codec.field("claim", codec.string(), get: fn(c) { c.claim })
  use source_ids <- codec.field(
    "source_ids",
    // The enum codec is built here, where the field uses it.
    codec.list(codec.string_enum(labels)),
    get: fn(c) { c.source_ids },
  )
  use note <- codec.optional_field("note", codec.string(), get: fn(c) { c.note })
  codec.success(Citation(claim:, source_ids:, note:))
}

// snips-end: citation-codec

/// The codec for `offered`, or why those ids cannot label an enum.
pub fn checked_citation_codec(
  offered: List(String),
) -> Result(Codec(Citation), codec.DefinitionError) {
  let citation = citation_codec(offered)
  codec.check(citation) |> result.replace(citation)
}

/// Runs the example and returns what it shows.
pub fn demonstrate() -> String {
  let assert Ok(citation) = checked_citation_codec(["doc-1", "doc-2"])
  let text = "{\"claim\":\"Paid in May\",\"source_ids\":[\"doc-2\"]}"
  let assert Ok(decoded) = codec.decode_json(citation, text)
  assert decoded == Citation("Paid in May", ["doc-2"], option.None)
  let assert Error(error) =
    codec.decode_json(
      citation,
      "{\"claim\":\"Paid in May\",\"source_ids\":[\"doc-9\"]}",
    )
  let refused = codec.describe_decode_error(error)
  assert refused == "$[\"source_ids\"][0]: unknown enum label"
  let assert Error(_) = checked_citation_codec(["doc-1", "doc-1"])
  let assert Ok(schema) = codec.schema_json(citation)
  "decoded: "
  <> decoded.claim
  <> "\nrefused: "
  <> refused
  <> "\nschema: "
  <> schema
}
