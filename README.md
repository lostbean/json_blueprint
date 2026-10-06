# json_blueprint

Define a JSON codec in Gleam to encode native values, decode JSON strictly, and
publish a Draft 2020-12 schema from the same definition.

[![Package Version](https://img.shields.io/hexpm/v/json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/json_blueprint/)

## Installation

The codec API shown below is unreleased work toward 2.0. To use it from a
sibling application, add this checkout to the application's `gleam.toml`:

```toml
[dependencies]
json_blueprint = { path = "../json_blueprint" }
```

The published package is 1.7.1 and provides the [1.x API](docs/v1.md):

```sh
gleam add json_blueprint@1.7.1
```

The [migration guide](docs/migration-2.0.md) explains the source and wire-format
changes in the current checkout.

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
  use name <- codec.field("name", codec.string(), get: fn(u) { u.name })
  use age <- codec.field("age", codec.integer_between(0, 150), get: fn(u) {
    u.age
  })
  use email <- codec.optional_field("email", codec.string(), get: fn(u) {
    u.email
  })
  use role <- codec.field("role", role, get: fn(u) { u.role })
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
  one; `codec.success` builds the record from the decoded fields. Pass each
  getter with its `get:` label; it needs no type annotation, because the
  rest of the block, which ends in `success`, fixes the record type first.
- Decoding is strict: unknown fields, duplicate keys and wrong types fail,
  with the path to the failure, such as
  `$["age"]: integer outside range 0 to 150`.
- `schema_json` renders the Draft 2020-12 schema: closed objects, the
  `required` list, the enum labels and the integer bounds.

These built-in operations are synchronous and keep no process or connection
to close. Custom callbacks own their effects.

## Defaults

| Operation                                                           | Default                                                             | Change it with                                                                             |
| ------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Text size: `codec.decode_json`, `value.parse`, `contract.parse`     | 1 MiB (1,048,576 bytes of UTF-8)                                    | `value.with_max_bytes`, passed to `codec.decode_json_with_limits` or the parsers           |
| Array and object nesting                                            | depth 64                                                            | `value.with_max_depth`                                                                     |
| Values in one document (each scalar, array, and object counts once) | 262,144                                                             | `value.with_max_elements`                                                                  |
| Number token bytes, significant digits, exponent magnitude          | 1,024, 800, 1,200                                                   | `value.with_number_limits(number.limits(..))`                                              |
| `codec.int()` decoding                                              | at most 24 digits; on JavaScript also within ±9,007,199,254,740,991 | fixed; use `codec.number()` for larger values                                              |
| `codec.decoder` (for `gleam/json`)                                  | supplied by the parser that produced the data                       | that parser                                                                                |
| 1.x `blueprint.decode` in this checkout                             | 1 MiB before `gleam/json` parses; no depth, value, or number limit  | `blueprint.decode_with_max_bytes`                                                          |
| Generated `decode_<name>_json_native`                               | 1 MiB before `gleam/json` parses; no depth, value, or number limit  | fixed                                                                                      |
| `contract.validate`, `contract.load`                                | no independent resource limit                                       | parse with explicit limits before calling; manually constructed values have no parse bound |
| Duplicate object keys in strict text parsing                        | rejected                                                            | not configurable                                                                           |
| Undeclared record fields                                            | rejected by built-in record codecs and closed contracts             | declare the field in the definition                                                        |

A parse error names the setter of the limit it hit, and
`codec.is_limit_exceeded` tells a too-large input from an invalid one.

Raising the byte limit does not raise the value limit. Parsed values can use
much more memory than their input text; [historical memory observations](docs/benchmarks.md#historical-memory-observations)
record the measured costs and their limits.

## Modules

| Module                                    | Use it for                                                                  |
| ----------------------------------------- | --------------------------------------------------------------------------- |
| `json/blueprint/codec`                    | codecs: the common path                                                     |
| `json/blueprint/value`                    | the JSON `Value`, the strict bounded parser, `Limits`, `gleam/json` bridges |
| `json/blueprint/number`                   | exact JSON numbers and checked `Int` and `Float` conversions                |
| `json/blueprint/contract`                 | schemas that arrive at runtime, and validation                              |
| `json/blueprint`, `json/blueprint/schema` | the frozen 1.x API; see [the 1.x guide](docs/v1.md)                         |

[Code generation](codegen/README.md) is a separate, unpublished development
dependency. The [1.x guide](docs/v1.md) covers recursive decoders and existing
wire formats; the [migration guide](docs/migration-2.0.md) explains moving to
the codec API.

## Targets

CI tests Erlang/OTP 28 and JavaScript on Node.js 24. On
JavaScript, native integers are limited to the safe range: `codec.int()`
refuses larger ones instead of rounding them, and `codec.number()` keeps them
exact. Browser JavaScript is not tested.

## Benchmarks

The retained 2026-09-20 run measured document parsing at 9,847 ns/op on
Erlang/OTP 28 and 41,057 ns/op on Node.js 24.15.0, with 200 warmup calls and
1,000 timed calls per workload. These are historical measurements. See the
[benchmark results and commands](docs/benchmarks.md) for workloads, evidence,
aggregation, and missing machine provenance.

## Development

```sh
nix develop          # Gleam 1.18.1, Erlang/OTP 28, Node.js 24, Python + jsonschema
sh scripts/gate.sh   # format, warnings, both-target tests and the schema oracle
```

`test/schema_check.py` compares the emitted schemas with the Python
`jsonschema` Draft 2020-12 validator; it needs `jsonschema` 4.26 or later,
provided by the dev shell and installed by CI. The gate runs it after both
packages pass their Erlang and JavaScript checks.

## Design

The [design layer](docs/design/design.typ) records ownership, behavior, limits,
legacy compatibility, and retained capability scope. The [rendered design](docs/design/design-layer.pdf)
includes its [canonical vocabulary](docs/design/CONTEXT.typ).
[Decision records](docs/adr/) explain the material choices, and
[coverage](docs/COVERAGE.md) maps source and verification to the design.

## More examples

Expand the examples below for [unions](#unions),
[application types and dependent fields](#your-own-types), [errors](#errors),
[gleam/json bridges](#gleamjson-and-other-libraries), [larger inputs](#larger-inputs),
[runtime schemas](#schemas-that-arrive-at-runtime), and [schema inspection](#reading-a-schema).

<details>
<summary>Optional, nullable and absent</summary>

## Optional, nullable and absent

`optional_field` omits the field for `None` and decodes an absent field as
`None`; JSON `null` fails. `codec.nullable(c)` accepts `null` as `None`. With
`optional_field(name, codec.nullable(c), ..)`, an absent field, `null` and a
value decode as `None`, `Some(None)` and `Some(Some(x))`, and encode back the
same way.

</details>

<details>
<summary>Tagged unions</summary>

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

</details>

<details>
<summary>Application types and dependent fields</summary>

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

A failed conversion is the reason `Custom(message)` at the codec's path, and
`describe_decode_error` renders it as `$: an email address needs an @`.

A generic wrapper over a codec it did not build takes the placeholder from
it: `codec.placeholder(inner)` returns the value `inner` describes itself
with, such as `""` for `codec.string()` or the first variant of a union. It
need not be valid input, so never encode it as data.

A `try_map` over a whole record fails at the record's own path, `[]` at the
root. To report a check across fields at the field it concerns, build that
field's codec inside the record from the fields decoded before it:

```gleam
pub type Order {
  Order(items: List(Int), total: Int)
}

pub fn order_codec() -> Codec(Order) {
  use items <- codec.field("items", codec.list(codec.int()), get: fn(o) {
    o.items
  })
  use total <- codec.field("total", total_of(items), get: fn(o) { o.total })
  codec.success(Order(items:, total:))
}

fn total_of(items: List(Int)) -> Codec(Int) {
  let sum = int.sum(items)
  let check = fn(total) {
    case total == sum {
      True -> Ok(total)
      False ->
        Error(
          "total "
          <> int.to_string(total)
          <> " differs from the item sum "
          <> int.to_string(sum),
        )
    }
  }
  codec.try_map(codec.int(), decode: check, encode: check, placeholder: sum)
}
```

Decoding `{"items":[1,2],"total":4}` fails with
`$["total"]: total 4 differs from the item sum 3`, and encoding such an
`Order` fails at the same path. When the codec describes itself, `total_of`
receives placeholder values, so its schema must not depend on them.

The other building blocks are `string`, `int`, `float`, `number` (exact), `bool`,
`list`, `pair`, `string_enum`, `integer_between`, `number_between` and
`describe`, which adds a schema description.

</details>

<details>
<summary>Error handling and definition checks</summary>

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

The library writes the path and the text of its own reasons, which never
contain input values or unknown keys from the input. A `Custom` reason
renders the caller's message verbatim, so leave input values out of a
message that must not show them. `Reason` may gain variants in minor
releases, so match it with a `_` branch.

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

</details>

<details>
<summary>gleam/json bridges</summary>

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

</details>

<details>
<summary>Larger inputs</summary>

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

</details>

<details>
<summary>Runtime schema documents</summary>

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
validated value with a codec whose schema matches. `codec.value()` passes
any JSON through as a `Value`, for a value the application forwards as it
came, such as a tool result from a remote peer; its schema is `{}`, which
accepts every value.

The profile covers closed objects with required and optional properties,
pairs, lists, nullable values, bounded integers and numbers, string enums,
tagged unions and any value (`{}`, or `true` in a loaded document).
Recursive references (`$ref`), untagged unions and string patterns are
outside it.

</details>

<details>
<summary>Schema inspection and evolution</summary>

## Reading a schema

`codec.schema` returns an opaque `Schema`. `schema_value` and
`schema_document` render it; code that translates schemas, such as a tool
server or an LLM provider adapter, reads it with `codec.view`, which gives
the kind at the root, and `codec.description`:

```gleam
/// Whether a tool's input schema has an object root, as MCP requires.
pub fn object_root(input: Codec(a)) -> Bool {
  case codec.schema(input) {
    Error(codec.UnknownSchema) -> False
    Ok(schema) ->
      case codec.view(schema) {
        codec.ObjectSchema(_) | codec.UnionSchema(_) -> True
        _ -> False
      }
  }
}
```

The children of a view, such as `ListSchema(items)` or a property's
`schema`, are `Schema` values to `view` in turn. A description is not a
kind: `view` looks through it and `description` reads it.

**Evolution policy.** The variants of `SchemaView` are fixed for every 2.x
release: `StringSchema`, `StringEnumSchema`, `IntSchema`,
`IntegerRangeSchema`, `NumberSchema`, `NumberRangeSchema`, `BoolSchema`,
`PairSchema`, `ListSchema`, `NullableSchema`, `ObjectSchema`, `UnionSchema`,
`AnySchema` and `OtherSchema`. A schema kind added in a minor release reaches
`view` as `OtherSchema(document)`, with the kind's JSON Schema object, so
code written against 2.0 keeps compiling and decides in that branch whether
to forward the document or refuse the schema; a minor release may add a
function that reads the new kind. A dedicated variant for it is a breaking
change and waits for a major release. `PropertySchema` and `VariantSchema`
may gain fields; read them by label.

</details>
