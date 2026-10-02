# json_blueprint

Describe a JSON shape once in Gleam, and get an encoder, a strict decoder and
a JSON Schema (Draft 2020-12) from the same definition.

[![Package Version](https://img.shields.io/hexpm/v/json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/json_blueprint/)

```sh
gleam add json_blueprint
```

## A record, both ways

```gleam
import gleam/option.{type Option}
import gleam/result
import json/blueprint/codec.{type Codec}

pub type Role {
  Admin
  Member
}

pub type User {
  User(name: String, age: Int, email: Option(String), role: Role)
}

pub fn user_codec() -> Codec(User) {
  let role = codec.string_enum([#("admin", Admin), #("member", Member)])
  use name <- codec.field("name", codec.string(), fn(u: User) { u.name })
  use age <- codec.field("age", codec.integer_between(0, 150), fn(u: User) {
    u.age
  })
  use email <- codec.optional_field("email", codec.string(), fn(u: User) {
    u.email
  })
  use role <- codec.field("role", role, fn(u: User) { u.role })
  codec.success(User(name:, age:, email:, role:))
}

pub fn round_trip() -> Result(User, String) {
  let text = "{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}"
  use user <- result.try(
    codec.decode_json(user_codec(), text)
    |> result.map_error(codec.describe_decode_error),
  )
  let assert Ok(_text) = codec.encode_json(user_codec(), user)
  let assert Ok(_schema) = codec.schema_json(user_codec())
  Ok(user)
}
```

- `codec.field` adds a required field and `codec.optional_field` an optional
  one; `codec.success` builds the record from the decoded fields. Each getter
  needs its record type annotated (`fn(u: User)`).
- Decoding is strict: unknown fields, duplicate keys and wrong types fail,
  with the path to the failure, such as
  `$["age"]: integer outside range 0 to 150`.
- `schema_json` renders the Draft 2020-12 schema: closed objects, the
  `required` list, the enum labels and the integer bounds.

Every function here is pure: none blocks, waits, retries or starts a process.

## Defaults

| Operation                                                           | Default                                                                     | Change it with                                                                   |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Text size: `codec.decode_json`, `value.parse`, `contract.parse`     | 1 MiB (1,048,576 bytes of UTF-8)                                            | `value.with_max_bytes`, passed to `codec.decode_json_with_limits` or the parsers |
| Array and object nesting                                            | depth 64                                                                    | `value.with_max_depth`                                                           |
| Values in one document (every scalar, array and object counts once) | 262,144: one per 4 bytes of the byte limit                                  | `value.with_max_elements`                                                        |
| Number tokens: bytes, significant digits, exponent magnitude        | 1,024, 800, 1,200                                                           | `value.with_number_limits(number.limits(..))`                                    |
| `codec.int()` decoding                                              | at most 24 digits; on JavaScript also within ±9,007,199,254,740,991         | fixed; use `codec.number()` for larger values                                    |
| `codec.decoder` (for `gleam/json`)                                  | none of its own: the parser that produced the data sets the limits          | that parser                                                                      |
| 1.x `blueprint.decode`, generated `decode_<name>_json_native`       | 1 MiB, checked before `gleam/json` parses; no depth, value or number limits | `blueprint.decode_with_max_bytes`                                                |
| `contract.validate`, `contract.load`                                | no separate limit: they walk a value that a bounded parse produced          | the parse limits                                                                 |
| Duplicate object keys and unknown object fields                     | rejected                                                                    | not configurable                                                                 |

A parse error names the setter of the limit it hit, and
`codec.is_limit_exceeded` tells a too-large input from an invalid one.

Parsed values take more memory than their text. The table lists the peak
process heap during `value.parse` at the defaults on Erlang/OTP 28, measured
from garbage-collection events with the old and new heap counted together,
and the heap growth on Node.js 24:

| Input at the defaults                          | Text    | Peak heap, OTP 28 | Parsed value, OTP 28 | Heap growth, Node.js 24 |
| ---------------------------------------------- | ------- | ----------------- | -------------------- | ----------------------- |
| `[1,1,...]`: 262,143 integers, the value limit | 512 KiB | 42 MB             | 16 MB                | about 120 MB            |
| `["a","a",...]`: 262,143 strings               | 1 MiB   | 40 MB             | 16 MB                | about 75 MB             |
| `[{"k":1},...]`: 87,001 objects                | 680 KiB | 32 MB             | 13 MB                | about 75 MB             |
| 61,001 fifteen-digit decimals                  | 1 MiB   | 16 MB             | 6 MB                 | about 80 MB             |

The value limit bounds the densest input: with it raised, 1 MiB of
`[1,1,...]` (524,288 integers) peaks at 80 MB by the same measure. Raise the
byte limit with these figures in mind.

## Optional, nullable and absent

`optional_field` omits the field for `None` and decodes an absent field as
`None`; JSON `null` fails. `codec.nullable(c)` accepts `null` as `None`. With
`optional_field(name, codec.nullable(c), ..)`, an absent field, `null` and a
value decode as `None`, `Some(None)` and `Some(Some(x))`, and encode back the
same way.

## Unions

```gleam
pub type Shape {
  Circle(radius: Int)
  Label(text: String)
  Empty
}

pub fn shape_codec() -> Codec(Shape) {
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
```

The JSON is `{"tag": "circle", "value": 2}`, and `{"tag": "empty"}` for a
unit variant. Gleam checks that the `case` covers every constructor.

## Your own types

`codec.map` converts with total functions, `codec.try_map` with functions
that may fail, and `codec.custom` builds a codec from functions over `Value`.
`try_map` and `custom` take a placeholder: any value of the type, used where a
value is needed without input, as `decode.failure` does.

```gleam
pub type Email {
  Email(address: String)
}

pub fn email_codec() -> Codec(Email) {
  codec.try_map(
    codec.string(),
    decode: fn(text) {
      case string.contains(text, "@") {
        True -> Ok(Email(text))
        False -> Error("an email address needs an @")
      }
    },
    encode: fn(email: Email) { Ok(email.address) },
    placeholder: Email(""),
  )
}
```

A failed conversion is the reason `Custom(message)` at the codec's path. The
other building blocks are `string`, `int`, `float`, `number` (exact), `bool`,
`list`, `pair`, `string_enum`, `integer_between`, `number_between` and
`describe`, which adds a schema description.

## Errors

`DecodeError` and `EncodeError` are `{path, reason}` records. Branch on the
reason, or render the error:

```gleam
pub fn explain(text: String) -> String {
  case codec.decode_json(user_codec(), text) {
    Ok(_) -> "ok"
    Error(error) ->
      case codec.is_limit_exceeded(error) {
        True -> "the request is too large"
        False -> codec.describe_decode_error(error)
      }
  }
}
```

The rendered text never contains input values, unknown keys from the input
or `Custom` messages. `Reason` may gain variants in minor releases, so match
it with a `_` branch.

A codec written wrongly, such as a field named twice, an enum label repeated
or reversed bounds, panics with a message naming the field, label or bounds
when that part is first used. For a definition built from runtime data, call
`codec.check` to get the mistake as a `DefinitionError` instead:

```gleam
pub fn status_codec(
  labels: List(String),
) -> Result(Codec(String), codec.DefinitionError) {
  codec.string_enum(list.map(labels, fn(label) { #(label, label) }))
  |> codec.check
}
```

## gleam/json and other libraries

`codec.to_json` returns a `json.Json` and `codec.decoder` a
`decode.Decoder`, so the same codec serves libraries that speak `gleam/json`:

```gleam
pub fn with_gleam_json(user: User) -> Result(User, json.DecodeError) {
  let assert Ok(encoded) = codec.to_json(user_codec(), user)
  json.parse(json.to_string(encoded), codec.decoder(user_codec()))
}
```

`to_json` is exact: a number without an exact `gleam/json` form, such as
`1e400` in a `codec.number()`, fails with `UnrepresentableNumber`. With
`decoder`, the parser that produced the data owns duplicate keys, number
precision and size limits.

## Larger inputs

```gleam
pub fn decode_many(text: String) -> Result(List(User), codec.DecodeError) {
  let limits =
    value.default_limits()
    |> value.with_max_bytes(8 * 1024 * 1024)
    |> value.with_max_elements(2_000_000)
  codec.decode_json_with_limits(codec.list(user_codec()), text, limits)
}
```

## Schemas that arrive at runtime

`json/blueprint/contract` accepts a Draft 2020-12 schema document inside the
profile that codecs describe, such as a tool's input schema from a remote
server, and validates values against it:

```gleam
pub fn check_arguments(
  schema_text: String,
  arguments: String,
) -> Result(value.Value, String) {
  let limits = value.default_limits()
  use remote <- result.try(
    contract.parse(schema_text, limits)
    |> result.map_error(contract.describe_load_error),
  )
  use parsed <- result.try(
    value.parse(arguments, limits)
    |> result.map_error(value.describe_parse_error),
  )
  contract.validate(remote, parsed)
  |> result.map(contract.value)
  |> result.map_error(contract.describe_validation_error)
}
```

`contract.value_codec(contract)` is a `Codec(Value)` with the contract's
schema that validates while decoding, and `contract.decode` decodes a
validated value with a codec whose schema matches.

The profile covers closed objects with required and optional properties,
pairs, lists, nullable values, bounded integers and numbers, string enums and
tagged unions. Recursive references (`$ref`), untagged unions and string
patterns are outside it.

## Modules

| Module                                    | Use it for                                                                  |
| ----------------------------------------- | --------------------------------------------------------------------------- |
| `json/blueprint/codec`                    | codecs: the common path                                                     |
| `json/blueprint/value`                    | the JSON `Value`, the strict bounded parser, `Limits`, `gleam/json` bridges |
| `json/blueprint/number`                   | exact JSON numbers and checked `Int` and `Float` conversions                |
| `json/blueprint/contract`                 | schemas that arrive at runtime, and validation                              |
| `json/blueprint`, `json/blueprint/schema` | the frozen 1.x API; see [the 1.x guide](docs/v1.md)                         |

Code generation is a separate dev-only package in
[`codegen/`](codegen/README.md). Moving from 1.x is described in
[the 2.0 migration guide](docs/migration-2.0.md).

## Targets

Erlang/OTP 28 and JavaScript on Node.js 24 are tested on every change. On
JavaScript, native integers are limited to the safe range: `codec.int()`
refuses larger ones instead of rounding them, and `codec.number()` keeps them
exact. Browser JavaScript is not tested.

## Development

```sh
nix develop          # Gleam 1.17, Erlang/OTP 28, Node.js 24
sh scripts/gate.sh   # format, warnings and tests on both targets, for both packages
```
