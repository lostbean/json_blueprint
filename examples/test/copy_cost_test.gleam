//// Sending a codec, or a value that holds one, to another process copies it
//// without sharing. From 2.2.0 a codec holds each input once, so a child
//// codec captured by a later field, or a run-time enum built before the
//// chain, is copied once. These checks hold the examples to that bound;
//// docs/CODEC-PRACTICE.md describes the same check for applications.

import examples/child_codecs
import examples/runtime_enum.{type Citation, Citation}
import gleam/list
import gleeunit/should
import json/blueprint/codec.{type Codec}

// snips-start: copy-size-test
@external(erlang, "examples_copy_cost_ffi", "flat_size_bytes")
@external(javascript, "./examples_copy_cost_ffi.mjs", "flat_size_bytes")
fn flat_size_bytes(term: a) -> Int

/// Copy size is a BEAM measure; on JavaScript the check is skipped.
fn copy_size(term: a, check: fn(Int) -> Nil) -> Nil {
  case flat_size_bytes(term) {
    -1 -> Nil
    bytes -> check(bytes)
  }
}

pub fn child_codecs_built_in_their_fields_stay_small_test() {
  use bytes <- copy_size(child_codecs.answer_codec())
  { bytes < 4096 } |> should.be_true
}

// snips-end: copy-size-test

pub fn a_let_bound_child_codec_is_copied_once_test() {
  use built <- copy_size(child_codecs.answer_codec())
  use captured <- copy_size(child_codecs.captured_answer_codec())
  use contact <- copy_size(child_codecs.contact_codec())
  // Holding the contact codec twice would add a whole second copy of it.
  { captured < built + contact + contact / 2 } |> should.be_true
}

pub fn a_codec_parameter_used_by_a_later_field_is_copied_once_test() {
  let contact = child_codecs.contact_codec()
  use first <- copy_size(child_codecs.reply_codec(contact))
  use later <- copy_size(child_codecs.captured_reply_codec(contact))
  use parameter <- copy_size(contact)
  { first < 4096 } |> should.be_true
  { later < first + parameter } |> should.be_true
}

pub fn a_prebuilt_runtime_enum_is_copied_once_test() {
  let offered = ["doc-1", "doc-2", "doc-3", "doc-4", "doc-5"]
  use in_field <- copy_size(runtime_enum.citation_codec(offered))
  use prebuilt <- copy_size(prebuilt_citation_codec(offered))
  use sources <- copy_size(
    codec.string_enum(list.map(offered, fn(id) { #(id, id) })),
  )
  { in_field < 16_384 } |> should.be_true
  // Holding the enum codec twice would add a whole second copy of it.
  { prebuilt < in_field + sources } |> should.be_true
}

// snips-start: prebuilt-enum
/// The enum codec built once before the chain: from 2.2.0 it is copied once
/// and not rebuilt per conversion. On 2.1.x every later continuation
/// captured the whole codec, so avoid this form there.
fn prebuilt_citation_codec(offered: List(String)) -> Codec(Citation) {
  let sources = codec.string_enum(list.map(offered, fn(id) { #(id, id) }))
  use claim <- codec.field("claim", codec.string(), get: fn(c: Citation) {
    c.claim
  })
  use source_ids <- codec.field("source_ids", codec.list(sources), get: fn(c) {
    c.source_ids
  })
  use note <- codec.optional_field("note", codec.string(), get: fn(c) { c.note })
  codec.success(Citation(claim:, source_ids:, note:))
}
// snips-end: prebuilt-enum
