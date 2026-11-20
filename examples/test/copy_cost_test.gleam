//// Sending a codec, or a value that holds one, to another process copies it
//// without sharing. These checks hold the examples to a copy-size bound;
//// docs/CODEC-PRACTICE.md describes the same check for applications.

import examples/child_codecs
import examples/runtime_enum.{type Citation, Citation}
import gleam/list
import gleeunit/should
import json/blueprint/codec.{type Codec}

// snips-start: copy-size-test
@external(erlang, "copy_cost_ffi", "flat_size_bytes")
@external(javascript, "./copy_cost_ffi.mjs", "flat_size_bytes")
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

pub fn a_let_bound_child_codec_is_copied_once_per_callback_test() {
  use built <- copy_size(child_codecs.answer_codec())
  use captured <- copy_size(child_codecs.captured_answer_codec())
  { captured > built * 10 } |> should.be_true
}

pub fn a_runtime_enum_built_in_its_field_copies_less_than_a_prebuilt_one_test() {
  let offered = ["doc-1", "doc-2", "doc-3", "doc-4", "doc-5"]
  use in_field <- copy_size(runtime_enum.citation_codec(offered))
  use prebuilt <- copy_size(prebuilt_citation_codec(offered))
  { in_field < 16_384 } |> should.be_true
  { in_field * 3 < prebuilt } |> should.be_true
}

// snips-start: prebuilt-enum
/// Avoid: the enum codec is built once before the chain, so every later
/// continuation captures the whole codec rather than its label strings.
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
