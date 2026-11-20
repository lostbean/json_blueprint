//// Each public combinator holds each of its inputs once (ADR 0018): built
//// from inputs that share nothing, a codec copies at its in-heap size, apart
//// from one reference per union variant, held by the variant and by its
//// tagging function. `copy_cost_coverage_check.py` fails when a public
//// function of the package returning `Codec` or `Union` has no
//// `*_holds_its_inputs_once_test` here (prefixed by its module outside
//// `codec`). A combinator that takes a child codec gets one with captured
//// state, so a child held twice shows. Flat size is a BEAM measure; on
//// JavaScript these checks pass without measuring.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit/should
import json/blueprint/codec.{type Codec}
import json/blueprint/codegen
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value.{type Value}

@external(erlang, "copy_cost_ffi", "flat_size_words")
@external(javascript, "./copy_cost_ffi.mjs", "flat_size_words")
fn flat_size_words(term: a) -> Int

@external(erlang, "copy_cost_ffi", "shared_size_words")
@external(javascript, "./copy_cost_ffi.mjs", "shared_size_words")
fn shared_size_words(term: a) -> Int

@external(erlang, "copy_cost_ffi", "round_trip")
@external(javascript, "./copy_cost_ffi.mjs", "round_trip")
fn round_trip(term: a) -> a

@external(erlang, "copy_cost_ffi", "through_process")
@external(javascript, "./copy_cost_ffi.mjs", "through_process")
fn through_process(term: a) -> a

@external(erlang, "copy_cost_ffi", "reference_words")
@external(javascript, "./copy_cost_ffi.mjs", "reference_words")
fn reference_words() -> Int

/// Copies at its in-heap size, plus `extra` words.
fn held_once(term: a, extra: Int) -> Nil {
  case flat_size_words(Nil) {
    -1 -> Nil
    _ ->
      { flat_size_words(term) - shared_size_words(term) } |> should.equal(extra)
  }
}

fn exact(text: String) -> number.Number {
  let assert Ok(found) = number.parse(text, number.default_limits())
  found
}

pub fn string_holds_its_inputs_once_test() {
  held_once(codec.string(), 0)
}

pub fn int_holds_its_inputs_once_test() {
  held_once(codec.int(), 0)
}

pub fn float_holds_its_inputs_once_test() {
  held_once(codec.float(), 0)
}

pub fn number_holds_its_inputs_once_test() {
  held_once(codec.number(), 0)
}

pub fn bool_holds_its_inputs_once_test() {
  held_once(codec.bool(), 0)
}

pub fn value_holds_its_inputs_once_test() {
  held_once(codec.value(), 0)
}

pub fn integer_between_holds_its_inputs_once_test() {
  held_once(codec.integer_between(-7, 7000), 0)
}

pub fn number_between_holds_its_inputs_once_test() {
  held_once(codec.number_between(exact("-1.5"), exact("2.5e3")), 0)
}

pub fn string_enum_holds_its_inputs_once_test() {
  held_once(codec.string_enum([#("north", 1), #("south", 2), #("east", 3)]), 0)
}

/// A child codec with captured state: a copy of a combinator that held it
/// twice would show the labels twice.
fn stateful() -> Codec(Int) {
  codec.string_enum([#("one", 1), #("two", 2), #("three", 3)])
}

pub fn describe_holds_its_inputs_once_test() {
  held_once(codec.describe(stateful(), "a count"), 0)
}

pub fn list_holds_its_inputs_once_test() {
  held_once(codec.list(stateful()), 0)
}

pub fn pair_holds_its_inputs_once_test() {
  held_once(codec.pair(stateful(), codec.string_enum([#("left", 0)])), 0)
}

pub fn nullable_holds_its_inputs_once_test() {
  held_once(codec.nullable(codec.integer_between(1, 3)), 0)
}

type Point {
  Point(x: Int, label: Option(String))
}

pub fn field_holds_its_inputs_once_test() {
  held_once(
    {
      use x <- codec.field("x", stateful(), get: fn(p: Point) { p.x })
      codec.success(Point(x:, label: None))
    },
    0,
  )
}

pub fn optional_field_holds_its_inputs_once_test() {
  held_once(
    {
      use label <- codec.optional_field("label", labels_codec(), get: fn(p) {
        p.label
      })
      codec.success(Point(x: 0, label:))
    },
    0,
  )
}

pub fn success_holds_its_inputs_once_test() {
  held_once(codec.success(Point(x: 1, label: Some("origin"))), 0)
}

type Shape {
  Circle(Int)
  Square(Int)
  Empty
}

fn shape_codec() -> Codec(Shape) {
  codec.union({
    use circle <- codec.variant("circle", stateful(), Circle)
    use square <- codec.variant("square", codec.integer_between(0, 9), Square)
    use empty <- codec.unit_variant("empty", Empty)
    codec.match(fn(shape) {
      case shape {
        Circle(r) -> circle(r)
        Square(s) -> square(s)
        Empty -> empty
      }
    })
  })
}

/// One reference per variant is held twice: by the variant and by the
/// tagging function or tagged value that `match` holds.
pub fn union_holds_its_inputs_once_test() {
  held_once(shape_codec(), 3 * reference_words())
}

pub fn variant_holds_its_inputs_once_test() {
  held_once(
    codec.union({
      use circle <- codec.variant("circle", stateful(), Circle)
      codec.match(fn(_) { circle(1) })
    }),
    reference_words(),
  )
}

pub fn unit_variant_holds_its_inputs_once_test() {
  held_once(
    codec.union({
      use empty <- codec.unit_variant("empty", Empty)
      codec.match(fn(_) { empty })
    }),
    reference_words(),
  )
}

pub fn match_holds_its_inputs_once_test() {
  held_once(codec.match(fn(_: Shape) { panic }), 0)
}

pub fn map_holds_its_inputs_once_test() {
  held_once(
    codec.map(stateful(), decode: fn(x) { Circle(x) }, encode: fn(shape) {
      case shape {
        Circle(r) -> r
        _ -> 0
      }
    }),
    0,
  )
}

pub fn try_map_holds_its_inputs_once_test() {
  held_once(
    codec.try_map(stateful(), decode: Ok, encode: Ok, placeholder: 41),
    0,
  )
}

pub fn custom_holds_its_inputs_once_test() {
  held_once(
    codec.custom(
      encode: fn(x: Int) { Ok(value.String(int.to_string(x))) },
      decode: fn(_: Value) { Ok(3) },
      schema: option.from_result(codec.schema(codec.string())),
      placeholder: 5,
    ),
    0,
  )
}

pub fn generated_holds_its_inputs_once_test() {
  let assert Ok(schema) = codec.schema(codec.int())
  held_once(
    codec.generated(
      encode: codec.encode(codec.int(), _),
      decode: codec.decode(codec.int(), _),
      strict_decode: fn(_) { Ok(0) },
      text_encode: codec.encode_json(codec.int(), _),
      schema:,
      placeholder: fn() { 0 },
    ),
    0,
  )
}

type Holder(a) {
  Holder(id: Int, body: a)
}

fn holder(body: Codec(a)) -> Codec(Holder(a)) {
  use id <- codec.field("id", codec.int(), get: fn(h: Holder(a)) { h.id })
  use body <- codec.field("body", body, get: fn(h) { h.body })
  codec.success(Holder(id:, body:))
}

/// A codec captured by a later field is copied once.
pub fn a_codec_used_by_a_later_field_is_copied_once_test() {
  case flat_size_words(Nil) {
    -1 -> Nil
    _ -> {
      let body = shape_codec()
      let held = holder(body)
      let around_int = holder(codec.int())
      {
        flat_size_words(held)
        <= flat_size_words(body) + flat_size_words(around_int)
      }
      |> should.be_true
    }
  }
}

fn labels(count: Int) -> List(#(String, Int)) {
  int.range(0, count, [], fn(done, index) {
    [#("label-" <> int.to_string(index), index), ..done]
  })
}

/// Each run-time label adds its own pair and one list cell, nothing more.
pub fn a_runtime_label_costs_its_own_data_test() {
  case flat_size_words(Nil) {
    -1 -> Nil
    _ -> {
      let fewer = labels(20)
      let more = labels(21)
      let assert [added, ..] = more
      let step =
        flat_size_words(codec.string_enum(more))
        - flat_size_words(codec.string_enum(fewer))
      step |> should.equal(flat_size_words(added) + 2)
    }
  }
}

fn labels_codec() -> Codec(String) {
  codec.string_enum([#("origin", "origin"), #("target", "target")])
}

pub fn contract_value_codec_holds_its_inputs_once_test() {
  let assert Ok(shapes) = contract.from_codec(shape_codec())
  held_once(contract.value_codec(shapes), 0)
}

/// A generated definition's runtime codec, eight fields nested in `combine`.
/// The fields use bounded integers: input-free leaves such as `codegen.int()`
/// are one module literal, which `erts_debug:flat_size` counts per reference
/// although a copy does not copy it.
pub fn codegen_runtime_holds_its_inputs_once_test() {
  let properties =
    codegen.combine(
      codegen.combine(
        codegen.combine(
          codegen.required("a", codegen.integer_between(0, 10)),
          codegen.required("b", codegen.integer_between(0, 20)),
        ),
        codegen.combine(
          codegen.required("c", codegen.integer_between(0, 30)),
          codegen.required("d", codegen.integer_between(0, 40)),
        ),
      ),
      codegen.combine(
        codegen.combine(
          codegen.required("e", codegen.integer_between(0, 50)),
          codegen.required("f", codegen.integer_between(0, 60)),
        ),
        codegen.combine(
          codegen.required("g", codegen.integer_between(0, 70)),
          codegen.required("h", codegen.integer_between(0, 80)),
        ),
      ),
    )
  held_once(codegen.runtime(codegen.object(properties)), 0)
}

/// A union codec converts the same after another process received it and
/// after an external-format round trip: variant identities survive copies.
pub fn a_copied_union_codec_converts_the_same_test() {
  let shapes = codec.list(shape_codec())
  let values = [Circle(2), Square(3), Empty]
  let assert Ok(text) = codec.encode_json(shapes, values)
  [
    through_process(shapes),
    round_trip(shapes),
    round_trip(through_process(shapes)),
  ]
  |> list.each(fn(copied) {
    codec.encode_json(copied, values) |> should.equal(Ok(text))
    codec.decode_json(copied, text) |> should.equal(Ok(values))
  })
}
