# Migrating to the json_blueprint 2.0 API

This guide moves code written against the unreleased 2.0 branch (up to commit
`787cf12`) to the redesigned 2.0 API. It lists every public item that was
removed or changed, with its replacement and a before→after snippet, grouped
by module. For 1.7.1 code, see [the 1.x → 2.0 guide](migration-2.0.md).

**Erlang and JavaScript FFI callers.** The Gleam compiler does not check
calls from Erlang or JavaScript source into this package. Generated module
names and function arities changed (for example
`json@blueprint@number:number_limits/3` became `limits/3` without an
`{ok, _}` wrapper, and `parse_number(Limits, Token)` became
`parse(Token, Limits)`). Search native sources (`*.erl`, `*.mjs`) for
`json@blueprint@` and update every call; a missed call fails only at run
time.

The sections:

1. [Module map](#module-map)
2. [codec](#codec): records, unions, enums and bounds, mapping, errors,
   definitions, `Schema`, generator helpers, text decoding
3. [value](#value), [number](#number)
4. [parser, parser_limits, json_text](#parser-parser_limits-json_text)
5. [runtime and document → contract](#runtime-and-document--contract)
6. [codegen](#codegen), [dynamic and the root module](#dynamic-and-the-root-module)
7. [Index of the symbols the dependents use](#index-of-the-symbols-the-dependents-use)

## Module map

| Before                                  | After                                                                    |
| --------------------------------------- | ------------------------------------------------------------------------ |
| `json/blueprint/codec`                  | `json/blueprint/codec`, redesigned                                       |
| `json/blueprint/value`                  | `json/blueprint/value`, which also holds the parser, limits and renderer |
| `json/blueprint/number`                 | `json/blueprint/number`, trimmed                                         |
| `json/blueprint/parser`                 | `json/blueprint/value` (`parse`, `parse_bits`), `json/blueprint/contract` (`parse`) |
| `json/blueprint/parser_limits`          | `json/blueprint/value` (`Limits`, `default_limits`, `with_*`)            |
| `json/blueprint/json_text`              | `json/blueprint/value` (`to_string`)                                     |
| `json/blueprint/runtime`                | `json/blueprint/contract`                                                |
| `json/blueprint/document`               | `json/blueprint/contract` (`load`, `DocumentError`)                      |
| `json/blueprint/codegen`                | the dev-only package `json_blueprint_codegen` in `codegen/`; same module name |
| `json/blueprint/dynamic`                | internal; use `gleam/dynamic/decode`                                      |
| `json/blueprint`, `json/blueprint/schema` | unchanged 1.x API; `Decoder` and `FieldDecoder` are opaque              |

## codec

### Records: `record2`, `record3`, `combine`, `object`, `required`, `optional`, `optional_option`, `empty`, `field`

All of these are replaced by one `use`-based builder: `field` (required),
`optional_field` (optional, as `Option`), and `success` (the end of the
record). Pass each getter with its `get:` label; it needs no type
annotation (see [Follow-up: record getters without
annotations](#follow-up-record-getters-without-annotations)). `Properties`,
`PropertyError`, `Optional`, `Missing` and `Present` are removed.

```gleam
// before
let assert Ok(task) =
  codec.record2(
    codec.required("id", id),
    codec.required("title", codec.string()),
    Task,
    fn(task) { task.id },
    fn(task) { task.title },
  )

// after
pub fn task_codec() -> codec.Codec(Task) {
  use id <- codec.field("id", codec.integer_between(1, 100_000), get: fn(t) {
    t.id
  })
  use title <- codec.field("title", codec.string(), get: fn(t) { t.title })
  codec.success(Task(id:, title:))
}
```

A `combine` chain with tuples, `object` and `imap` becomes the same builder
without tuples:

```gleam
// before
let assert Ok(props) =
  codec.combine(codec.required("name", codec.string()), codec.required("age", age))
let assert Ok(props) =
  codec.combine(props, codec.optional_option("email", codec.string()))
codec.object(props)
|> codec.imap(
  fn(t) {
    let #(#(name, age), email) = t
    User(name:, age:, email:)
  },
  fn(u) { #(#(u.name, u.age), u.email) },
)

// after
use name <- codec.field("name", codec.string(), get: fn(u) { u.name })
use age <- codec.field("age", age, get: fn(u) { u.age })
use email <- codec.optional_field("email", codec.string(), get: fn(u) {
  u.email
})
codec.success(User(name:, age:, email:))
```

`optional(name, c)` returned `Optional(a)`; `optional_field` gives `Option(a)`
(`Missing` → `None`, `Present(x)` → `Some(x)`). `optional_option(name, c)` is
exactly `optional_field(name, c, ..)`.

The single-property `codec.field(name, inner)`, which built an object with one
required property, is now a one-field record:

```gleam
// before
codec.field("sku", codec.string()) |> codec.imap(StockQuery, fn(q) { q.sku })
codec.field("query", codec.string() |> codec.describe("Search terms"))

// after
{
  use sku <- codec.field("sku", codec.string(), get: fn(q) { q.sku })
  codec.success(StockQuery(sku))
}
{
  use query <- codec.field(
    "query",
    codec.string() |> codec.describe("Search terms"),
    get: fn(query) { query },
  )
  codec.success(query)
}
```

`codec.object(codec.empty())` (an empty object of `Nil`) is `codec.success(Nil)`.

A duplicate property name was `Error(DuplicateProperty(name))` from
`combine`/`record2`/`record3`; it is now a definition mistake (see
[Definitions](#definitions-panic-at-first-use-and-check)).

### Unions: `tagged`, `Either`, `Left`, `Right`, `UnionError`

`tagged(left_tag, left, right_tag, right)` with `Either` is replaced by an
N-ary builder. The wire stays `{"tag": ..., "value": ...}`; a `unit_variant`
has no `"value"`.

```gleam
// before
let assert Ok(state) =
  codec.tagged("drafting", codec.int(), "reviewing", draft_codec())
codec.imap(
  state,
  fn(either) {
    case either {
      codec.Left(revision) -> Drafting(revision)
      codec.Right(draft) -> Reviewing(draft)
    }
  },
  fn(state) {
    case state {
      Drafting(revision) -> codec.Left(revision)
      Reviewing(draft) -> codec.Right(draft)
    }
  },
)

// after
codec.union({
  use drafting <- codec.variant("drafting", codec.int(), Drafting)
  use reviewing <- codec.variant("reviewing", draft_codec(), Reviewing)
  codec.match(fn(state) {
    case state {
      Drafting(revision) -> drafting(revision)
      Reviewing(draft) -> reviewing(draft)
    }
  })
})
```

A `Left(Nil)` case over `codec.object(codec.empty())` becomes a
`unit_variant`: `use stop <- codec.unit_variant("stop", StopRequested)`. Its
wire changes from `{"tag":"stop","value":{}}` to `{"tag":"stop"}`; keep a
`variant("stop", codec.success(Nil), fn(_) { StopRequested })` if stored data
has the old form.

A duplicate tag was `Error(DuplicateTag(tag))`; it is now a definition mistake.

### Enums and bounds: `string_enum`, `integer_between`, `number_between`

They return `Codec(a)` instead of `Result`. `EnumError` and `ConstraintError`
are removed.

```gleam
// before
let assert Ok(role) = codec.string_enum([#("admin", Admin), #("member", Member)])
let assert Ok(age) = codec.integer_between(0, 150)
let assert Ok(score) = codec.number_between(low, high)

// after
let role = codec.string_enum([#("admin", Admin), #("member", Member)])
let age = codec.integer_between(0, 150)
let score = codec.number_between(low, high)
```

| Before                                         | After (`DefinitionError`)             |
| ---------------------------------------------- | ------------------------------------- |
| `EmptyEnum`                                    | `EmptyEnum`                           |
| `DuplicateEnumLabel(label)`                    | `DuplicateEnumLabel(label)`           |
| `DuplicateEnumValue(first_index, repeated_index)` | `DuplicateEnumValue(label)`: the second label |
| `InvalidIntegerBounds(min, max)`               | `ReversedIntegerBounds(minimum, maximum)`, or `UnsafeIntegerBound(bound)` on JavaScript |
| `ReversedNumberBounds(min, max)`               | `ReversedNumberBounds(minimum, maximum)` |
| `DuplicateProperty(name)` (`PropertyError`)    | `DuplicateFieldName(name)`            |
| `DuplicateTag(tag)` (`UnionError`)             | `DuplicateTag(tag)`                   |
| new                                            | `NotARecord(after_field)`, `EmptyUnion` |

### Definitions: panic at first use, and `check`

A mistaken definition no longer returns an error from its constructor. It
panics with a message naming the field, label, tag or bounds when the
mistaken part is first used (encoding, decoding or `schema`), for example
`json_blueprint: invalid codec definition: enum label "draft" appears twice`.
For a definition built from runtime data, `codec.check(codec)` returns
`Result(Codec(a), DefinitionError)` without panicking:

```gleam
// before
case codec.string_enum(pairs_from_database) {
  Ok(status) -> use_it(status)
  Error(error) -> report(error)
}

// after
case codec.check(codec.string_enum(pairs_from_database)) {
  Ok(status) -> use_it(status)
  Error(error) -> report(codec.describe_definition_error(error))
}
```

### Nullable: `Nullable`, `Null`, `NonNull`

`nullable(c)` returns `Codec(Option(a))`: `Null` → `None`, `NonNull(x)` →
`Some(x)`. With an optional field, absent, `null` and a value are `None`,
`Some(None)` and `Some(Some(x))`.

```gleam
// before
case item {
  codec.Null -> ..
  codec.NonNull(x) -> ..
}

// after
case item {
  None -> ..
  Some(x) -> ..
}
```

### Mapping: `imap`, `try_imap`, `new`, `from_parts`

| Before                                       | After                                                        |
| -------------------------------------------- | ------------------------------------------------------------ |
| `imap(codec, from, to)`                      | `map(codec, decode: from, encode: to)`                       |
| `try_imap(codec, from, to)`                  | `try_map(codec, decode:, encode:, placeholder:)`; the functions return `Result(_, String)` |
| `new(encode, decode)`                        | `custom(encode:, decode:, schema: None, placeholder:)`       |
| `from_parts(encode, decode, schema)`         | `custom(encode:, decode:, schema: Some(schema), placeholder:)` |

```gleam
// before
codec.try_imap(codec.string(), check_date, Ok)
// where check_date returned Result(Date, codec.DecodeError)

// after
codec.try_map(
  codec.string(),
  decode: fn(text) { check_date(text) |> result.replace_error("not a date") },
  encode: fn(date) { Ok(date_text(date)) },
  placeholder: epoch(),
)

// before
codec.new(Ok, Ok)
codec.from_parts(Ok, validate, schema)

// after
codec.custom(encode: Ok, decode: Ok, schema: None, placeholder: value.Null)
codec.custom(encode: Ok, decode: validate, schema: Some(schema), placeholder: value.Null)
```

The placeholder is any value of the type; `decoder` uses it on failure, as
`decode.failure` does. A failed `try_map` conversion is
`Custom(message)` at the codec's path. Inside `custom`, build errors with
`codec.decode_failure(message)` and `codec.encode_failure(message)`, or return
the errors of the codecs you call.

A `try_map` over a whole record fails at the record's own path, `[]` at the
root. To keep a check across fields located at the field it concerns, build
that field's codec inside the record from the fields decoded before it:

```gleam
// before: the failure is at [], whatever field it concerns
codec.try_map(
  invoice_fields(),
  decode: check_total,
  encode: check_total,
  placeholder: blank(),
)

// after: the failure is at [Field("total_cents")], in both directions
use line_items <- codec.field(
  "line_items",
  codec.list(line_item_codec()),
  get: fn(i) { i.line_items },
)
use total_cents <- codec.field(
  "total_cents",
  total_matching(line_items),
  get: fn(i) { i.total_cents },
)
```

where `total_matching(line_items)` is a `try_map` over `codec.int()`. When
the record describes itself, it receives placeholder values, so its schema
must not depend on them. The README's `order_codec` is a tested example.

### Errors: `EncodeError`, `DecodeError`, `EncodeReason`, `DecodeReason`, `JsonDecodeError`

Errors are flat `{path, reason}` records with one shared `Reason` union.
The nested constructors are removed.

| Before                                       | After                                                    |
| -------------------------------------------- | -------------------------------------------------------- |
| `CannotDecode(reason)`                       | `DecodeError(path: [], reason: reason)`                  |
| `DecodeAtField(name, inner)`                 | `Field(name)` prepended to `inner.path`                  |
| `DecodeAtIndex(i, inner)`                    | `Index(i)` prepended to `inner.path`                     |
| `CannotEncode(reason)`, `EncodeAtField`, `EncodeAtIndex` | `EncodeError(path, reason)`, the same way      |
| `JsonDecodeError`, `TypedCodecFailure(e)`    | `DecodeError`: `decode_json` returns it directly         |
| `BlueprintParserFailure(failure)`            | `DecodeError([], InvalidJson(value.ParseError))`         |
| `NativeJsonFailure(e)`                       | removed; generated native decoders return `json.DecodeError` |
| `BlueprintJsonParseFailure`, `BlueprintJsonLocation`, `BlueprintJsonParseReason` | `value.ParseError`, `value.Location`, `value.ParseReason` |
| `render_json_decode_error(e)`                | `describe_decode_error(e)`                               |
| new                                          | `describe_encode_error`, `describe_definition_error`, `is_limit_exceeded`, `decode_failure`, `encode_failure` |

| Before (`DecodeReason`)                      | After (`Reason`)                                         |
| -------------------------------------------- | -------------------------------------------------------- |
| `DecodeExpectedString`, `DecodeExpectedInt`, `DecodeExpectedNumber`, `DecodeExpectedBool`, `DecodeExpectedArray`, `DecodeExpectedObject` | `ExpectedString`, `ExpectedInt`, `ExpectedNumber`, `ExpectedBool`, `ExpectedArray`, `ExpectedObject` |
| `DecodeExpectedTaggedObject`                 | `ExpectedObject`                                         |
| `DecodeUnknownEnumLabel(label)`              | `UnknownEnumLabel` (no payload)                          |
| `DecodeUnknownTag(tag)`                      | `UnknownTag` at path `[Field("tag")]`                    |
| `DecodeMissingTag`                           | `MissingField` at `[Field("tag")]`                       |
| `DecodeMissingTagPayload(_)`                 | `MissingField` at `[Field("value")]`                     |
| `DecodeMissingProperty(name)`                | `MissingField` at `[.., Field(name)]`                    |
| `DecodeUnknownProperty(name)`                | `UnknownField` at `[.., Field(name)]`                    |
| `DecodeDuplicateProperty(name)`              | `DuplicateField` at `[.., Field(name)]`                  |
| `DecodeWrongTupleLength(expected, actual)`   | `WrongLength(expected, actual)`                          |
| `DecodeInvalidWireValue(_)`                  | removed (it was only produced by native decoding)        |
| `DecodeIntegerOutsideRange(min, max, actual)` | `IntegerOutsideRange(minimum, maximum)`                 |
| `DecodeNumberOutsideRange(min, max, actual)` | `NumberOutsideRange(minimum, maximum)`                   |
| `CustomDecodeReason(text)`                   | `Custom(message)`                                        |
| `CustomDecodeReason("Schema mismatch")` from `runtime.decode` | `ContractMismatch`                      |
| new                                          | `InvalidJson(value.ParseError)`, `FloatOutOfRange`       |

| Before (`EncodeReason`)                      | After (`Reason`)                                         |
| -------------------------------------------- | -------------------------------------------------------- |
| `EncodeUnknownEnumValue(_)`                  | `UnknownEnumValue`                                       |
| `EncodeInvalidNativeValue("UnsafeNativeInteger")` and the other native texts | `UnsafeInteger`             |
| `EncodeIntegerOutsideRange(min, max, actual)` | `IntegerOutsideRange(minimum, maximum)`                 |
| `EncodeNumberOutsideRange(min, max, actual)` | `NumberOutsideRange(minimum, maximum)`                   |
| `CustomEncodeReason("NonNull must encode a non-null value")` | `NullInsideNullable`                       |
| `CustomEncodeReason(text)`                   | `Custom(message)`                                        |
| `EncodeUnknownEnumLabel`, `EncodeUnknownTag`, `EncodeUnknownProperty`, `EncodeWrongTupleLength` | removed: never produced |
| new                                          | `NonFiniteFloat`, `UnrepresentableNumber(Number)`        |

```gleam
// before
fn decode_error(message: String) -> codec.DecodeError {
  codec.CannotDecode(codec.CustomDecodeReason(message))
}
case error {
  codec.TypedCodecFailure(codec.DecodeAtField(name, _)) -> name
  _ -> ""
}

// after
fn decode_error(message: String) -> codec.DecodeError {
  codec.decode_failure(message)
}
case error {
  codec.DecodeError(path: [codec.Field(name), ..], reason: _) -> name
  _ -> ""
}
```

A hand-written renderer over `string.inspect` (fabric's
`internal/invocation.gleam`) becomes `codec.describe_encode_error` or
`codec.describe_decode_error`. The library writes the path and the text of
its own reasons, which omit input values and unknown keys from the input. A
`Custom(message)` renders as the caller's message, verbatim, such as
`$["total_cents"]: total 9999 differs from line sum 4490`; an empty message
renders as `custom validation failed`. Up to `c96a8c3` every `Custom`
rendered as `custom validation failed`, so update any test or caller that
matches that text.

`Reason` may gain variants in minor releases: match it with a `_` branch.

A record now decodes its fields before it reports an unknown or repeated
key, so an object with both a bad field and an unknown key fails on the bad
field.

### Text: `decode_json`, `decode_json_with_limits`, `decode_json_native`, `decode_json_native_with_max_bytes`, `encode_json`, `from_json_parts`

| Before                                              | After                                                       |
| --------------------------------------------------- | ----------------------------------------------------------- |
| `decode_json(c, text) -> Result(a, JsonDecodeError)` | `decode_json(c, text) -> Result(a, DecodeError)`           |
| `decode_json_with_limits(c, limits, text)`          | `decode_json_with_limits(c, text, limits)`: argument order and `value.Limits` |
| `decode_json_native(c, text)`, `decode_json_native_with_max_bytes(c, max, text)` | removed from `codec`; generated modules keep `decode_<name>_json_native` |
| `from_json_parts(..)`                               | removed; generated codecs use `custom`                      |
| `encode_json`                                       | unchanged; a decimal is now written in plain form when its exponent is from -7 to 20 (`0.1`, not `1e-1`) |

```gleam
// before
case codec.decode_json(c, text) {
  Error(codec.BlueprintParserFailure(_)) -> bad_json()
  Error(codec.TypedCodecFailure(error)) -> bad_shape(error)
  Ok(x) -> ok(x)
}

// after
case codec.decode_json(c, text) {
  Error(codec.DecodeError(_, codec.InvalidJson(_))) -> bad_json()
  Error(error) -> bad_shape(error)
  Ok(x) -> ok(x)
}
```

### New: bridges and `float`

`codec.to_json(c, x) -> Result(json.Json, EncodeError)` and
`codec.decoder(c) -> decode.Decoder(a)` replace hand-written `gleam/json`
twins of a codec (for Grind workers, Saga storage):

```gleam
// before: a second encoder and decoder written with gleam/json
worker.codec(version, encode_job, job_decoder())

// after
worker.codec(
  version,
  fn(job) {
    case codec.to_json(job_codec(), job) {
      Ok(json) -> json
      // The consumer's encoder has no failure channel. Fail loudly rather
      // than store `null` for a value the codec rejects.
      Error(error) -> panic as codec.describe_encode_error(error)
    }
  },
  codec.decoder(job_codec()),
)
```

`to_json` fails only when the value violates the codec (a refinement such as
`integer_between`, a `try_map` encode check, or a number with no exact JSON
form). When the consumer's encoder cannot fail, as with Grind's
`worker.codec`, never fall back to `json.null()`: that stores a value the
decoder will later reject. Panic with the described error, or validate the
value before submitting it.

`codec.float()` is a `Codec(Float)` that rounds to the nearest float on
decode; use `codec.number()` to keep numbers exact.

### `Schema`

| Before                                   | After                                                              |
| ---------------------------------------- | ------------------------------------------------------------------ |
| `FieldSchema(name, inner)`               | `ObjectSchema([PropertySchema(name, True, inner)])`                |
| `TaggedSchema(left_tag, left, right_tag, right)` | `UnionSchema([VariantSchema(left_tag, Some(left)), VariantSchema(right_tag, Some(right))])` |
| positional fields                        | labelled fields (`DescribedSchema(description:, inner:)`, `ListSchema(items:)`, ...); positional patterns still work |

```gleam
// before
case schema {
  codec.FieldSchema(_, _) -> True
  codec.TaggedSchema(_, _, _, _) -> True
  codec.ObjectSchema(_) -> True
  _ -> False
}
codec.TaggedSchema(_, left, _, right) -> supported(left) && supported(right)

// after
case schema {
  codec.ObjectSchema(_) -> True
  codec.UnionSchema(_) -> True
  _ -> False
}
codec.UnionSchema(variants) ->
  list.all(variants, fn(variant) {
    case variant.payload {
      Some(payload) -> supported(payload)
      None -> True
    }
  })
```

`Schema` may gain variants in minor releases: keep a `_` branch.
`schema`, `schema_json`, `schema_value`, `schema_document`, `describe`,
`PropertySchema` and `SchemaError(UnknownSchema)` are unchanged.

### Generator helpers

The functions that generated modules called move to the internal module
`json/blueprint/internal/generated`, with shorter names. Application code
should use codecs instead:

| Before (`codec.`)                               | After                                                 |
| ----------------------------------------------- | ----------------------------------------------------- |
| `encode_string_value(s)`                        | `codec.encode(codec.string(), s)`                     |
| `encode_int_value(n)`                           | `codec.encode(codec.int(), n)`                        |
| `decode_int_value(raw)`                         | `codec.decode(codec.int(), raw)`                      |
| `decode_string_value`, `encode_bool_value`, `decode_bool_value`, `encode_number_value`, `decode_number_value` | `codec.encode`/`decode` with `string()`, `bool()`, `number()` |
| `encode_integer_between_value(min, max, n)`, `decode_integer_between_value` | `codec.encode`/`decode` with `integer_between(min, max)` |
| `encode_native_int`, `encode_native_integer_between` | `codec.to_json(codec.int(), n)`                   |
| `decode_native_string`, `decode_native_int`, `decode_native_bool` | `decode.run(raw, codec.decoder(codec.string()))` and so on |
| `*_with` (`encode_pair_with`, `decode_list_with`, `encode_object_with`, ...) and `*_native_*_with` | `json/blueprint/internal/generated` (regenerate) |
| `encode_mapped_with`, `decode_mapped_with`      | `codec.map`                                           |

```gleam
// before
case codec.decode_int_value(wire_id) { .. }
codec.new(codec.encode_int_value, codec.decode_int_value)

// after
case codec.decode(codec.int(), wire_id) { .. }
codec.int()
```

## value

| Before                                        | After                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `object(entries, RejectDuplicates) -> Result(Value, ValueError)` | `object(entries) -> Result(Value, DuplicateKey)` |
| `ObjectKeyPolicy`, `RejectDuplicates`         | removed                                            |
| `ValueError`, `DuplicateObjectKey(key)`       | `DuplicateKey(key:)`                               |
| `null()`, `bool(b)`, `string(s)`, `number(n)`, `array(xs)` | the constructors `Null`, `Bool(b)`, `String(s)`, `Number(n)`, `Array(xs)` |
| new                                           | `parse`, `parse_bits`, `Limits`, `to_string`, `to_json`, `decoder`, `describe_parse_error`, `is_limit_exceeded` |

```gleam
// before
let assert Ok(entry) = value.object([#("k", value.string("v"))], value.RejectDuplicates)

// after
let assert Ok(entry) = value.object([#("k", value.String("v"))])
```

`value.to_json(v) -> Result(json.Json, Number)` converts exactly and fails with
the first number that has no exact `gleam/json` form. It replaces llm_wire's
float-based converter (`internal/schema.gleam`):

```gleam
// before: 80 lines of value-to-json conversion through Float
blueprint_value_to_json(codec.schema_value(schema))

// after
codec.schema_value(schema)
|> value.to_json
|> result.replace_error(types.PreparationError(
  "Number schema bound cannot be represented exactly as a JSON number",
))
```

`value.decoder()` reads a `Value` from `json.parse`.

## number

| Before                                        | After                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `NumberLimits`, `number_limits(a, b, c) -> Result(NumberLimits, LimitsError)` | `Limits`, `limits(max_token_bytes:, max_significant_digits:, max_exponent:) -> Limits`; a bound below 1 refuses every token |
| `LimitsError`                                 | removed                                            |
| new                                           | `default_limits()`: 1,024, 800, 1,200              |
| `parse_number(limits, token)`                 | `parse(token, limits)`                             |
| `number_text(n)`                              | `to_string(n)` (same text)                         |
| `compare(a, b) -> NumberOrder`; `LessThan`, `EqualTo`, `GreaterThan` | `compare(a, b) -> gleam/order.Order`; `order.Lt`, `order.Eq`, `order.Gt` |
| `integer_projection_limit(d)` with `to_int_exact(n, limit)` | `to_int(n, d)`                          |
| `IntegerProjectionLimit`, `IntegerProjectionLimitError`, `integer_projection_limit_for_bounds`, `integer_projection_limit_for_range_value`, `integer_projection_limit_for_number` | removed; pass a digit count to `to_int` |
| `FloatCandidate`, `small_integer_token`       | removed (private)                                  |
| `from_int`, `is_integer`, `from_float_exact`, `to_float_exact` and their error types | unchanged |
| new                                           | `from_float` (shortest decimal), `to_float` (nearest float) |

```gleam
// before
let assert Ok(limits) = number.number_limits(1024, 100, 1000)
let assert Ok(n) = number.parse_number(limits, "41")
let assert Ok(limit) = number.integer_projection_limit(64)
case number.to_int_exact(n, limit) { .. }
number.compare(a, b) == number.EqualTo
number.number_text(n)

// after
let assert Ok(n) = number.parse("41", number.limits(1024, 100, 1000))
case number.to_int(n, 64) { .. }
number.compare(a, b) == order.Eq
number.to_string(n)
```

## parser, parser_limits, json_text

| Before                                        | After                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `parser.default_limits()`, `parser_limits.default()` | `value.default_limits()`: 1 MiB, depth 64, 262,144 values |
| `parser.parser_limits(bytes, depth, numbers)`, `parser_limits.new(..)` | `value.default_limits() \|> value.with_max_bytes(bytes) \|> value.with_max_depth(depth) \|> value.with_number_limits(numbers)` |
| `parser_limits.with_max_bytes(l, n) -> Result(..)`, `with_max_depth` | `value.with_max_bytes(l, n) -> Limits`, `value.with_max_depth`; a bound below 1 rejects every input |
| `parser_limits.with_number_limits`            | `value.with_number_limits`                         |
| `parser_limits.max_bytes`, `max_depth`, `number_limits` | removed                                  |
| `ParserLimits`, both `LimitsError` types      | `value.Limits`; no error                           |
| new                                           | `value.with_max_elements` (default 262,144)        |
| `parser.parse_value_from_string(limits, text)` | `value.parse(text, limits)`                       |
| `parser.parse_value(limits, bytes)`           | `value.parse_bits(bytes, limits)`                  |
| `parser.parse_schema_document_from_string(limits, text)`, `parse_schema_document(limits, bytes)` | `contract.parse(text, limits)` |
| `parser.AdmissionError`: `ParseAdmissionError`, `DocumentAdmissionError` | `contract.LoadError`: `InvalidJson`, `InvalidDocument` |
| `parser.ParseError(location, kind)`, `Location` | `value.ParseError(location:, reason:)`, `value.Location` |
| `parser.ParseErrorKind`                       | `value.ParseReason`                                |
| `UnexpectedByte(text)`                        | `UnexpectedCharacter` (no payload; see the location) |
| `DuplicateObjectKey(key)`                     | `DuplicateObjectKey` (no payload)                  |
| `InvalidNumberToken(error)`                   | `InvalidNumber(error)`                             |
| `InvalidEscapeSequence`                       | `InvalidEscape`                                    |
| new                                           | `ElementLimitExceeded(max)`                        |
| `json_text.render_value(v)`                   | `value.to_string(v)`                               |

```gleam
// before
let assert Ok(limits) = parser_limits.with_max_bytes(parser_limits.default(), 64 * 1024)
case parser.parse_value_from_string(limits, text) { .. }
json_text.render_value(v)

// after
let limits = value.default_limits() |> value.with_max_bytes(64 * 1024)
case value.parse(text, limits) { .. }
value.to_string(v)
```

`value.to_string` writes a decimal with an exponent from -7 to 20 in plain
form (`12.5`, `0.001`), where `json_text.render_value` wrote `1.25e1`.

## runtime and document → contract

| Before                                        | After                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `runtime.RuntimeContract`                     | `contract.Contract`                                |
| `runtime.from_codec(c) -> Result(_, ContractError)` | `contract.from_codec(c) -> Result(Contract, codec.SchemaError)` |
| `runtime.from_schema(s) -> Result(_, ContractError)` | `contract.from_schema(s) -> Result(Contract, codec.DefinitionError)` |
| `runtime.ContractError`                       | `codec.DefinitionError` (`ReversedIntegerRange` → `ReversedIntegerBounds`, `ReversedNumberRange` → `ReversedNumberBounds`, `DuplicateSchemaProperty` → `DuplicateFieldName`, `DuplicateSchemaTag` → `DuplicateTag`, `EmptyStringEnum` → `EmptyEnum`, `DuplicateSchemaEnumLabel` → `DuplicateEnumLabel`); `UnknownSchema` → `codec.UnknownSchema` |
| `runtime.schema`, `validate`, `same_schema`, `decode` | `contract.schema`, `validate`, `same_schema`, `decode` |
| `runtime.encoded(v)`                          | `contract.value(v)`                                |
| `runtime.matches(contract, v)`                | removed: `contract.decode` checks the schema       |
| `runtime.ValidationError(path, reason)`       | `contract.ValidationError(path: List(codec.PathSegment), reason: codec.Reason)` |
| `runtime.PathSegment`: `Property(name)`, `Index(i)`, `TaggedBranch(tag)` | `codec.PathSegment`: `Field(name)`, `Index(i)`; no tag segment |
| `runtime.ValidationReason`                    | `codec.Reason`: `ExpectedString`, `ExpectedInteger` → `ExpectedInt`, `ExpectedNumber`, `ExpectedBoolean` → `ExpectedBool`, `ExpectedArray`, `ExpectedObject`, `UnknownEnumLabel(_)` → `UnknownEnumLabel`, `MissingProperty(_)` → `MissingField`, `UnknownProperty(_)` → `UnknownField`, `DuplicateProperty(_)` → `DuplicateField`, `WrongTupleLength` → `WrongLength`, `IntegerOutsideRange(min, max, _)` → `IntegerOutsideRange(min, max)`, `NumberOutsideRange(min, max, _)` → `NumberOutsideRange(min, max)`, `MissingTag` → `MissingField` at `[Field("tag")]`, `NonStringTag` → `ExpectedString` at `[Field("tag")]`, `UnknownTag(_)` → `UnknownTag` |
| `document.load(v)`                            | `contract.load(v)`                                 |
| `document.DocumentError`, `MalformedReason`, `UnsupportedReason`, `PathSegment` | `contract.DocumentError`, `MalformedReason`, `UnsupportedReason`, `codec.PathSegment` |
| `MissingField(name)` (`MalformedReason`)      | `MissingKeyword(name)`                             |
| `SchemaInvariant(path, ContractError)`        | `InvalidDefinition(path, codec.DefinitionError)`   |
| `UnsupportedDialect(path, actual)`            | `UnsupportedDialect(path, dialect)`                |
| new                                           | `contract.parse`, `value_codec`, `describe_validation_error`, `describe_document_error`, `describe_load_error` |

A union payload is validated under `[Field("value")]`; the old path was
`[Property("value"), TaggedBranch(tag)]`. Documents may now hold N-ary
`oneOf` unions and unit variants.

```gleam
// before: tool_hub's Codec(Value) over a contract plus a 37-line error map
fn contract_codec(contract: runtime.RuntimeContract) -> codec.Codec(Value) {
  codec.from_parts(
    Ok,
    fn(value) {
      runtime.validate(contract, value)
      |> result.map(runtime.encoded)
      |> result.map_error(decode_error)
    },
    runtime.schema(contract),
  )
}

// after
contract.value_codec(remote_contract)
```

```gleam
// before
let assert Ok(c) =
  parser.parse_schema_document_from_string(parser.default_limits(), text)
case runtime.validate(c, v) {
  Error(runtime.ValidationError(path, runtime.MissingProperty(_))) -> ..
  _ -> ..
}

// after
let assert Ok(c) = contract.parse(text, value.default_limits())
case contract.validate(c, v) {
  Error(contract.ValidationError(path, codec.MissingField)) -> ..
  _ -> ..
}
```

## codegen

`json/blueprint/codegen` moves to the dev-only package `json_blueprint_codegen`
in `codegen/` of this repository; add it as a dev dependency by path. The
module name is unchanged. Its API changes:

| Before                                        | After                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `integer_between(min, max) -> Result(Definition(Int), ConstraintError)` | `integer_between(min, max) -> Definition(Int)` |
| `combine(l, r) -> Result(Properties(#(a, b)), PropertyError)` | `combine(l, r) -> Properties(r, #(a, b))`; a repeated name is reported by `compile` |
| `Properties(a)`                               | `Properties(r, a)`, with `r` the record type        |
| `optional(name, d) -> Properties(Optional(a))`, `optional_option` | `optional(name, d) -> Properties(r, Option(a))` |
| `nullable(d) -> Definition(Nullable(a))`      | `nullable(d) -> Definition(Option(a))`              |
| `CompileError.InvalidEnum(EnumError)`         | `InvalidDefinition(codec.DefinitionError)`          |

Generated modules import `json/blueprint/internal/generated`.
`decode_<name>_json` returns `codec.DecodeError`; `decode_<name>_json_native`
returns `json.DecodeError`; `<name>_codec()` is built with `codec.custom`.
Regenerate every checked-in module once.

## dynamic and the root module

| Before                                        | After                                              |
| --------------------------------------------- | -------------------------------------------------- |
| `json/blueprint/dynamic` (31 functions)       | internal; use `gleam/dynamic/decode`               |
| `blueprint.Decoder(..)`, `FieldDecoder(..)` built or matched as records | opaque: build them with the combinators |
| `blueprint.get_dynamic_decoder(d) -> fn(Dynamic) -> Result(t, List(dynamic.DecodeError))` | returns `List(decode.DecodeError)` (same fields) |

## Index of the symbols the dependents use

Every symbol that relay, llm_wire, fabric (with its integrations and
consumers) and the oversight apps import from json_blueprint, with its
replacement. Unchanged symbols are listed as such.

### codec

| Symbol                         | Used by                                   | Replacement                                   |
| ------------------------------ | ----------------------------------------- | --------------------------------------------- |
| `Codec`                        | all                                       | unchanged                                     |
| `string`, `int`, `bool`, `list`, `pair`, `number` | all                    | unchanged                                     |
| `nullable`                     | extractor, fabric, llm_wire               | returns `Codec(Option(a))`                    |
| `Null`, `NonNull`              | fabric                                    | `None`, `Some`                                |
| `field` (single property)      | relay, apps, fabric, llm_wire             | a one-field record, see [Records](#records-record2-record3-combine-object-required-optional-optional_option-empty-field) |
| `required`, `optional`, `optional_option`, `combine`, `object`, `empty`, `record2`, `record3`, `{type Properties}`, `PropertyError` | relay, llm_wire, fabric, apps | `field`, `optional_field`, `success` |
| `imap`                         | apps, fabric                              | `map(codec, decode:, encode:)`                |
| `try_imap`                     | extractor, fabric                         | `try_map(codec, decode:, encode:, placeholder:)` |
| `new`, `from_parts`            | relay, fabric, tool_hub                   | `custom(encode:, decode:, schema:, placeholder:)` |
| `tagged`, `Left`, `Right`, `UnionError` | fabric                           | `union`, `variant`, `unit_variant`, `match`   |
| `string_enum`, `integer_between`, `number_between` | apps, fabric, relay, llm_wire | no `Result`; `check` for runtime data |
| `describe`                     | all                                       | unchanged                                     |
| `encode`, `decode`, `encode_json`, `schema`, `schema_json`, `schema_value`, `schema_document` | all | unchanged |
| `decode_json`                  | relay, fabric, apps                       | returns `DecodeError`                         |
| `render_json_decode_error`     | fabric, research_agent, support_desk      | `describe_decode_error`                       |
| `EncodeError`, `DecodeError`, `{type EncodeError}`, `{type DecodeError}` | relay, fabric, apps | flat `{path, reason}` records |
| `CannotDecode`, `CannotEncode`, `DecodeAtField`, `DecodeAtIndex`, `EncodeAtField`, `EncodeAtIndex` | fabric, extractor, tool_hub | `DecodeError(path, reason)`, `EncodeError(path, reason)`, `Field`, `Index` |
| `CustomDecodeReason`, `CustomEncodeReason` | extractor, fabric             | `decode_failure`, `encode_failure`, `Custom`  |
| `DecodeReason` and its variants (`DecodeExpected*`, `DecodeUnknownEnumLabel`, `DecodeUnknownTag`, `DecodeMissingTag`, `DecodeMissingProperty`, `DecodeUnknownProperty`, `DecodeDuplicateProperty`, `DecodeWrongTupleLength`, `DecodeIntegerOutsideRange`, `DecodeNumberOutsideRange`, `DecodeExpectedTaggedObject`) | tool_hub, extractor, fabric | `Reason`, see [Errors](#errors-encodeerror-decodeerror-encodereason-decodereason-jsondecodeerror) |
| `TypedCodecFailure`            | extractor                                 | `decode_json` returns `DecodeError` directly  |
| `SchemaError`, `{type SchemaError}`, `UnknownSchema` | relay, fabric       | unchanged                                     |
| `Schema`, `{type Schema}`, `StringSchema`, `IntSchema`, `NumberSchema`, `BoolSchema`, `StringEnumSchema`, `ListSchema`, `NullableSchema`, `ObjectSchema`, `PairSchema`, `IntegerRangeSchema`, `NumberRangeSchema`, `DescribedSchema`, `PropertySchema` | relay, llm_wire, fabric | unchanged (fields gained labels) |
| `FieldSchema`                  | relay, llm_wire, fabric                   | `ObjectSchema([PropertySchema(name, True, inner)])` |
| `TaggedSchema`                 | relay, llm_wire                           | `UnionSchema([VariantSchema(tag, Some(payload)), ..])` |
| `encode_string_value`, `encode_int_value`, `decode_int_value` | fabric, fabric_mcp, fabric_typesafe | `codec.encode`/`decode` with `string()` or `int()` |

### value

| Symbol                         | Used by                   | Replacement                              |
| ------------------------------ | ------------------------- | ---------------------------------------- |
| `Value`, `{type Value}`, `Null`, `Bool`, `String`, `Number`, `Array`, `Object` | all | unchanged |
| `object`, `RejectDuplicates`   | fabric                    | `object(entries)`                        |

### number

| Symbol                         | Used by                   | Replacement                              |
| ------------------------------ | ------------------------- | ---------------------------------------- |
| `Number`, `from_int`, `is_integer` | relay, llm_wire, fabric | unchanged                              |
| `compare`, `EqualTo`, `LessThan`, `GreaterThan` | fabric, llm_wire | `compare` returns `order.Order`; `order.Eq`, `order.Lt`, `order.Gt` |
| `number_text`                  | fabric, llm_wire, relay   | `to_string`                              |
| `number_limits`                | llm_wire, relay (tests)   | `limits(..)`, no `Result`                |
| `parse_number`                 | llm_wire, relay (tests)   | `parse(token, limits)`                   |
| `integer_projection_limit`, `to_int_exact` | llm_wire      | `to_int(n, digits)`                      |

### parser, parser_limits, json_text

| Symbol                         | Used by                   | Replacement                              |
| ------------------------------ | ------------------------- | ---------------------------------------- |
| `parser.default_limits`, `parser_limits.default` | tool_hub, llm_wire, relay, fabric | `value.default_limits()` |
| `parser_limits.with_max_bytes` | llm_wire, relay           | `value.with_max_bytes` (no `Result`)     |
| `parser.parse_value_from_string` | tool_hub, fabric, llm_wire | `value.parse(text, limits)`           |
| `parser.parse_value`           | relay                     | `value.parse_bits(bytes, limits)`        |
| `parser.parse_schema_document_from_string` | tool_hub      | `contract.parse(text, limits)`           |
| `json_text.render_value`       | fabric, relay             | `value.to_string`                        |

### runtime and document

| Symbol                         | Used by                   | Replacement                              |
| ------------------------------ | ------------------------- | ---------------------------------------- |
| `runtime.RuntimeContract`      | tool_hub, fabric, llm_wire | `contract.Contract`                     |
| `runtime.ValidatedValue`       | llm_wire                  | `contract.ValidatedValue`                |
| `runtime.from_codec`, `from_schema`, `schema`, `same_schema`, `validate`, `decode` | tool_hub, fabric, llm_wire | the same names in `contract` |
| `runtime.encoded`              | tool_hub                  | `contract.value`                         |
| `runtime.ValidationError`, `ValidationReason` and its variants, `Property`, `Index`, `TaggedBranch` | tool_hub | `contract.ValidationError` with `codec.Reason` and `codec.PathSegment`; `contract.value_codec` removes the map |
| `document.load`                | tool_hub, fabric          | `contract.load`                          |

## Follow-up: record getters without annotations

`codec.field` and `codec.optional_field` take the rest of the `use` block
before the getter, and the getter is passed with its `get:` label. Gleam
checks a call's arguments in parameter order, so the block, which ends in
`success`, fixes the record type before the getter is checked: getters need
no type annotation. Schemas, wire output and error paths are unchanged.

| Item                   | Before                                 | After                                  |
| ---------------------- | -------------------------------------- | -------------------------------------- |
| `codec.field`          | `field(named, of, get, then)`          | `field(named, of, then, get)`          |
| `codec.optional_field` | `optional_field(named, of, get, then)` | `optional_field(named, of, then, get)` |

```gleam
// before
use sku <- codec.field("sku", codec.string(), fn(q: StockQuery) { q.sku })
use note <- codec.optional_field("note", codec.string(), fn(t: Ticket) {
  t.note
})

// after
use sku <- codec.field("sku", codec.string(), get: fn(q) { q.sku })
use note <- codec.optional_field("note", codec.string(), get: fn(t) {
  t.note
})
```

The rule is mechanical: put `get: ` before the third argument of every
`use x <- codec.field(...)` and `use x <- codec.optional_field(...)`, and
drop the `fn(x: Type)` annotation if you like (it is still accepted). A call
that passes the callback explicitly names it: `codec.field(name, inner,
then: next, get:)`. A getter left without its label fills the `then` slot,
and the call fails to compile with a type mismatch at the getter, so no
call site changes meaning silently. Building a field's codec from the fields
decoded before it works as before.

Dependents (every site fails to compile until migrated):

| Package        | Sites | Files                                                                                                                                                                                                                                                                                                             |
| -------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| fabric         | 62    | `src/fabric/graph/llm.gleam`; `test/fabric/` (oracle, approved_context, observation, cancellation, readme_example, delegation, support/apps, support/codecs); `integrations/` fabric_postgres, fabric_mcp (2), fabric_saga (2); `consumers/` app, decision, jobs, writing; `experiments/graph_authoring/consumer` |
| relay          | 6     | `src/relay/tool.gleam` (module doc), `src/relay_conformance_server.gleam`, `test/relay/client_test.gleam`, `test/relay/test_codec.gleam`, `fixtures/negative/wrong_handler_codec.gleam`                                                                                                                           |
| llm_wire       | 2     | `test/llm_wire_api_test.gleam`, `test/tool_fixtures.gleam`                                                                                                                                                                                                                                                        |
| oversight apps | 88    | extractor (`invoice`, `jobs`, test), research_agent (`domain`, `publish`), secure_mcp (`reports`), support_desk (`domain`), tool_hub (`inventory`, `assistant`)                                                                                                                                                   |

## Wave 3 additions

Wave 3 adds two functions to `json/blueprint/codec`. Both are additive:
nothing that compiled stops compiling, and no schema, wire output or error
changes. Commit: `60c0dfb`.

| Item                                | Replaces                                                                     |
| ----------------------------------- | ---------------------------------------------------------------------------- |
| `codec.value() -> Codec(Value)`     | `codec.custom(encode: Ok, decode: Ok, schema: None, placeholder: value.Null)` |
| `codec.placeholder(Codec(a)) -> a`  | a placeholder written by hand for a type the wrapper did not build           |

### `codec.value`

A pass-through codec for JSON that the application forwards or inspects
itself. Decoding accepts any value and encoding returns it unchanged; the
parse limits of `decode_json` still bound it. It has no schema, so `schema`
returns `UnknownSchema` for it and for any codec built from it, exactly as
the `custom` it replaces. Use `contract.value_codec(contract)` when the
value's schema is known.

```gleam
// Before
codec.custom(encode: Ok, decode: Ok, schema: None, placeholder: Null)

// After
codec.value()
```

Dependents that can adopt it:
`oversight/apps/tool_hub/src/tool_hub/remote_tools.gleam:120` (a peer's
tool output, forwarded as sent).

### `codec.placeholder`

Returns the value a codec describes itself with: `""` for `string()`, `0`
for `int()`, `minimum` for `integer_between`, `[]` for `list`, `None` for
`nullable`, `value.Null` for `value()`, the first variant of a union or
enum, and the record built from its fields' placeholders. A generic wrapper
passes it to `try_map`, `custom` or `decode.failure` instead of asking its
caller for one. It need not be valid input and is not a default value: never
encode it as data.

```gleam
// Before: the wrapper invents a value of a type it does not own, or takes
// one from its caller.
pub fn receipt_codec(output: Codec(o)) -> Codec(Receipt(o)) {
  codec.custom(.., placeholder: Receipt("", Refusal(""), None))
}

// After: derive it from the codec being wrapped.
pub fn non_empty(inner: Codec(List(a))) -> Codec(List(a)) {
  codec.try_map(
    inner,
    decode: fn(items) {
      case items {
        [] -> Error("expected at least one item")
        _ -> Ok(items)
      }
    },
    encode: Ok,
    placeholder: codec.placeholder(inner),
  )
}
```

Dependents that can adopt it: `fabric/src/fabric/graph/llm.gleam` lines 141,
164, 207 and 294, which build a `Receipt` or `Refusal` placeholder by hand
around the application's output codec.

### Version

`gleam.toml` still says `1.7.1`. The CHANGELOG convention keeps the manifest
version until a release decision (`## Unreleased — intended 2.0`), so wave 3
does not bump it; bump it to `2.0.0` when publishing.
