//// Sending a codec to another process copies it without preserving sharing,
//// so its copied size is its flat size. A combinator whose callbacks each
//// retain the whole child codec multiplies that size at every nesting layer.
//// These tests hold every combinator to additive growth.

import copy_cost_fixtures as fixtures
import gleeunit/should
import json/blueprint/codec.{type Codec}

@external(erlang, "copy_cost_ffi", "flat_size_words")
@external(javascript, "./copy_cost_ffi.mjs", "flat_size_words")
fn flat_size_words(term: a) -> Int

/// Flat size is a BEAM measure; JavaScript reports -1 and skips the check.
fn on_beam(check: fn() -> Nil) -> Nil {
  case flat_size_words(Nil) {
    -1 -> Nil
    _ -> check()
  }
}

/// Each extra layer adds the same number of words.
fn grows_by_equal_steps(one: Int, two: Int, three: Int, four: Int) -> Nil {
  let step = two - one
  { step > 0 } |> should.be_true
  { three - two } |> should.equal(step)
  { four - three } |> should.equal(step)
}

fn layers(
  base: Codec(a),
  wrap: fn(Codec(a)) -> Codec(a),
  check: fn(Int, Int, Int, Int) -> Nil,
) -> Nil {
  use <- on_beam
  let one = wrap(base)
  let two = wrap(one)
  let three = wrap(two)
  let four = wrap(three)
  check(
    flat_size_words(one),
    flat_size_words(two),
    flat_size_words(three),
    flat_size_words(four),
  )
}

pub fn agent_input_copy_cost_stays_near_its_innermost_record_test() {
  use <- on_beam
  let profile = flat_size_words(fixtures.profile_codec())
  let input = flat_size_words(fixtures.agent_input_codec())
  // Two record layers and a list around the profile record.
  { input < profile * 3 } |> should.be_true
}

pub fn record_of_list_of_record_copy_cost_grows_by_equal_steps_test() {
  use <- on_beam
  let one = fixtures.batch(fixtures.profile_codec())
  let two = fixtures.batch(one)
  let three = fixtures.batch(two)
  let four = fixtures.batch(three)
  grows_by_equal_steps(
    flat_size_words(one),
    flat_size_words(two),
    flat_size_words(three),
    flat_size_words(four),
  )
}

pub fn optional_first_field_copy_cost_grows_by_equal_steps_test() {
  use <- on_beam
  let one = fixtures.maybe(fixtures.profile_codec())
  let two = fixtures.maybe(one)
  let three = fixtures.maybe(two)
  let four = fixtures.maybe(three)
  grows_by_equal_steps(
    flat_size_words(one),
    flat_size_words(two),
    flat_size_words(three),
    flat_size_words(four),
  )
}

// A record describes itself by continuing from its first field's placeholder,
// so its decoders and schema carry one small thunk per enclosing record. The
// step may grow by those thunks, never by a multiple of the child.
pub fn record_in_record_copy_cost_grows_by_bounded_steps_test() {
  use <- on_beam
  let one = fixtures.envelope(fixtures.profile_codec())
  let two = fixtures.envelope(one)
  let three = fixtures.envelope(two)
  let four = fixtures.envelope(three)
  let five = fixtures.envelope(four)
  let first_step = flat_size_words(two) - flat_size_words(one)
  let last_step = flat_size_words(five) - flat_size_words(four)
  { first_step > 0 } |> should.be_true
  { last_step - first_step <= 3 * 64 } |> should.be_true
  { flat_size_words(five) < flat_size_words(one) * 4 } |> should.be_true
}

pub fn wider_records_cost_no_more_to_copy_per_layer_test() {
  use <- on_beam
  let narrow = flat_size_words(fixtures.envelope(fixtures.profile_codec()))
  let wide = flat_size_words(fixtures.wide_envelope(fixtures.profile_codec()))
  { wide <= narrow + 64 } |> should.be_true
}

pub fn nullable_copy_cost_grows_by_equal_steps_test() {
  use <- on_beam
  let one = codec.nullable(fixtures.profile_codec())
  let two = codec.nullable(one)
  let three = codec.nullable(two)
  let four = codec.nullable(three)
  grows_by_equal_steps(
    flat_size_words(one),
    flat_size_words(two),
    flat_size_words(three),
    flat_size_words(four),
  )
}

pub fn pair_copy_cost_grows_by_equal_steps_test() {
  use <- on_beam
  let one = codec.pair(codec.int(), fixtures.profile_codec())
  let two = codec.pair(codec.int(), one)
  let three = codec.pair(codec.int(), two)
  let four = codec.pair(codec.int(), three)
  grows_by_equal_steps(
    flat_size_words(one),
    flat_size_words(two),
    flat_size_words(three),
    flat_size_words(four),
  )
}

pub fn union_copy_cost_grows_by_equal_steps_test() {
  use <- on_beam
  let one = fixtures.choice(fixtures.profile_codec())
  let two = fixtures.choice(one)
  let three = fixtures.choice(two)
  let four = fixtures.choice(three)
  grows_by_equal_steps(
    flat_size_words(one),
    flat_size_words(two),
    flat_size_words(three),
    flat_size_words(four),
  )
}

pub fn map_copy_cost_grows_by_equal_steps_test() {
  layers(
    fixtures.profile_codec(),
    codec.map(_, decode: fn(item) { item }, encode: fn(item) { item }),
    grows_by_equal_steps,
  )
}

pub fn try_map_copy_cost_grows_by_equal_steps_test() {
  let base = fixtures.profile_codec()
  layers(
    base,
    codec.try_map(_, decode: Ok, encode: Ok, placeholder: fixtures.nobody()),
    grows_by_equal_steps,
  )
}

// A description replaces the schema callback and keeps the others as they are.
pub fn describe_copy_cost_adds_only_a_schema_callback_test() {
  use <- on_beam
  let base = fixtures.profile_codec()
  let once = codec.describe(base, "a profile")
  let twice = codec.describe(once, "the profile")
  { flat_size_words(once) <= flat_size_words(base) + 16 } |> should.be_true
  { flat_size_words(twice) <= flat_size_words(once) + 16 } |> should.be_true
}
