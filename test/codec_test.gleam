import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit/should
import json/blueprint/codec.{type Codec, DecodeError, EncodeError, Field, Index}
import json/blueprint/number
import json/blueprint/value

pub type Priority {
  Low
  Normal
  Urgent
}

pub type Note {
  Note(title: String, count: Int, note: Option(String))
}

pub type Shape {
  Circle(Int)
  Label(String)
  Empty
}

@external(erlang, "codec_test_ffi", "panic_message")
@external(javascript, "./codec_test_ffi.mjs", "panic_message")
fn panic_message(run: fn() -> a) -> Result(String, Nil)

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

fn num(token: String) -> number.Number {
  let assert Ok(parsed) = number.parse(token, number.default_limits())
  parsed
}

fn fail(
  path: List(codec.PathSegment),
  reason: codec.Reason,
) -> Result(a, codec.DecodeError) {
  Error(DecodeError(path, reason))
}

fn note_codec() -> Codec(Note) {
  use title <- codec.field("title", codec.string(), fn(n: Note) { n.title })
  use count <- codec.field("count", codec.int(), fn(n: Note) { n.count })
  use note <- codec.optional_field("note", codec.string(), fn(n: Note) {
    n.note
  })
  codec.success(Note(title:, count:, note:))
}

fn shape_codec() -> Codec(Shape) {
  codec.union({
    use circle <- codec.variant("circle", codec.int(), Circle)
    use label <- codec.variant("label", codec.string(), Label)
    use empty <- codec.unit_variant("empty", Empty)
    codec.match(fn(shape) {
      case shape {
        Circle(radius) -> circle(radius)
        Label(text) -> label(text)
        Empty -> empty
      }
    })
  })
}

// --- primitives ----------------------------------------------------------------

pub fn string_codec_test() {
  let c = codec.string()
  codec.encode(c, "hello") |> should.equal(Ok(value.String("hello")))
  codec.decode(c, value.String("hello")) |> should.equal(Ok("hello"))
  codec.decode(c, value.Bool(True))
  |> should.equal(fail([], codec.ExpectedString))
  codec.schema(c) |> should.equal(Ok(codec.StringSchema))
}

pub fn int_codec_test() {
  let c = codec.int()
  codec.encode(c, 42) |> should.equal(Ok(value.Number(int_num(42))))
  codec.decode(c, value.Number(int_num(42))) |> should.equal(Ok(42))
  codec.decode(c, value.Number(num("1.2e1"))) |> should.equal(Ok(12))
  codec.decode(c, value.Number(num("1.5")))
  |> should.equal(fail([], codec.ExpectedInt))
  codec.decode(c, value.Number(num("1e24")))
  |> should.equal(fail([], codec.ExpectedInt))
  codec.decode(c, value.String("42"))
  |> should.equal(fail([], codec.ExpectedInt))
  codec.schema(c) |> should.equal(Ok(codec.IntSchema))
}

pub fn float_codec_rounds_to_the_nearest_float_test() {
  let c = codec.float()
  codec.decode(c, value.Number(num("0.1"))) |> should.equal(Ok(0.1))
  codec.decode(c, value.Number(num("2"))) |> should.equal(Ok(2.0))
  codec.decode(c, value.Number(num("0.1000000000000000000001")))
  |> should.equal(Ok(0.1))
  codec.decode(c, value.Number(num("1e400")))
  |> should.equal(fail([], codec.FloatOutOfRange))
  codec.decode(c, value.String("1"))
  |> should.equal(fail([], codec.ExpectedNumber))
  codec.encode_json(c, 0.1) |> should.equal(Ok("0.1"))
  codec.encode_json(c, 2.5) |> should.equal(Ok("2.5"))
  codec.decode_json(c, "0.30000000000000004")
  |> should.equal(Ok(0.30000000000000004))
  codec.schema(c) |> should.equal(Ok(codec.NumberSchema))
}

pub fn number_codec_test() {
  let c = codec.number()
  codec.encode(c, int_num(99)) |> should.equal(Ok(value.Number(int_num(99))))
  codec.decode(c, value.Number(num("1.10"))) |> should.equal(Ok(num("1.1")))
  codec.decode(c, value.Null) |> should.equal(fail([], codec.ExpectedNumber))
  codec.schema(c) |> should.equal(Ok(codec.NumberSchema))
}

pub fn bool_codec_test() {
  let c = codec.bool()
  codec.encode(c, True) |> should.equal(Ok(value.Bool(True)))
  codec.decode(c, value.Bool(False)) |> should.equal(Ok(False))
  codec.decode(c, value.String("true"))
  |> should.equal(fail([], codec.ExpectedBool))
  codec.schema(c) |> should.equal(Ok(codec.BoolSchema))
}

// --- collections ---------------------------------------------------------------

pub fn pair_codec_test() {
  let c = codec.pair(codec.string(), codec.int())
  let wire = value.Array([value.String("item"), value.Number(int_num(10))])
  codec.encode(c, #("item", 10)) |> should.equal(Ok(wire))
  codec.decode(c, wire) |> should.equal(Ok(#("item", 10)))
  codec.decode(c, value.Array([value.String("item")]))
  |> should.equal(fail([], codec.WrongLength(2, 1)))
  codec.decode(c, value.String("x"))
  |> should.equal(fail([], codec.ExpectedArray))
  codec.decode(c, value.Array([value.Bool(False), value.Number(int_num(10))]))
  |> should.equal(fail([Index(0)], codec.ExpectedString))
  codec.schema(c)
  |> should.equal(Ok(codec.PairSchema(codec.StringSchema, codec.IntSchema)))
}

pub fn list_codec_test() {
  let c = codec.list(codec.string())
  let wire = value.Array([value.String("a"), value.String("b")])
  codec.encode(c, ["a", "b"]) |> should.equal(Ok(wire))
  codec.decode(c, wire) |> should.equal(Ok(["a", "b"]))
  codec.decode(c, value.Array([value.String("a"), value.Bool(True)]))
  |> should.equal(fail([Index(1)], codec.ExpectedString))
  codec.decode(c, value.Null) |> should.equal(fail([], codec.ExpectedArray))
  codec.schema(c) |> should.equal(Ok(codec.ListSchema(codec.StringSchema)))
}

pub fn nullable_is_an_option_test() {
  let c = codec.nullable(codec.string())
  codec.encode(c, None) |> should.equal(Ok(value.Null))
  codec.encode(c, Some("text")) |> should.equal(Ok(value.String("text")))
  codec.decode(c, value.Null) |> should.equal(Ok(None))
  codec.decode(c, value.String("text")) |> should.equal(Ok(Some("text")))
  codec.decode(c, value.Bool(True))
  |> should.equal(fail([], codec.ExpectedString))
  codec.schema(c) |> should.equal(Ok(codec.NullableSchema(codec.StringSchema)))
}

pub fn nullable_refuses_an_inner_null_test() {
  let c = codec.nullable(codec.nullable(codec.string()))
  codec.encode(c, Some(None))
  |> should.equal(Error(EncodeError([], codec.NullInsideNullable)))
}

// --- records -------------------------------------------------------------------

pub fn record_builder_encodes_in_declaration_order_test() {
  codec.encode(note_codec(), Note("Book", 5, Some("First edition")))
  |> should.equal(
    Ok(
      value.Object([
        #("title", value.String("Book")),
        #("count", value.Number(int_num(5))),
        #("note", value.String("First edition")),
      ]),
    ),
  )
  codec.encode(note_codec(), Note("Book", 5, None))
  |> should.equal(
    Ok(
      value.Object([
        #("title", value.String("Book")),
        #("count", value.Number(int_num(5))),
      ]),
    ),
  )
}

pub fn record_builder_decodes_in_any_member_order_test() {
  codec.decode_json(
    note_codec(),
    "{\"count\":5,\"note\":\"x\",\"title\":\"Book\"}",
  )
  |> should.equal(Ok(Note("Book", 5, Some("x"))))
  codec.decode_json(note_codec(), "{\"title\":\"Book\",\"count\":5}")
  |> should.equal(Ok(Note("Book", 5, None)))
}

pub fn record_builder_is_closed_test() {
  codec.decode_json(note_codec(), "{\"title\":\"Book\"}")
  |> should.equal(fail([Field("count")], codec.MissingField))
  codec.decode_json(
    note_codec(),
    "{\"title\":\"Book\",\"count\":5,\"extra\":null}",
  )
  |> should.equal(fail([Field("extra")], codec.UnknownField))
  codec.decode(
    note_codec(),
    value.Object([
      #("title", value.String("Book")),
      #("count", value.Number(int_num(5))),
      #("title", value.String("Again")),
    ]),
  )
  |> should.equal(fail([Field("title")], codec.DuplicateField))
  codec.decode_json(note_codec(), "[]")
  |> should.equal(fail([], codec.ExpectedObject))
  codec.decode_json(note_codec(), "{\"title\":\"Book\",\"count\":\"5\"}")
  |> should.equal(fail([Field("count")], codec.ExpectedInt))
}

pub fn optional_field_rejects_null_unless_nullable_test() {
  codec.decode_json(note_codec(), "{\"title\":\"a\",\"count\":1,\"note\":null}")
  |> should.equal(fail([Field("note")], codec.ExpectedString))
}

pub type Patch {
  Patch(name: Option(Option(String)))
}

pub fn optional_nullable_field_keeps_three_states_test() {
  let patch = {
    use name <- codec.optional_field(
      "name",
      codec.nullable(codec.string()),
      fn(p: Patch) { p.name },
    )
    codec.success(Patch(name:))
  }
  codec.decode_json(patch, "{}") |> should.equal(Ok(Patch(None)))
  codec.decode_json(patch, "{\"name\":null}")
  |> should.equal(Ok(Patch(Some(None))))
  codec.decode_json(patch, "{\"name\":\"x\"}")
  |> should.equal(Ok(Patch(Some(Some("x")))))
  codec.encode_json(patch, Patch(None)) |> should.equal(Ok("{}"))
  codec.encode_json(patch, Patch(Some(None)))
  |> should.equal(Ok("{\"name\":null}"))
  codec.encode_json(patch, Patch(Some(Some("x"))))
  |> should.equal(Ok("{\"name\":\"x\"}"))
  let assert Ok(codec.ObjectSchema([property])) = codec.schema(patch)
  property
  |> should.equal(codec.PropertySchema(
    "name",
    False,
    codec.NullableSchema(codec.StringSchema),
  ))
}

pub fn record_schema_lists_required_and_optional_fields_test() {
  codec.schema(note_codec())
  |> should.equal(
    Ok(
      codec.ObjectSchema([
        codec.PropertySchema("title", True, codec.StringSchema),
        codec.PropertySchema("count", True, codec.IntSchema),
        codec.PropertySchema("note", False, codec.StringSchema),
      ]),
    ),
  )
}

pub fn success_alone_is_the_empty_object_test() {
  let empty = codec.success(Nil)
  codec.encode_json(empty, Nil) |> should.equal(Ok("{}"))
  codec.decode_json(empty, "{}") |> should.equal(Ok(Nil))
  codec.decode_json(empty, "{\"a\":1}")
  |> should.equal(fail([Field("a")], codec.UnknownField))
  codec.schema(empty) |> should.equal(Ok(codec.ObjectSchema([])))
}

pub type Order {
  Order(id: Int, lines: List(Line))
}

pub type Line {
  Line(sku: String, quantity: Int)
}

fn order_codec() -> Codec(Order) {
  let line = {
    use sku <- codec.field("sku", codec.string(), fn(l: Line) { l.sku })
    use quantity <- codec.field(
      "quantity",
      codec.integer_between(1, 99),
      fn(l: Line) { l.quantity },
    )
    codec.success(Line(sku:, quantity:))
  }
  use id <- codec.field("id", codec.int(), fn(o: Order) { o.id })
  use lines <- codec.field("lines", codec.list(line), fn(o: Order) { o.lines })
  codec.success(Order(id:, lines:))
}

pub fn nested_errors_carry_the_full_path_test() {
  let text =
    "{\"id\":1,\"lines\":[{\"sku\":\"a\",\"quantity\":1},{\"sku\":\"b\",\"quantity\":100}]}"
  let assert Error(error) = codec.decode_json(order_codec(), text)
  error
  |> should.equal(DecodeError(
    [Field("lines"), Index(1), Field("quantity")],
    codec.IntegerOutsideRange(1, 99),
  ))
  codec.describe_decode_error(error)
  |> should.equal(
    "$[\"lines\"][1][\"quantity\"]: integer outside range 1 to 99",
  )
  codec.encode(order_codec(), Order(1, [Line("a", 0)]))
  |> should.equal(
    Error(EncodeError(
      [Field("lines"), Index(0), Field("quantity")],
      codec.IntegerOutsideRange(1, 99),
    )),
  )
}

// --- enums ---------------------------------------------------------------------

pub fn string_enum_test() {
  let priority =
    codec.string_enum([#("low", Low), #("normal", Normal), #("urgent", Urgent)])
  codec.encode(priority, Normal) |> should.equal(Ok(value.String("normal")))
  codec.decode(priority, value.String("urgent")) |> should.equal(Ok(Urgent))
  codec.decode(priority, value.String("critical"))
  |> should.equal(fail([], codec.UnknownEnumLabel))
  codec.decode(priority, value.Number(int_num(10)))
  |> should.equal(fail([], codec.ExpectedString))
  codec.schema(priority)
  |> should.equal(Ok(codec.StringEnumSchema(["low", "normal", "urgent"])))
  let partial = codec.string_enum([#("low", Low)])
  codec.encode(partial, Urgent)
  |> should.equal(Error(EncodeError([], codec.UnknownEnumValue)))
}

// --- unions --------------------------------------------------------------------

pub fn union_encodes_every_variant_test() {
  codec.encode_json(shape_codec(), Circle(2))
  |> should.equal(Ok("{\"tag\":\"circle\",\"value\":2}"))
  codec.encode_json(shape_codec(), Label("hi"))
  |> should.equal(Ok("{\"tag\":\"label\",\"value\":\"hi\"}"))
  codec.encode_json(shape_codec(), Empty)
  |> should.equal(Ok("{\"tag\":\"empty\"}"))
}

pub fn union_decodes_every_variant_test() {
  codec.decode_json(shape_codec(), "{\"value\":2,\"tag\":\"circle\"}")
  |> should.equal(Ok(Circle(2)))
  codec.decode_json(shape_codec(), "{\"tag\":\"label\",\"value\":\"hi\"}")
  |> should.equal(Ok(Label("hi")))
  codec.decode_json(shape_codec(), "{\"tag\":\"empty\"}")
  |> should.equal(Ok(Empty))
}

pub fn union_decode_errors_test() {
  let decode = fn(text) { codec.decode_json(shape_codec(), text) }
  decode("{\"tag\":\"square\",\"value\":1}")
  |> should.equal(fail([Field("tag")], codec.UnknownTag))
  decode("{\"value\":1}")
  |> should.equal(fail([Field("tag")], codec.MissingField))
  decode("{\"tag\":7,\"value\":1}")
  |> should.equal(fail([Field("tag")], codec.ExpectedString))
  decode("{\"tag\":\"circle\"}")
  |> should.equal(fail([Field("value")], codec.MissingField))
  decode("{\"tag\":\"circle\",\"value\":\"x\"}")
  |> should.equal(fail([Field("value")], codec.ExpectedInt))
  decode("{\"tag\":\"empty\",\"value\":null}")
  |> should.equal(fail([Field("value")], codec.UnknownField))
  decode("{\"tag\":\"circle\",\"value\":1,\"extra\":1}")
  |> should.equal(fail([Field("extra")], codec.UnknownField))
  decode("[]") |> should.equal(fail([], codec.ExpectedObject))
}

pub fn union_schema_lists_variants_in_order_test() {
  codec.schema(shape_codec())
  |> should.equal(
    Ok(
      codec.UnionSchema([
        codec.VariantSchema("circle", Some(codec.IntSchema)),
        codec.VariantSchema("label", Some(codec.StringSchema)),
        codec.VariantSchema("empty", None),
      ]),
    ),
  )
}

pub fn union_payload_encode_errors_are_under_value_test() {
  let bounded =
    codec.union({
      use small <- codec.variant("small", codec.integer_between(0, 9), fn(n) {
        n
      })
      codec.match(fn(n) { small(n) })
    })
  codec.encode(bounded, 10)
  |> should.equal(
    Error(EncodeError([Field("value")], codec.IntegerOutsideRange(0, 9))),
  )
}

// --- refinements ---------------------------------------------------------------

pub fn integer_between_test() {
  let c = codec.integer_between(1, 10)
  codec.encode(c, 5) |> should.equal(Ok(value.Number(int_num(5))))
  codec.decode(c, value.Number(int_num(1))) |> should.equal(Ok(1))
  codec.decode(c, value.Number(int_num(10))) |> should.equal(Ok(10))
  codec.encode(c, 0)
  |> should.equal(Error(EncodeError([], codec.IntegerOutsideRange(1, 10))))
  codec.decode(c, value.Number(int_num(11)))
  |> should.equal(fail([], codec.IntegerOutsideRange(1, 10)))
  codec.decode(c, value.Number(num("1e400")))
  |> should.equal(fail([], codec.IntegerOutsideRange(1, 10)))
  codec.decode(c, value.Number(num("2.5")))
  |> should.equal(fail([], codec.ExpectedInt))
  codec.schema(c) |> should.equal(Ok(codec.IntegerRangeSchema(1, 10)))
}

pub fn number_between_test() {
  let c = codec.number_between(int_num(-5), int_num(5))
  codec.decode(c, value.Number(num("4.99"))) |> should.equal(Ok(num("4.99")))
  codec.decode(c, value.Number(int_num(6)))
  |> should.equal(fail([], codec.NumberOutsideRange(int_num(-5), int_num(5))))
  codec.encode(c, int_num(-6))
  |> should.equal(
    Error(EncodeError([], codec.NumberOutsideRange(int_num(-5), int_num(5)))),
  )
  codec.schema(c)
  |> should.equal(Ok(codec.NumberRangeSchema(int_num(-5), int_num(5))))
}

// --- mapping -------------------------------------------------------------------

pub type Email {
  Email(address: String)
}

pub fn map_converts_both_directions_test() {
  let email =
    codec.map(codec.string(), decode: Email, encode: fn(e: Email) { e.address })
  codec.decode_json(email, "\"a@b\"") |> should.equal(Ok(Email("a@b")))
  codec.encode_json(email, Email("a@b")) |> should.equal(Ok("\"a@b\""))
  codec.schema(email) |> should.equal(Ok(codec.StringSchema))
}

pub fn try_map_reports_a_custom_reason_at_the_path_test() {
  let even =
    codec.try_map(
      codec.int(),
      decode: fn(n) {
        case n % 2 {
          0 -> Ok(n)
          _ -> Error("odd")
        }
      },
      encode: fn(n) {
        case n % 2 {
          0 -> Ok(n)
          _ -> Error("odd")
        }
      },
      placeholder: 0,
    )
  let pairs = codec.list(even)
  codec.decode_json(pairs, "[2,3]")
  |> should.equal(fail([Index(1)], codec.Custom("odd")))
  codec.encode(pairs, [3])
  |> should.equal(Error(EncodeError([Index(0)], codec.Custom("odd"))))
  let assert Error(error) = codec.decode_json(pairs, "[3]")
  codec.describe_decode_error(error)
  |> should.equal("$[0]: custom validation failed")
}

pub fn custom_codec_test() {
  let passthrough =
    codec.custom(encode: Ok, decode: Ok, schema: None, placeholder: value.Null)
  codec.decode_json(passthrough, "[1]") |> should.be_ok
  codec.schema(passthrough) |> should.equal(Error(codec.UnknownSchema))
  codec.schema(codec.list(passthrough))
  |> should.equal(Error(codec.UnknownSchema))
  codec.schema_json(passthrough) |> should.equal(Error(codec.UnknownSchema))

  let positive =
    codec.custom(
      encode: fn(n) { codec.encode(codec.int(), n) },
      decode: fn(raw) {
        case codec.decode(codec.int(), raw) {
          Ok(n) if n > 0 -> Ok(n)
          Ok(_) -> Error(codec.decode_failure("not positive"))
          Error(error) -> Error(error)
        }
      },
      schema: Some(codec.IntSchema),
      placeholder: 1,
    )
  codec.decode_json(positive, "0")
  |> should.equal(fail([], codec.Custom("not positive")))
  codec.decode_json(positive, "2") |> should.equal(Ok(2))
  codec.encode_failure("x") |> should.equal(EncodeError([], codec.Custom("x")))
}

pub fn describe_adds_a_description_test() {
  let c = codec.string() |> codec.describe("first") |> codec.describe("second")
  codec.schema(c)
  |> should.equal(Ok(codec.DescribedSchema("second", codec.StringSchema)))
  codec.decode_json(c, "\"x\"") |> should.equal(Ok("x"))
}

// --- definitions ---------------------------------------------------------------

pub fn check_reports_definition_mistakes_test() {
  let assert Error(codec.EmptyEnum) = codec.check(codec.string_enum([]))
  codec.check(codec.string_enum([#("same", Low), #("same", Normal)]))
  |> should.equal(Error(codec.DuplicateEnumLabel("same")))
  codec.check(codec.string_enum([#("low", Low), #("other", Low)]))
  |> should.equal(Error(codec.DuplicateEnumValue("other")))
  codec.check(codec.integer_between(10, 5))
  |> should.equal(Error(codec.ReversedIntegerBounds(10, 5)))
  codec.check(codec.number_between(int_num(1), int_num(0)))
  |> should.equal(Error(codec.ReversedNumberBounds(int_num(1), int_num(0))))
  let repeated = {
    use a <- codec.field("a", codec.int(), fn(p: #(Int, Int)) { p.0 })
    use b <- codec.field("a", codec.int(), fn(p: #(Int, Int)) { p.1 })
    codec.success(#(a, b))
  }
  codec.check(repeated) |> should.equal(Error(codec.DuplicateFieldName("a")))
  let not_record = {
    use a <- codec.field("a", codec.string(), fn(s: String) { s })
    codec.string() |> codec.map(fn(_) { a }, fn(s) { s })
  }
  codec.check(not_record) |> should.equal(Error(codec.NotARecord("a")))
  let repeated_tag =
    codec.union({
      use a <- codec.variant("x", codec.int(), Circle)
      use b <- codec.variant("x", codec.string(), Label)
      codec.match(fn(shape) {
        case shape {
          Circle(n) -> a(n)
          _ -> b("")
        }
      })
    })
  codec.check(repeated_tag) |> should.equal(Error(codec.DuplicateTag("x")))
  let no_variants: Codec(Shape) = codec.union(codec.match(fn(_) { panic }))
  codec.check(no_variants) |> should.equal(Error(codec.EmptyUnion))
  codec.check(codec.custom(
    encode: Ok,
    decode: Ok,
    schema: Some(
      codec.ObjectSchema([
        codec.PropertySchema("a", True, codec.IntSchema),
        codec.PropertySchema("a", False, codec.IntSchema),
      ]),
    ),
    placeholder: value.Null,
  ))
  |> should.equal(Error(codec.DuplicateFieldName("a")))
}

pub fn check_finds_mistakes_inside_composites_test() {
  let bad = codec.string_enum([#("a", 1), #("a", 2)])
  codec.check(codec.list(bad))
  |> should.equal(Error(codec.DuplicateEnumLabel("a")))
  codec.check(codec.pair(codec.string(), codec.nullable(bad)))
  |> should.equal(Error(codec.DuplicateEnumLabel("a")))
  let record = {
    use x <- codec.field("x", bad, fn(r: Int) { r })
    codec.success(x)
  }
  codec.check(record) |> should.equal(Error(codec.DuplicateEnumLabel("a")))
  // An unknown schema elsewhere does not hide a mistake.
  let unknown =
    codec.custom(encode: Ok, decode: Ok, schema: None, placeholder: value.Null)
  codec.check(codec.pair(unknown, bad))
  |> should.equal(Error(codec.DuplicateEnumLabel("a")))
  codec.check(codec.string()) |> should.be_ok
}

pub fn a_mistaken_definition_panics_with_the_key_at_first_use_test() {
  let labels = codec.string_enum([#("draft", 1), #("draft", 2)])
  panic_message(fn() { codec.decode_json(labels, "\"draft\"") })
  |> should.equal(Ok(
    "json_blueprint: invalid codec definition: enum label \"draft\" appears twice",
  ))
  let repeated = {
    use a <- codec.field("id", codec.int(), fn(p: #(Int, Int)) { p.0 })
    use b <- codec.field("id", codec.int(), fn(p: #(Int, Int)) { p.1 })
    codec.success(#(a, b))
  }
  panic_message(fn() { codec.encode(repeated, #(1, 2)) })
  |> should.equal(Ok(
    "json_blueprint: invalid codec definition: field \"id\" appears twice",
  ))
  panic_message(fn() { codec.schema(codec.integer_between(3, 1)) })
  |> should.equal(Ok(
    "json_blueprint: invalid codec definition: integer bounds 3 to 1 are reversed",
  ))
  panic_message(fn() { codec.schema(codec.string()) })
  |> should.equal(Error(Nil))
}

// --- bridges -------------------------------------------------------------------

pub fn to_json_matches_encode_json_test() {
  let note = Note("Book", 5, Some("x"))
  let assert Ok(converted) = codec.to_json(note_codec(), note)
  Ok(json.to_string(converted))
  |> should.equal(codec.encode_json(note_codec(), note))
}

pub fn to_json_reports_unrepresentable_numbers_with_a_path_test() {
  let numbers = codec.list(codec.number())
  codec.to_json(numbers, [int_num(1), num("1e400")])
  |> should.equal(
    Error(EncodeError([Index(1)], codec.UnrepresentableNumber(num("1e400")))),
  )
}

pub fn decoder_bridges_to_gleam_json_test() {
  json.parse("{\"title\":\"Book\",\"count\":5}", codec.decoder(note_codec()))
  |> should.equal(Ok(Note("Book", 5, None)))
  let assert Error(json.UnableToDecode([error])) =
    json.parse(
      "{\"title\":\"Book\",\"count\":\"x\"}",
      codec.decoder(note_codec()),
    )
  error.expected |> should.equal("$[\"count\"]: expected an integer")
  json.parse("[{\"tag\":\"empty\"}]", decode.list(codec.decoder(shape_codec())))
  |> should.equal(Ok([Empty]))
}

// --- text and errors -----------------------------------------------------------

pub fn decode_json_reports_invalid_json_without_a_path_test() {
  let assert Error(error) = codec.decode_json(note_codec(), "{\"title\": ")
  let assert DecodeError([], codec.InvalidJson(_)) = error
  codec.is_limit_exceeded(error) |> should.be_false
  codec.describe_decode_error(error)
  |> should.equal("invalid JSON at line 1, column 11: unexpected end of input")
}

pub fn describe_errors_omit_input_values_test() {
  let assert Error(error) =
    codec.decode_json(
      note_codec(),
      "{\"title\":\"a\",\"count\":1,\"password\":\"x\"}",
    )
  codec.describe_decode_error(error) |> should.equal("$: unknown field")
  { string.contains(codec.describe_decode_error(error), "password") }
  |> should.be_false
  let assert Error(error) =
    codec.decode_json(codec.string_enum([#("a", 1)]), "\"secret-label\"")
  codec.describe_decode_error(error) |> should.equal("$: unknown enum label")
  codec.describe_encode_error(EncodeError(
    [Field("role")],
    codec.UnknownEnumValue,
  ))
  |> should.equal("$[\"role\"]: value is not in the enum")
  codec.describe_definition_error(codec.DuplicateTag("x"))
  |> should.equal("union tag \"x\" appears twice")
}

pub fn schema_document_test() {
  codec.schema_document(codec.StringSchema)
  |> should.equal(
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
      #("type", value.String("string")),
    ]),
  )
  codec.schema_document(codec.IntegerRangeSchema(-2, 2))
  |> should.equal(
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
      #("type", value.String("integer")),
      #("minimum", value.Number(int_num(-2))),
      #("maximum", value.Number(int_num(2))),
    ]),
  )
  codec.schema_value(
    codec.UnionSchema([
      codec.VariantSchema("a", Some(codec.BoolSchema)),
      codec.VariantSchema("b", None),
    ]),
  )
  |> value.to_string
  |> should.equal(
    "{\"type\":\"object\",\"oneOf\":[{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"a\"},\"value\":{\"type\":\"boolean\"}},\"required\":[\"tag\",\"value\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"b\"}},\"required\":[\"tag\"],\"additionalProperties\":false}]}",
  )
}
