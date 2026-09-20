import gleeunit/should
import json/blueprint/codec
import json/blueprint/number
import json/blueprint/value

pub type Priority {
  Low
  Normal
  Urgent
}

pub type SimpleRecord {
  SimpleRecord(title: String, count: Int, note: codec.Optional(String))
}

fn cannot_decode(reason: codec.DecodeReason) -> Result(a, codec.DecodeError) {
  Error(codec.CannotDecode(reason))
}

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

pub fn string_codec_test() {
  let c = codec.string()
  codec.encode(c, "hello")
  |> should.equal(Ok(value.String("hello")))

  codec.decode(c, value.String("hello"))
  |> should.equal(Ok("hello"))

  codec.decode(c, value.Bool(True))
  |> should.equal(cannot_decode(codec.DecodeExpectedString))

  codec.schema(c)
  |> should.equal(Ok(codec.StringSchema))
}

pub fn int_codec_test() {
  let c = codec.int()
  let expected_num = int_num(42)

  codec.encode(c, 42)
  |> should.equal(Ok(value.Number(expected_num)))

  codec.decode(c, value.Number(expected_num))
  |> should.equal(Ok(42))

  codec.decode(c, value.String("42"))
  |> should.equal(cannot_decode(codec.DecodeExpectedInt))

  codec.schema(c)
  |> should.equal(Ok(codec.IntSchema))
}

pub fn number_codec_test() {
  let c = codec.number()
  let num = int_num(99)

  codec.encode(c, num)
  |> should.equal(Ok(value.Number(num)))

  codec.decode(c, value.Number(num))
  |> should.equal(Ok(num))

  codec.decode(c, value.Null)
  |> should.equal(cannot_decode(codec.DecodeExpectedNumber))

  codec.schema(c)
  |> should.equal(Ok(codec.NumberSchema))
}

pub fn bool_codec_test() {
  let c = codec.bool()

  codec.encode(c, True)
  |> should.equal(Ok(value.Bool(True)))
  codec.encode(c, False)
  |> should.equal(Ok(value.Bool(False)))

  codec.decode(c, value.Bool(True))
  |> should.equal(Ok(True))
  codec.decode(c, value.Bool(False))
  |> should.equal(Ok(False))

  codec.decode(c, value.String("true"))
  |> should.equal(cannot_decode(codec.DecodeExpectedBool))

  codec.schema(c)
  |> should.equal(Ok(codec.BoolSchema))
}

pub fn pair_codec_test() {
  let c = codec.pair(codec.string(), codec.int())

  codec.encode(c, #("item", 10))
  |> should.equal(
    Ok(value.Array([value.String("item"), value.Number(int_num(10))])),
  )

  codec.decode(
    c,
    value.Array([value.String("item"), value.Number(int_num(10))]),
  )
  |> should.equal(Ok(#("item", 10)))

  // Wrong tuple length
  codec.decode(c, value.Array([value.String("item")]))
  |> should.equal(cannot_decode(codec.DecodeWrongTupleLength(2, 1)))

  // Non-array
  codec.decode(c, value.String("not-an-array"))
  |> should.equal(cannot_decode(codec.DecodeExpectedArray))

  // Element error at index
  codec.decode(c, value.Array([value.Bool(False), value.Number(int_num(10))]))
  |> should.equal(
    Error(codec.DecodeAtIndex(0, codec.CannotDecode(codec.DecodeExpectedString))),
  )

  codec.schema(c)
  |> should.equal(Ok(codec.PairSchema(codec.StringSchema, codec.IntSchema)))
}

pub fn list_codec_test() {
  let c = codec.list(codec.string())

  codec.encode(c, ["a", "b"])
  |> should.equal(Ok(value.Array([value.String("a"), value.String("b")])))

  codec.decode(c, value.Array([value.String("a"), value.String("b")]))
  |> should.equal(Ok(["a", "b"]))

  codec.decode(c, value.Array([value.String("a"), value.Bool(True)]))
  |> should.equal(
    Error(codec.DecodeAtIndex(1, codec.CannotDecode(codec.DecodeExpectedString))),
  )

  codec.decode(c, value.Null)
  |> should.equal(cannot_decode(codec.DecodeExpectedArray))

  codec.schema(c)
  |> should.equal(Ok(codec.ListSchema(codec.StringSchema)))
}

pub fn nullable_codec_test() {
  let c = codec.nullable(codec.string())

  codec.encode(c, codec.Null)
  |> should.equal(Ok(value.Null))

  codec.encode(c, codec.NonNull("text"))
  |> should.equal(Ok(value.String("text")))

  codec.decode(c, value.Null)
  |> should.equal(Ok(codec.Null))

  codec.decode(c, value.String("text"))
  |> should.equal(Ok(codec.NonNull("text")))

  codec.decode(c, value.Bool(True))
  |> should.equal(cannot_decode(codec.DecodeExpectedString))

  codec.schema(c)
  |> should.equal(Ok(codec.NullableSchema(codec.StringSchema)))
}

pub fn object_codec_test() {
  let assert Ok(props1) =
    codec.combine(
      codec.required("title", codec.string()),
      codec.required("count", codec.int()),
    )
  let assert Ok(props2) =
    codec.combine(props1, codec.optional("note", codec.string()))

  let record_codec =
    codec.imap(
      codec.object(props2),
      fn(raw) {
        let #(#(title, count), note) = raw
        SimpleRecord(title, count, note)
      },
      fn(r) { #(#(r.title, r.count), r.note) },
    )

  // Encode with present optional
  codec.encode(
    record_codec,
    SimpleRecord("Book", 5, codec.Present("First edition")),
  )
  |> should.equal(
    Ok(
      value.Object([
        #("title", value.String("Book")),
        #("count", value.Number(int_num(5))),
        #("note", value.String("First edition")),
      ]),
    ),
  )

  // Encode with missing optional
  codec.encode(record_codec, SimpleRecord("Book", 5, codec.Missing))
  |> should.equal(
    Ok(
      value.Object([
        #("title", value.String("Book")),
        #("count", value.Number(int_num(5))),
      ]),
    ),
  )

  // Decode with present optional
  codec.decode(
    record_codec,
    value.Object([
      #("title", value.String("Book")),
      #("count", value.Number(int_num(5))),
      #("note", value.String("First edition")),
    ]),
  )
  |> should.equal(Ok(SimpleRecord("Book", 5, codec.Present("First edition"))))

  // Decode with missing optional
  codec.decode(
    record_codec,
    value.Object([
      #("title", value.String("Book")),
      #("count", value.Number(int_num(5))),
    ]),
  )
  |> should.equal(Ok(SimpleRecord("Book", 5, codec.Missing)))

  // Missing required field
  codec.decode(record_codec, value.Object([#("title", value.String("Book"))]))
  |> should.equal(
    Error(codec.DecodeAtField(
      "count",
      codec.CannotDecode(codec.DecodeMissingProperty("count")),
    )),
  )

  // Closed object: unexpected extra field rejected
  codec.decode(
    record_codec,
    value.Object([
      #("title", value.String("Book")),
      #("count", value.Number(int_num(5))),
      #("extra", value.Null),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "extra",
      codec.CannotDecode(codec.DecodeUnknownProperty("extra")),
    )),
  )

  // Duplicate key rejected on decode
  codec.decode(
    record_codec,
    value.Object([
      #("title", value.String("Book")),
      #("count", value.Number(int_num(5))),
      #("title", value.String("Another")),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "title",
      codec.CannotDecode(codec.DecodeDuplicateProperty("title")),
    )),
  )

  // Combine duplicate property error
  codec.combine(
    codec.required("dup", codec.string()),
    codec.optional("dup", codec.int()),
  )
  |> should.equal(Error(codec.DuplicateProperty("dup")))
}

pub fn string_enum_test() {
  // Empty enum error
  let empty: Result(codec.Codec(Priority), codec.EnumError) =
    codec.string_enum([])
  empty |> should.equal(Error(codec.EmptyEnum))

  // Duplicate label error
  codec.string_enum([#("same", Low), #("same", Normal)])
  |> should.equal(Error(codec.DuplicateEnumLabel("same")))

  // Duplicate value error
  codec.string_enum([#("low", Low), #("other_low", Low)])
  |> should.equal(Error(codec.DuplicateEnumValue(0, 1)))

  // Valid enum
  let assert Ok(priority_codec) =
    codec.string_enum([
      #("low", Low),
      #("normal", Normal),
      #("urgent", Urgent),
    ])

  codec.encode(priority_codec, Normal)
  |> should.equal(Ok(value.String("normal")))

  codec.decode(priority_codec, value.String("urgent"))
  |> should.equal(Ok(Urgent))

  // Unknown label
  codec.decode(priority_codec, value.String("critical"))
  |> should.equal(cannot_decode(codec.DecodeUnknownEnumLabel("critical")))

  // Non-string wire value
  codec.decode(priority_codec, value.Number(int_num(10)))
  |> should.equal(cannot_decode(codec.DecodeExpectedString))

  codec.schema(priority_codec)
  |> should.equal(Ok(codec.StringEnumSchema(["low", "normal", "urgent"])))
}

pub fn tagged_union_test() {
  // Duplicate tag error
  codec.tagged("dup", codec.string(), "dup", codec.int())
  |> should.equal(Error(codec.DuplicateTag("dup")))

  let assert Ok(tagged_codec) =
    codec.tagged("left", codec.string(), "right", codec.int())

  // Left encode & decode
  let left_val = codec.Left("hello")
  let expected_left_wire =
    value.Object([
      #("tag", value.String("left")),
      #("value", value.String("hello")),
    ])

  codec.encode(tagged_codec, left_val)
  |> should.equal(Ok(expected_left_wire))

  codec.decode(tagged_codec, expected_left_wire)
  |> should.equal(Ok(left_val))

  // Right encode & decode
  let right_val = codec.Right(77)
  let expected_right_wire =
    value.Object([
      #("tag", value.String("right")),
      #("value", value.Number(int_num(77))),
    ])

  codec.encode(tagged_codec, right_val)
  |> should.equal(Ok(expected_right_wire))

  codec.decode(tagged_codec, expected_right_wire)
  |> should.equal(Ok(right_val))

  // Unknown tag
  codec.decode(
    tagged_codec,
    value.Object([
      #("tag", value.String("unknown")),
      #("value", value.Null),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "tag",
      codec.CannotDecode(codec.DecodeUnknownTag("unknown")),
    )),
  )

  // Missing tag
  codec.decode(tagged_codec, value.Object([#("value", value.String("val"))]))
  |> should.equal(
    Error(codec.DecodeAtField("tag", codec.CannotDecode(codec.DecodeMissingTag))),
  )

  // Missing value payload
  codec.decode(tagged_codec, value.Object([#("tag", value.String("left"))]))
  |> should.equal(
    Error(codec.DecodeAtField(
      "value",
      codec.CannotDecode(codec.DecodeMissingTagPayload("Missing payload")),
    )),
  )

  // Present non-string tag returns structured wrong-type error
  codec.decode(
    tagged_codec,
    value.Object([
      #("tag", value.Number(int_num(123))),
      #("value", value.String("hello")),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "tag",
      codec.CannotDecode(codec.DecodeExpectedString),
    )),
  )

  codec.decode(
    tagged_codec,
    value.Object([
      #("tag", value.Bool(True)),
      #("value", value.String("hello")),
    ]),
  )
  |> should.equal(
    Error(codec.DecodeAtField(
      "tag",
      codec.CannotDecode(codec.DecodeExpectedString),
    )),
  )

  // Schema
  codec.schema(tagged_codec)
  |> should.equal(
    Ok(codec.TaggedSchema("left", codec.StringSchema, "right", codec.IntSchema)),
  )
}

pub fn range_codec_test() {
  // Reversed range error
  codec.integer_between(10, 5)
  |> should.equal(Error(codec.InvalidIntegerBounds(10, 5)))

  let assert Ok(bounded_int) = codec.integer_between(1, 10)

  // In-bounds
  codec.encode(bounded_int, 5)
  |> should.equal(Ok(value.Number(int_num(5))))
  codec.decode(bounded_int, value.Number(int_num(5)))
  |> should.equal(Ok(5))

  // Edge in-bounds
  codec.decode(bounded_int, value.Number(int_num(1)))
  |> should.equal(Ok(1))
  codec.decode(bounded_int, value.Number(int_num(10)))
  |> should.equal(Ok(10))

  // Out of bounds encode
  codec.encode(bounded_int, 0)
  |> should.equal(
    Error(codec.CannotEncode(codec.EncodeIntegerOutsideRange(1, 10, 0))),
  )
  codec.encode(bounded_int, 11)
  |> should.equal(
    Error(codec.CannotEncode(codec.EncodeIntegerOutsideRange(1, 10, 11))),
  )

  // Out of bounds decode
  codec.decode(bounded_int, value.Number(int_num(0)))
  |> should.equal(cannot_decode(codec.DecodeIntegerOutsideRange(1, 10, 0)))
  codec.decode(bounded_int, value.Number(int_num(11)))
  |> should.equal(cannot_decode(codec.DecodeIntegerOutsideRange(1, 10, 11)))

  // Schema
  codec.schema(bounded_int)
  |> should.equal(Ok(codec.IntegerRangeSchema(1, 10)))

  // Number range
  let min_num = int_num(-5)
  let max_num = int_num(5)
  let assert Ok(bounded_num) = codec.number_between(min_num, max_num)

  codec.encode(bounded_num, int_num(0))
  |> should.equal(Ok(value.Number(int_num(0))))

  codec.decode(bounded_num, value.Number(int_num(0)))
  |> should.equal(Ok(int_num(0)))

  codec.decode(bounded_num, value.Number(int_num(6)))
  |> should.equal(
    cannot_decode(codec.DecodeNumberOutsideRange(min_num, max_num, int_num(6))),
  )

  codec.schema(bounded_num)
  |> should.equal(Ok(codec.NumberRangeSchema(min_num, max_num)))
}

pub fn schema_document_test() {
  let doc = codec.schema_document(codec.StringSchema)
  doc
  |> should.equal(
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
      #("type", value.String("string")),
    ]),
  )

  let int_range_doc = codec.schema_document(codec.IntegerRangeSchema(-2, 2))
  int_range_doc
  |> should.equal(
    value.Object([
      #("$schema", value.String("https://json-schema.org/draft/2020-12/schema")),
      #("type", value.String("integer")),
      #("minimum", value.Number(int_num(-2))),
      #("maximum", value.Number(int_num(2))),
    ]),
  )
}
