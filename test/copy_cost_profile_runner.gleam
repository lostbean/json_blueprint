//// Prints what the record-heavy fixture codecs cost to copy between BEAM
//// processes: `gleam run -m copy_cost_profile_runner`. An observation, like
//// the benchmarks; the copy-cost tests hold the growth rule.

import copy_cost_fixtures as fixtures
import gleam/int
import gleam/io
import gleam/string
import json/blueprint/codec

@external(erlang, "copy_cost_ffi", "flat_size_words")
@external(javascript, "./copy_cost_ffi.mjs", "flat_size_words")
fn flat_size_words(term: a) -> Int

@external(erlang, "copy_cost_ffi", "shared_size_words")
@external(javascript, "./copy_cost_ffi.mjs", "shared_size_words")
fn shared_size_words(term: a) -> Int

@external(erlang, "copy_cost_ffi", "external_bytes")
@external(javascript, "./copy_cost_ffi.mjs", "external_bytes")
fn external_bytes(term: a) -> Int

fn report(name: String, term: a) -> Nil {
  io.println(
    string.pad_end(name, 34, " ")
    <> string.pad_start(int.to_string(flat_size_words(term) * 8), 14, " ")
    <> string.pad_start(int.to_string(external_bytes(term)), 14, " ")
    <> string.pad_start(int.to_string(shared_size_words(term) * 8), 14, " "),
  )
}

pub fn main() -> Nil {
  case flat_size_words(Nil) {
    -1 -> io.println("copied size is a BEAM measure; run on the Erlang target")
    _ -> profile()
  }
}

fn profile() -> Nil {
  io.println(
    string.pad_end("codec", 34, " ")
    <> string.pad_start("copied bytes", 14, " ")
    <> string.pad_start("term_to_binary", 14, " ")
    <> string.pad_start("heap bytes", 14, " "),
  )
  let profile = fixtures.profile_codec()
  report("profile (12 optional fields)", profile)
  report("entry (profile first, 2 more)", fixtures.entry_codec())
  report("agent input (list of entry)", fixtures.agent_input_codec())

  let batch1 = fixtures.batch(profile)
  let batch2 = fixtures.batch(batch1)
  let batch3 = fixtures.batch(batch2)
  let batch4 = fixtures.batch(batch3)
  report("record>list>profile depth 1", batch1)
  report("record>list>profile depth 2", batch2)
  report("record>list>profile depth 3", batch3)
  report("record>list>profile depth 4", batch4)

  let envelope1 = fixtures.envelope(profile)
  let envelope2 = fixtures.envelope(envelope1)
  let envelope3 = fixtures.envelope(envelope2)
  let envelope4 = fixtures.envelope(envelope3)
  report("record>profile depth 1", envelope1)
  report("record>profile depth 2", envelope2)
  report("record>profile depth 3", envelope3)
  report("record>profile depth 4", envelope4)
  report("wide record>profile depth 1", fixtures.wide_envelope(profile))

  let choice1 = fixtures.choice(profile)
  let choice2 = fixtures.choice(choice1)
  let choice3 = fixtures.choice(choice2)
  report("union>profile depth 1", choice1)
  report("union>profile depth 2", choice2)
  report("union>profile depth 3", choice3)

  let nullable1 = codec.nullable(profile)
  let nullable2 = codec.nullable(nullable1)
  let nullable3 = codec.nullable(nullable2)
  report("nullable>profile depth 1", nullable1)
  report("nullable>profile depth 2", nullable2)
  report("nullable>profile depth 3", nullable3)

  let pair1 = codec.pair(codec.int(), profile)
  let pair2 = codec.pair(codec.int(), pair1)
  let pair3 = codec.pair(codec.int(), pair2)
  report("pair>profile depth 1", pair1)
  report("pair>profile depth 2", pair2)
  report("pair>profile depth 3", pair3)
}
