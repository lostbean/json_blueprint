import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value

pub type Record {
  Record(first: Int, total: Int, note: Option(Option(String)))
}

fn record_codec() -> codec.Codec(Record) {
  use first <- codec.field("first", codec.int(), get: fn(r) { r.first })
  use total <- codec.field(
    "total",
    codec.try_map(
      codec.int(),
      decode: fn(total) {
        case total == first * 2 {
          True -> Ok(total)
          False -> Error("total must be twice first")
        }
      },
      encode: Ok,
      placeholder: 0,
    ),
    get: fn(r) { r.total },
  )
  use note <- codec.optional_field(
    "note",
    codec.nullable(codec.string()),
    get: fn(r) { r.note },
  )
  codec.success(Record(first, total, note))
}

pub fn record_text_decoding_preserves_continuations_and_error_order_test() {
  let c = record_codec()
  list.each(
    [
      "{\"first\":2,\"total\":4}",
      "{\"total\":4,\"note\":null,\"first\":2}",
      "{\"first\":2,\"total\":4,\"note\":\"ok\"}",
      "{\"first\":2,\"total\":3,\"extra\":true}",
      "{\"total\":4,\"extra\":true}",
      "{\"first\":2,\"total\":4,\"extra\":true}",
    ],
    fn(text) {
      let assert Ok(raw) = value.parse(text, value.default_limits())
      codec.decode_json(c, text) |> should.equal(codec.decode(c, raw))
    },
  )
  codec.decode_json(c, "{\"first\":2,\"total\":4,\"note\":null}")
  |> should.equal(Ok(Record(2, 4, Some(None))))
}

pub fn native_primitive_and_collection_paths_match_value_decoding_test() {
  let c = codec.list(codec.pair(codec.int(), codec.nullable(codec.float())))
  list.each(
    [
      "[[12.0,0.1],[1.2e1,null]]",
      "[[1,2],[3,\"bad\"]]",
      "[[1]]",
      "[false]",
      "false",
    ],
    fn(text) {
      let assert Ok(raw) = value.parse(text, value.default_limits())
      codec.decode_json(c, text) |> should.equal(codec.decode(c, raw))
    },
  )
}

pub fn native_custom_codec_materializes_only_its_value_test() {
  let exact =
    codec.custom(
      encode: fn(n) { Ok(value.Number(n)) },
      decode: fn(raw) { codec.decode(codec.number(), raw) },
      schema: None,
      placeholder: codec.placeholder(codec.number()),
    )
  let c = codec.pair(codec.string(), exact)
  let assert Ok(expected) =
    number.parse("123456789012345678901234567890.1", number.default_limits())
  codec.decode_json(c, "[\"exact\",123456789012345678901234567890.1]")
  |> should.equal(Ok(#("exact", expected)))
}

pub fn native_text_parsing_has_no_depth_admission_limit_test() {
  let text = string.repeat("[", 80) <> "null" <> string.repeat("]", 80)
  codec.decode_json(codec.string(), text)
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedString)))
}

pub type Choice {
  Empty
  Label(String)
  Count(Int)
}

fn choice_codec() -> codec.Codec(Choice) {
  codec.union({
    use empty <- codec.unit_variant("empty", Empty)
    use label <- codec.variant("label", codec.string(), Label)
    use count <- codec.variant("count", codec.int(), Count)
    codec.match(fn(choice) {
      case choice {
        Empty -> empty
        Label(text) -> label(text)
        Count(n) -> count(n)
      }
    })
  })
}

pub fn native_tagged_union_errors_match_value_decoding_test() {
  let c = choice_codec()
  list.each(
    [
      "{\"tag\":\"empty\"}",
      "{\"value\":\"hello\",\"tag\":\"label\"}",
      "{\"tag\":\"count\",\"value\":2.0}",
      "{\"tag\":\"empty\",\"value\":null}",
      "{\"tag\":\"label\"}",
      "{\"tag\":\"label\",\"value\":false}",
      "{\"tag\":\"missing\"}",
      "{\"tag\":false}",
      "{\"value\":2}",
      "{\"extra\":true}",
      "[]",
    ],
    fn(text) {
      let assert Ok(raw) = value.parse(text, value.default_limits())
      codec.decode_json(c, text) |> should.equal(codec.decode(c, raw))
    },
  )
}

pub fn native_mappings_and_numeric_constraints_match_value_decoding_test() {
  let mapped =
    codec.string_enum([#("first", 1), #("second", 2)])
    |> codec.map(decode: Count, encode: fn(choice) {
      case choice {
        Count(n) -> n
        _ -> 0
      }
    })
    |> codec.describe("mapped enum")
  list.each(["\"first\"", "\"third\"", "42"], fn(text) {
    let assert Ok(raw) = value.parse(text, value.default_limits())
    codec.decode_json(mapped, text) |> should.equal(codec.decode(mapped, raw))
  })
  let assert Ok(lower) = number.from_int(-2)
  let assert Ok(upper) = number.from_int(2)
  let c =
    codec.pair(codec.integer_between(-2, 2), codec.number_between(lower, upper))
  list.each(
    ["[1.0,0.1]", "[3,0]", "[1,3]", "[0.5,1]", "[true,1]", "[1,false]"],
    fn(text) {
      let assert Ok(raw) = value.parse(text, value.default_limits())
      codec.decode_json(c, text) |> should.equal(codec.decode(c, raw))
    },
  )
}

pub fn native_custom_failures_keep_nested_paths_test() {
  let custom =
    codec.custom(
      encode: fn(_) { Ok(value.Null) },
      decode: fn(_) { Error(codec.decode_failure("custom refusal")) },
      schema: None,
      placeholder: Nil,
    )
  codec.decode_json(codec.list(custom), "[{}]")
  |> should.equal(
    Error(codec.DecodeError([codec.Index(0)], codec.Custom("custom refusal"))),
  )
}
