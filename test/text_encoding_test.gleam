//// `encode_json` writes the bytes that rendering `encode`'s Value writes, and
//// fails with the same errors at the same paths, for every combinator and
//// across strings, numbers and failures that differ by target (ADR 0016,
//// ADR 0018). Applications store this text, so the corpus is exhaustive per
//// combinator rather than sampled.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import json/blueprint/codec.{type Codec}
import json/blueprint/number
import json/blueprint/value.{type Value}

fn same_text(codec: Codec(a), items: List(a)) -> Nil {
  list.each(items, fn(item) {
    codec.encode_json(codec, item)
    |> should.equal(codec.encode(codec, item) |> result.map(value.to_string))
  })
}

fn exact(text: String) -> number.Number {
  let assert Ok(found) = number.parse(text, number.default_limits())
  found
}

fn big(digits: String) -> Int {
  let assert Ok(found) = int.parse(digits)
  found
}

const strings = [
  "", "plain", "quote \" backslash \\ slash /", "tab\tnew\nline\rreturn",
  "control \u{0000} \u{0001} \u{001F} \u{007F}", "accents é ü ß ñ",
  "emoji 😀 and flag 🇧🇷", "line sep \u{2028} para sep \u{2029}", "cjk 漢字 かな",
  "zero width \u{200B} joiner \u{200D}", "<script>&amp;</script>",
]

pub fn strings_render_the_same_test() {
  same_text(codec.string(), strings)
  same_text(codec.list(codec.string()), [strings, []])
  same_text(codec.string_enum(list.index_map(strings, fn(s, i) { #(s, i) })), [
    0, 3, 4, 7, 99,
  ])
}

pub fn integers_render_the_same_test() {
  same_text(codec.int(), [
    0,
    -1,
    1,
    42,
    -9_007_199_254_740_991,
    9_007_199_254_740_991,
    big("9007199254740992"),
    big("123456789012345678901234"),
    big("1234567890123456789012345"),
  ])
  same_text(codec.integer_between(-5, 5), [-5, 0, 5, 6, -6])
}

pub fn floats_and_numbers_render_the_same_test() {
  same_text(codec.float(), [
    0.0,
    -0.0,
    1.5,
    -2.25,
    0.1,
    1.0e-7,
    1.0e21,
    1.7976931348623157e308,
    5.0e-324,
    float.negate(1.0e300),
  ])
  same_text(codec.number(), [
    exact("0"),
    exact("-0"),
    exact("1e400"),
    exact("-1.5e-400"),
    exact("123456789012345678901234567890"),
    exact("0.000000000000000000001"),
  ])
  same_text(codec.number_between(exact("-1.5"), exact("1e3")), [
    exact("-1.5"),
    exact("1000"),
    exact("1001"),
  ])
}

pub fn values_render_the_same_test() {
  same_text(codec.value(), [
    value.Null,
    value.Bool(True),
    value.Array([value.String("x"), value.Number(exact("1e400"))]),
    value.Object([#("a", value.Object([])), #("\u{2028}", value.Null)]),
  ])
}

type Shape {
  Circle(Int)
  Named(String)
  Empty
}

fn shape_codec() -> Codec(Shape) {
  codec.union({
    use circle <- codec.variant("circle", codec.integer_between(0, 9), Circle)
    use named <- codec.variant("named\"tag", codec.string(), Named)
    use empty <- codec.unit_variant("empty", Empty)
    codec.match(fn(shape) {
      case shape {
        Circle(r) -> circle(r)
        Named(n) -> named(n)
        Empty -> empty
      }
    })
  })
}

type Record {
  Record(
    id: Int,
    note: Option(String),
    shape: Shape,
    pair: #(Bool, Option(Value)),
    tags: List(String),
  )
}

fn record_codec() -> Codec(Record) {
  use id <- codec.field("id", codec.int(), get: fn(r: Record) { r.id })
  use note <- codec.optional_field("note \u{2028}", codec.string(), get: fn(r) {
    r.note
  })
  use shape <- codec.field("shape", shape_codec(), get: fn(r) { r.shape })
  use pair <- codec.field(
    "pair",
    codec.pair(codec.bool(), codec.nullable(codec.value())),
    get: fn(r) { r.pair },
  )
  use tags <- codec.field(
    "tags",
    codec.list(codec.describe(codec.string(), "a tag")),
    get: fn(r) { r.tags },
  )
  codec.success(Record(id:, note:, shape:, pair:, tags:))
}

pub fn records_and_unions_render_the_same_test() {
  same_text(record_codec(), [
    Record(1, None, Empty, #(True, None), []),
    Record(2, Some("é \u{2028}"), Circle(3), #(False, Some(value.Bool(True))), [
      "a", "\"",
    ]),
    Record(3, None, Named("😀"), #(True, Some(value.Array([]))), ["x"]),
    // Failures: a bound, a null inside nullable, an unsafe integer.
    Record(4, None, Circle(10), #(True, None), []),
    Record(5, None, Empty, #(True, Some(value.Null)), []),
    Record(big("1234567890123456789012345"), None, Empty, #(True, None), []),
  ])
  same_text(codec.list(record_codec()), [
    [],
    [
      Record(1, None, Empty, #(True, None), []),
      Record(6, None, Circle(99), #(True, None), []),
    ],
  ])
}

pub fn mappings_render_the_same_test() {
  let even =
    codec.try_map(
      codec.int(),
      decode: Ok,
      encode: fn(x) {
        case x % 2 {
          0 -> Ok(x)
          _ -> Error("odd \"" <> int.to_string(x) <> "\"")
        }
      },
      placeholder: 0,
    )
  same_text(even, [2, 3])
  same_text(
    codec.map(codec.string(), decode: string.length, encode: fn(n) {
      string.repeat("é", n)
    }),
    [0, 3],
  )
  same_text(
    codec.custom(
      encode: fn(x: Int) {
        case x {
          0 -> Error(codec.encode_failure("zero"))
          _ -> Ok(value.String(int.to_string(x)))
        }
      },
      decode: fn(_) { Ok(0) },
      schema: None,
      placeholder: 0,
    ),
    [0, 7],
  )
  same_text(codec.success("constant"), ["ignored"])
}
