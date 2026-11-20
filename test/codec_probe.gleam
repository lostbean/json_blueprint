//// A differential probe of the public codec operations. `lines` runs a fixed
//// set of codecs through every operation and returns, for each case, its
//// result or error text and the trace of the caller callbacks it ran, in
//// order. Every line is rendered without `string.inspect`, so one expected
//// output serves both targets.
////
//// `codec_probe_test` compares `lines()` with `codec_probe_expected`, which
//// `codec_probe_runner` writes. Cases are only ever added; the expected line
//// of an existing case changes only in a commit that names the design or ADR
//// change it follows. See `codec_probe_expected` for where each expected
//// line came from.

import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import json/blueprint/codec.{type Codec}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

@external(erlang, "codec_probe_ffi", "log")
@external(javascript, "./codec_probe_ffi.mjs", "log")
fn log(entry: String) -> Nil

@external(erlang, "codec_probe_ffi", "take")
@external(javascript, "./codec_probe_ffi.mjs", "take")
fn take() -> List(String)

/// `Ok` with the result of `run`, or `Error` with the message of the panic it
/// raised.
@external(erlang, "codec_probe_ffi", "stash")
@external(javascript, "./codec_probe_ffi.mjs", "stash")
fn stash(item: a) -> Nil

@external(erlang, "codec_probe_ffi", "unstash")
@external(javascript, "./codec_probe_ffi.mjs", "unstash")
fn unstash() -> a

@external(erlang, "codec_probe_ffi", "panic_message")
@external(javascript, "./codec_probe_ffi.mjs", "panic_message")
fn panic_message(run: fn() -> a) -> Result(a, String)

pub type Shape {
  Circle(Int)
  Square(Int)
  Empty
}

pub type Kind {
  A
  B
  C
}

pub type Order {
  Order(
    id: Int,
    items: List(Int),
    total: Int,
    note: Option(String),
    shape: Shape,
    kind: Kind,
    at: #(Float, number.Number),
  )
}

fn traced_int(label: String) -> Codec(Int) {
  codec.map(
    codec.int(),
    decode: fn(x) {
      log(label <> ".decode " <> int.to_string(x))
      x
    },
    encode: fn(x) {
      log(label <> ".encode " <> int.to_string(x))
      x
    },
  )
}

fn total_of(items: List(Int)) -> Codec(Int) {
  log("total_of " <> ints(items))
  let check = fn(total) {
    case total == int.sum(items) {
      True -> Ok(total)
      False -> Error("total differs")
    }
  }
  codec.try_map(
    codec.int(),
    decode: fn(total) {
      log("total.decode")
      check(total)
    },
    encode: fn(total) {
      log("total.encode")
      check(total)
    },
    placeholder: -1,
  )
}

fn shape_codec() -> Codec(Shape) {
  codec.union({
    use circle <- codec.variant("circle", traced_int("radius"), fn(r) {
      log("construct circle")
      Circle(r)
    })
    use square <- codec.variant("square", codec.integer_between(0, 10), Square)
    use empty <- codec.unit_variant("empty", Empty)
    codec.match(fn(shape) {
      log("match")
      case shape {
        Circle(r) -> circle(r)
        Square(s) -> square(s)
        Empty -> empty
      }
    })
  })
}

fn kind_codec() -> Codec(Kind) {
  codec.string_enum([#("a", A), #("b", B), #("c", C)])
  |> codec.describe("a kind")
}

fn exact(text: String) -> number.Number {
  let assert Ok(found) = number.parse(text, number.default_limits())
  found
}

fn order_codec() -> Codec(Order) {
  log("order_codec")
  use id <- codec.field("id", traced_int("id"), get: fn(o) {
    log("get id")
    o.id
  })
  log("after id " <> int.to_string(id))
  use items <- codec.field("items", codec.list(traced_int("item")), get: fn(o) {
    log("get items")
    o.items
  })
  use total <- codec.field("total", total_of(items), get: fn(o) {
    log("get total")
    o.total
  })
  use note <- codec.optional_field(
    "note",
    codec.map(
      codec.string(),
      decode: fn(x) {
        log("note.decode")
        x
      },
      encode: fn(x) {
        log("note.encode")
        x
      },
    ),
    get: fn(o) {
      log("get note")
      o.note
    },
  )
  use shape <- codec.field("shape", shape_codec(), get: fn(o) {
    log("get shape")
    o.shape
  })
  use kind <- codec.field("kind", kind_codec(), get: fn(o) {
    log("get kind")
    o.kind
  })
  use at <- codec.field(
    "at",
    codec.pair(codec.float(), codec.number_between(exact("-1.5"), exact("1e3"))),
    get: fn(o) {
      log("get at")
      o.at
    },
  )
  log("success")
  codec.success(Order(id:, items:, total:, note:, shape:, kind:, at:))
}

// --- rendering ---------------------------------------------------------------

fn ints(items: List(Int)) -> String {
  "[" <> string.join(list.map(items, int.to_string), ",") <> "]"
}

fn show_shape(shape: Shape) -> String {
  case shape {
    Circle(r) -> "Circle(" <> int.to_string(r) <> ")"
    Square(s) -> "Square(" <> int.to_string(s) <> ")"
    Empty -> "Empty"
  }
}

fn show_kind(kind: Kind) -> String {
  case kind {
    A -> "A"
    B -> "B"
    C -> "C"
  }
}

fn show_order(o: Order) -> String {
  "Order("
  <> string.join(
    [
      int.to_string(o.id),
      ints(o.items),
      int.to_string(o.total),
      case o.note {
        Some(note) -> "Some(" <> note <> ")"
        None -> "None"
      },
      show_shape(o.shape),
      show_kind(o.kind),
      float.to_string({ o.at }.0) <> " " <> number.to_string({ o.at }.1),
    ],
    ", ",
  )
  <> ")"
}

fn encoded(outcome: Result(String, codec.EncodeError)) -> String {
  case outcome {
    Ok(text) -> "ok " <> text
    Error(error) -> "error " <> codec.describe_encode_error(error)
  }
}

fn decoded(
  outcome: Result(a, codec.DecodeError),
  show: fn(a) -> String,
) -> String {
  case outcome {
    Ok(item) -> "ok " <> show(item)
    Error(error) -> "error " <> codec.describe_decode_error(error)
  }
}

fn defined(outcome: Result(a, codec.DefinitionError)) -> String {
  case outcome {
    Ok(_) -> "ok"
    Error(error) -> "error " <> codec.describe_definition_error(error)
  }
}

fn view_kind(view: codec.SchemaView) -> String {
  case view {
    codec.ObjectSchema(properties) ->
      "object "
      <> string.join(
        list.map(properties, fn(property) {
          property.name
          <> case property.required {
            True -> "!"
            False -> "?"
          }
          <> ":"
          <> view_kind(codec.view(property.schema))
        }),
        ",",
      )
    codec.UnionSchema(variants) ->
      "union "
      <> string.join(list.map(variants, fn(variant) { variant.tag }), ",")
    codec.StringEnumSchema(labels) -> "enum " <> string.join(labels, ",")
    codec.ListSchema(_) -> "list"
    codec.PairSchema(_, _) -> "pair"
    codec.IntSchema -> "int"
    codec.StringSchema -> "string"
    _ -> "other"
  }
}

/// One line per case: its name, its result, and the callbacks it ran.
fn case_line(name: String, run: fn() -> String) -> String {
  let _ = take()
  let outcome = case panic_message(run) {
    Ok(text) -> text
    Error(message) -> "panic " <> message
  }
  name <> " => " <> outcome <> " | trace: " <> string.join(take(), "; ")
}

// --- cases -------------------------------------------------------------------

const good_text =
  "{\"id\":1,\"items\":[2,3],\"total\":5,\"note\":\"hi\",\"shape\":{\"tag\":\"circle\",\"value\":4},\"kind\":\"b\",\"at\":[0.5,2]}"

const bad_texts = [
  "{\"id\":1,\"items\":[2,3],\"total\":6,\"shape\":{\"tag\":\"empty\"},\"kind\":\"b\",\"at\":[0.5,2]}",
  "{\"id\":1,\"items\":[2,\"x\"],\"total\":6,\"shape\":{\"tag\":\"empty\"},\"kind\":\"b\",\"at\":[0.5,2]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"square\",\"value\":11},\"kind\":\"b\",\"at\":[0.5,2]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\",\"value\":1},\"kind\":\"b\",\"at\":[0.5,2]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"nope\"},\"kind\":\"b\",\"at\":[0.5,2]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"z\",\"at\":[0.5,2]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[0.5,1e4]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[1e400,1]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[1]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[1,1],\"zz\":1}",
  "{\"id\":1,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[1,1],\"id\":1}",
  "{\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[1,1]}",
  "{\"id\":1.5,\"items\":[],\"total\":0,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[1,1]}",
  "{\"id\":1,\"items\":[],\"total\":0,\"note\":null,\"shape\":{\"tag\":\"empty\"},\"kind\":\"a\",\"at\":[1,1]}",
  "[1]",
  "{\"id\":1,",
]

fn parsed(text: String) -> value.Value {
  let assert Ok(raw) = value.parse(text, value.default_limits())
  raw
}

/// Every case, in a fixed order.
pub fn lines() -> List(String) {
  let built = case_line("construct", fn() { "" })
  let c = order_codec()
  let good = Order(1, [2, 3], 5, Some("hi"), Circle(4), B, #(0.5, exact("2")))
  list.flatten([
    [
      built,
      case_line("encode_json good", fn() { encoded(codec.encode_json(c, good)) }),
      case_line("encode good", fn() {
        encoded(codec.encode(c, good) |> result.map(value.to_string))
      }),
      case_line("to_json good", fn() {
        encoded(codec.to_json(c, good) |> result.map(json.to_string))
      }),
      case_line("decode_json good", fn() {
        decoded(codec.decode_json(c, good_text), show_order)
      }),
      case_line("decode good", fn() {
        decoded(codec.decode(c, parsed(good_text)), show_order)
      }),
      case_line("decoder good", fn() {
        case json.parse(good_text, codec.decoder(c)) {
          Ok(order) -> "ok " <> show_order(order)
          Error(_) -> "error"
        }
      }),
      case_line("schema_json", fn() {
        codec.schema_json(c) |> result.unwrap("unknown")
      }),
      case_line("placeholder", fn() { show_order(codec.placeholder(c)) }),
      case_line("check", fn() { defined(codec.check(c)) }),
      case_line("view", fn() {
        let assert Ok(schema) = codec.schema(c)
        view_kind(codec.view(schema))
      }),
    ],
    list.index_map(bad_texts, fn(text, index) {
      case_line("decode_json bad " <> int.to_string(index), fn() {
        decoded(codec.decode_json(c, text), show_order)
      })
    }),
    list.index_map(bad_texts, fn(text, index) {
      case_line("decode bad " <> int.to_string(index), fn() {
        case value.parse(text, value.default_limits()) {
          Ok(raw) -> decoded(codec.decode(c, raw), show_order)
          Error(_) -> "unparsable"
        }
      })
    }),
    list.index_map(
      [
        Order(1, [2, 3], 6, None, Empty, A, #(0.5, exact("2"))),
        Order(1, [], 0, None, Square(11), A, #(0.5, exact("2"))),
        Order(1, [], 0, None, Empty, A, #(0.5, exact("1e4"))),
      ],
      fn(order, index) {
        case_line("encode bad " <> int.to_string(index), fn() {
          encoded(codec.encode_json(c, order))
        })
      },
    ),
    definition_cases(),
    mapping_cases(c, good),
    leaf_cases(),
    union_cases(),
  ])
}

fn definition_cases() -> List(String) {
  let repeated_field = {
    use a <- codec.field("a", codec.int(), get: fn(x: #(Int, Int)) { x.0 })
    use b <- codec.field("a", codec.int(), get: fn(x: #(Int, Int)) { x.1 })
    codec.success(#(a, b))
  }
  let repeated_label = codec.string_enum([#("x", 1), #("y", 2), #("x", 3)])
  let repeated_value = codec.string_enum([#("x", 1), #("y", 1)])
  let not_record = {
    use a <- codec.field("a", codec.int(), get: fn(x: Int) { x })
    codec.int() |> codec.map(decode: fn(b) { a + b }, encode: fn(x) { x })
  }
  let later_mistakes = {
    use a <- codec.field("a", codec.int(), get: fn(x: #(Int, Int, Int)) { x.0 })
    use b <- codec.field(
      "b",
      codec.string_enum([#("p", 1), #("p", 2)]),
      get: fn(x: #(Int, Int, Int)) { x.1 },
    )
    use c <- codec.field(
      "a",
      codec.integer_between(5, 1),
      get: fn(x: #(Int, Int, Int)) { x.2 },
    )
    codec.success(#(a, b, c))
  }
  let repeated_tag =
    codec.union({
      use x <- codec.variant("x", codec.int(), Circle)
      use y <- codec.variant("x", codec.int(), Square)
      use z <- codec.unit_variant("z", Empty)
      codec.match(fn(s) {
        case s {
          Circle(r) -> x(r)
          Square(r) -> y(r)
          Empty -> z
        }
      })
    })
  [
    case_line("check repeated field", fn() {
      defined(codec.check(repeated_field))
    }),
    case_line("encode repeated field", fn() {
      encoded(codec.encode_json(repeated_field, #(1, 2)))
    }),
    case_line("decode repeated field", fn() {
      decoded(codec.decode_json(repeated_field, "{\"a\":1}"), fn(_) { "" })
    }),
    case_line("check repeated label", fn() {
      defined(codec.check(repeated_label))
    }),
    case_line("decode repeated label", fn() {
      decoded(codec.decode_json(repeated_label, "\"y\""), int.to_string)
    }),
    case_line("check repeated value", fn() {
      defined(codec.check(repeated_value))
    }),
    case_line("check not a record", fn() { defined(codec.check(not_record)) }),
    case_line("encode not a record", fn() {
      encoded(codec.encode_json(not_record, 1))
    }),
    case_line("check later mistakes", fn() {
      defined(codec.check(later_mistakes))
    }),
    case_line("placeholder later mistakes", fn() {
      let #(a, b, c) = codec.placeholder(later_mistakes)
      ints([a, b, c])
    }),
    case_line("check repeated tag", fn() { defined(codec.check(repeated_tag)) }),
    case_line("encode repeated tag", fn() {
      encoded(codec.encode_json(repeated_tag, Empty))
    }),
    case_line("check reversed bounds", fn() {
      defined(codec.check(codec.integer_between(3, 1)))
    }),
    case_line("check empty union", fn() {
      defined(codec.check(codec.union(codec.match(fn(_: Int) { panic }))))
    }),
    case_line("check empty enum", fn() {
      defined(codec.check(
        codec.string_enum([]) |> codec.map(fn(x: Int) { x }, fn(x) { x }),
      ))
    }),
  ]
}

fn mapping_cases(c: Codec(Order), good: Order) -> List(String) {
  let custom =
    codec.custom(
      encode: fn(x: Int) {
        log("custom.encode")
        Ok(value.String(int.to_string(x)))
      },
      decode: fn(raw) {
        log("custom.decode")
        case raw {
          value.String(text) ->
            int.parse(text) |> result.replace_error(codec.decode_failure("nan"))
          _ -> Error(codec.decode_failure(""))
        }
      },
      schema: option.from_result(codec.schema(codec.string())),
      placeholder: 0,
    )
  let wrapper = {
    use x <- codec.field(
      "x",
      custom,
      get: fn(w: #(Int, value.Value, Option(Option(Int)))) { w.0 },
    )
    use v <- codec.field(
      "v",
      codec.value(),
      get: fn(w: #(Int, value.Value, Option(Option(Int)))) { w.1 },
    )
    use n <- codec.optional_field(
      "n",
      codec.nullable(codec.int()),
      get: fn(w: #(Int, value.Value, Option(Option(Int)))) { w.2 },
    )
    codec.success(#(x, v, n))
  }
  let show_wrapper = fn(w: #(Int, value.Value, Option(Option(Int)))) {
    int.to_string(w.0)
    <> " "
    <> value.to_string(w.1)
    <> " "
    <> case w.2 {
      None -> "None"
      Some(None) -> "Some(None)"
      Some(Some(n)) -> "Some(Some(" <> int.to_string(n) <> "))"
    }
  }
  let assert Ok(schema) = codec.schema(c)
  let order_contract = contract.from_schema(schema)
  [
    case_line("map labels", fn() {
      codec.map_enum_labels(schema, fn(label) { "L" <> label })
      |> result.map(fn(mapped) { value.to_string(codec.schema_value(mapped)) })
      |> defined_text
    }),
    case_line("map labels repeated", fn() {
      codec.map_enum_labels(schema, fn(_) { "same" })
      |> result.map(fn(mapped) { value.to_string(codec.schema_value(mapped)) })
      |> defined_text
    }),
    case_line("map descriptions", fn() {
      codec.map_descriptions(schema, string.uppercase)
      |> codec.schema_value
      |> value.to_string
    }),
    case_line("contract decode", fn() {
      let assert Ok(validated) =
        contract.validate(order_contract, parsed(good_text))
      decoded(contract.decode(c, validated), show_order)
    }),
    case_line("contract value codec", fn() {
      decoded(
        codec.decode_json(
          codec.list(contract.value_codec(order_contract)),
          "[" <> good_text <> ",{}]",
        ),
        fn(items) { int.to_string(list.length(items)) },
      )
    }),
    case_line("custom encode", fn() {
      encoded(
        codec.encode_json(wrapper, #(7, value.Array([value.Null]), Some(None))),
      )
    }),
    case_line("custom decode", fn() {
      decoded(
        codec.decode_json(wrapper, "{\"x\":\"7\",\"v\":[null,{}],\"n\":null}"),
        show_wrapper,
      )
    }),
    case_line("custom decode bad", fn() {
      decoded(codec.decode_json(wrapper, "{\"x\":\"q\",\"v\":1}"), show_wrapper)
    }),
    case_line("custom decode empty message", fn() {
      decoded(codec.decode_json(wrapper, "{\"x\":3,\"v\":1}"), show_wrapper)
    }),
    case_line("custom schema", fn() {
      codec.schema_json(wrapper) |> result.unwrap("unknown")
    }),
    case_line("unknown schema", fn() {
      codec.list(codec.custom(
        encode: fn(_: Int) { Ok(value.Null) },
        decode: fn(_) { Ok(1) },
        schema: None,
        placeholder: 0,
      ))
      |> codec.schema_json
      |> result.unwrap("unknown")
    }),
    case_line("described encode", fn() {
      encoded(codec.encode_json(codec.describe(c, "an order"), good))
    }),
  ]
}

fn defined_text(outcome: Result(String, codec.DefinitionError)) -> String {
  case outcome {
    Ok(text) -> "ok " <> text
    Error(error) -> "error " <> codec.describe_definition_error(error)
  }
}

fn leaf_cases() -> List(String) {
  [
    case_line("nullable null inside", fn() {
      encoded(codec.encode_json(codec.nullable(codec.value()), Some(value.Null)))
    }),
    // The reason differs by target (24 digits, or the JavaScript safe range).
    case_line("int too long", fn() {
      case codec.encode_json(codec.int(), too_long()) {
        Ok(_) -> "ok"
        Error(_) -> "refused"
      }
    }),
    case_line("float out of range", fn() {
      decoded(codec.decode_json(codec.float(), "1e400"), float.to_string)
    }),
    case_line("int digits", fn() {
      decoded(
        codec.decode_json(codec.int(), "1234567890123456789012345"),
        int.to_string,
      )
    }),
    case_line("int spelling", fn() {
      decoded(codec.decode_json(codec.int(), "1.2e1"), int.to_string)
    }),
    case_line("enum unknown value", fn() {
      encoded(codec.encode_json(codec.string_enum([#("a", 1)]), 2))
    }),
    case_line("decoder failure placeholder", fn() {
      case json.parse("null", codec.decoder(order_codec())) {
        Ok(_) -> "ok"
        Error(_) -> "error"
      }
    }),
  ]
}

fn too_long() -> Int {
  let assert Ok(found) = int.parse("1234567890123456789012345")
  found
}

/// A union whose `match` returns what an enclosing union passed on.
fn inner_union(
  outer_payload: fn(Int) -> codec.Tagged(Shape),
  outer_unit: codec.Tagged(Shape),
) -> #(Codec(Shape), Codec(Shape)) {
  let payload =
    codec.union({
      use _square <- codec.variant("inner", codec.int(), Square)
      codec.match(fn(_) { outer_payload(7) })
    })
  let unit =
    codec.union({
      use _square <- codec.variant("inner", codec.int(), Square)
      codec.match(fn(_) { outer_unit })
    })
  #(payload, unit)
}

/// Cases whose expected lines follow ADR 0018, which changes them from 2.1.1.
fn union_cases() -> List(String) {
  let _outer =
    codec.union({
      use circle <- codec.variant("outer", traced_int("outer"), Circle)
      use empty <- codec.unit_variant("outer-empty", Empty)
      stash(inner_union(circle, empty))
      codec.match(fn(shape) {
        case shape {
          Circle(r) -> circle(r)
          _ -> empty
        }
      })
    })
  let #(foreign_payload, foreign_unit): #(Codec(Shape), Codec(Shape)) =
    unstash()
  let two_taggers =
    codec.union({
      use circle <- codec.variant("circle", traced_int("first"), Circle)
      use square <- codec.variant("square", traced_int("second"), Square)
      codec.match(fn(_) {
        let _ = circle(1)
        log("match after first")
        square(2)
      })
    })
  [
    case_line("adr-0018 foreign tagging function", fn() {
      encoded(codec.encode_json(foreign_payload, Empty))
    }),
    case_line("adr-0018 foreign tagged value", fn() {
      encoded(codec.encode_json(foreign_unit, Empty))
    }),
    case_line("adr-0018 match calls two tagging functions", fn() {
      encoded(codec.encode_json(two_taggers, Empty))
    }),
  ]
}
