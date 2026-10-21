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

The published package is 1.7.1 and provides the frozen 1.x API in
`json/blueprint` and `json/blueprint/schema`:

```sh
gleam add json_blueprint@1.7.1
```

The 1.x decoder remains the choice for recursive types, which `self_decoder`
and `reuse_decoder` describe with `$ref` and `$defs`, and for existing wire
formats: unions use `{"type": ..., "data": ...}` and enums use `{"enum": ...}`.
Its examples are compiled and run in [`examples/test/legacy/`](examples/test/legacy/). The
renderer labels its schema Draft-07 although some keywords, such as `$defs`
and `prefixItems`, come from later drafts; check dialect support before passing
that output to a validator.

### Upgrading from 1.x

Code that only uses the 1.x combinators compiles unchanged. Three things
changed in the current checkout:

- `json/blueprint/dynamic` is internal. Import `gleam/dynamic/decode` instead.
- `Decoder` and `FieldDecoder` are opaque. Build them with the combinators
  instead of record syntax. `get_dynamic_decoder` returns
  `fn(Dynamic) -> Result(t, List(decode.DecodeError))` with the same
  `expected`, `found` and `path` fields.
- `blueprint.decode` rejects text above 1 MiB before parsing, with one
  `json.UnableToDecode` error that names the limit. `blueprint.decode_with_max_bytes`
  accepts a larger bound.

The same record in both APIs, with the wire differences that need review against
stored data, is compiled and run in
[`examples/test/migration_test.gleam`](examples/test/migration_test.gleam).

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

## Tagged unions

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

The JSON is `{"tag": "circle", "value": 2}`, and `{"tag": "empty"}` for a unit
variant. Gleam checks that the `case` covers every constructor.

## Examples

Every usage topic is real code in [`examples/`](examples/README.md), compiled and
run on Erlang and JavaScript by the package gate, so it cannot drift from the
library. `gleam run` there prints each example's result.

| Topic | Example |
| --- | --- |
| A record, both ways: encode, strict decode and schema | [`record`](examples/src/examples/record.gleam) |
| Optional, nullable and absent fields | [`optional_fields`](examples/src/examples/optional_fields.gleam) |
| Tagged unions | [`unions`](examples/src/examples/unions.gleam) |
| Application types and fields that depend on earlier fields | [`custom_types`](examples/src/examples/custom_types.gleam) |
| Errors and definition checks | [`errors`](examples/src/examples/errors.gleam) |
| `gleam/json` and other libraries | [`gleam_json_bridge`](examples/src/examples/gleam_json_bridge.gleam) |
| Larger inputs | [`larger_inputs`](examples/src/examples/larger_inputs.gleam) |
| Schemas that arrive at runtime | [`runtime_schema`](examples/src/examples/runtime_schema.gleam) |
| Reading a schema | [`schema_inspection`](examples/src/examples/schema_inspection.gleam) |
| Frozen 1.x API and the move to 2.0 | [`legacy` and `migration`](examples/test/legacy/) |
| Schema-driven code generation | [`codegen/consumer`](codegen/consumer/README.md) |

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
much more memory than their input text, and the limits bound admission rather
than heap size.

## Modules

| Module                                    | Use it for                                                                  |
| ----------------------------------------- | --------------------------------------------------------------------------- |
| `json/blueprint/codec`                    | codecs: the common path                                                     |
| `json/blueprint/value`                    | the JSON `Value`, the strict bounded parser, `Limits`, `gleam/json` bridges |
| `json/blueprint/number`                   | exact JSON numbers and checked `Int` and `Float` conversions                |
| `json/blueprint/contract`                 | schemas that arrive at runtime, and validation                              |
| `json/blueprint`, `json/blueprint/schema` | the frozen 1.x API; see [Upgrading from 1.x](#upgrading-from-1x)            |

[Code generation](codegen/README.md) is a separate, unpublished development
dependency.

## Targets

CI tests Erlang/OTP 29 and JavaScript on Node.js 24. On
JavaScript, native integers are limited to the safe range: `codec.int()`
refuses larger ones instead of rounding them, and `codec.number()` keeps them
exact. Browser JavaScript is not tested.

## Development

```sh
nix develop          # Gleam, Erlang/OTP, Node.js, Python with jsonschema
sh scripts/gate.sh   # compilation, both-target tests, examples and schema oracle
nix flake check     # shared formatting check
nix run .#design-gate-check -- docs/design .
nix fmt -- PATH...   # format named authored files
```

The [design](docs/design/design.typ) records ownership, behavior, limits and
verification. [Decision records](docs/adr/) explain the material choices, and
[coverage](docs/COVERAGE.md) maps source and verification to the design.

## References

- [Oracle](docs/ORACLE.md): the independent Draft 2020-12 validator and the frozen
  corpus the emitted schemas, decoders and contracts are compared against.
- [Benchmarks](docs/BENCHMARKS.md): method, provenance and retained local timing
  observations. They never gate a change.
