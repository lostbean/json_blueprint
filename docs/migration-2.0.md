# Moving from json_blueprint 1.x to 2.0

json_blueprint 2.0 keeps the 1.x API, frozen, in `json/blueprint` and
`json/blueprint/schema`, and adds `json/blueprint/codec`: one `Codec(a)` that
encodes, decodes strictly and describes a Draft 2020-12 schema. The [design layer](design/design.typ) records the current API contract and
[decision records](adr/) explain its material changes.

## What 1.x code must change

1.x code that only uses the combinators compiles unchanged. Three things
changed:

- **`json/blueprint/dynamic` is internal.** Replace its imports with
  `gleam/dynamic/decode`.
- **`Decoder` and `FieldDecoder` are opaque.** Build them with the
  combinators instead of record syntax. `get_dynamic_decoder` now returns
  `fn(Dynamic) -> Result(t, List(decode.DecodeError))`; the errors have the
  same `expected`, `found` and `path` fields.
- **`blueprint.decode` rejects text above 1 MiB** before parsing, with one
  `json.UnableToDecode` error that names the limit. Use
  `blueprint.decode_with_max_bytes` to accept larger text.

```gleam
// before
import json/blueprint/dynamic

blueprint.Decoder(dyn_decoder: dynamic.string, schema: schema, defs: [])

// after
blueprint.string()
```

## Moving a type to `Codec`

A codec gives both directions and a schema from one definition. This record
is compiled in [test/migration_test.gleam](../test/migration_test.gleam):

```gleam
// 1.x
pub fn person_decoder() -> blueprint.Decoder(Person) {
  blueprint.decode2(
    Person,
    blueprint.field("name", blueprint.string()),
    blueprint.field("age", blueprint.int()),
  )
}

// 2.0
pub fn person_codec() -> Codec(Person) {
  use name <- codec.field("name", codec.string(), get: fn(p) { p.name })
  use age <- codec.field("age", codec.int(), get: fn(p) { p.age })
  codec.success(Person(name:, age:))
}
```

| 1.x                                               | 2.0                                                        |
| ------------------------------------------------- | ---------------------------------------------------------- |
| `decode1` … `decode9` with `field`                | `codec.field` for each field, then `codec.success`         |
| `optional_field(name, inner)`                     | `codec.optional_field(name, inner, get: getter)`           |
| `optional(inner)` (a present `null`)              | `codec.nullable(inner)`                                    |
| `union_type_decoder` with `union_type_encoder`    | `codec.union` with `variant` and `unit_variant`            |
| `enum_type_decoder` with `enum_type_encoder`      | `codec.string_enum`                                        |
| `tuple2` … `tuple6`                               | `codec.pair`, or a record                                  |
| `map`                                             | `codec.map(codec, decode:, encode:)`                       |
| `float()`                                         | `codec.float()`, or `codec.number()` to keep numbers exact |
| `self_decoder`, `reuse_decoder` (recursive types) | keep the 1.x decoder: codec schemas have no `$ref`         |
| `generate_json_schema` (Draft-07 label)           | `codec.schema_json` (Draft 2020-12)                        |
| `blueprint.decode` (gleam/json, 1 MiB check)      | `codec.decode_json` (strict parser, bounded)               |

Each item below changes what the wire accepts or produces. Review it against
stored data before moving a type:

- **Objects are closed.** An unknown field fails to decode; 1.x ignored it.
- **`optional_field` rejects `null`.** 1.x treated an absent field and `null`
  alike. Use `codec.optional_field(name, codec.nullable(inner), ..)` to accept
  both; absent and `null` then decode as `None` and `Some(None)`.
- **Unions use `{"tag": ..., "value": ...}`.** 1.x wrote
  `{"type": ..., "data": ...}`. Data stored in the 1.x form stays readable
  with the 1.x decoder; there is no codec for that envelope.
- **Enums encode a bare label.** 1.x `enum_type_encoder` wrote
  `{"enum": label}`.
- **Duplicate keys fail, and numbers are exact.** `codec.int()` accepts an
  exact integer spelling such as `1.0e2` and refuses a fraction.
- **Limits.** `codec.decode_json` stops at 1 MiB, depth 64 and 262,144
  values; see the README defaults table.

Changing a decoder does not by itself authorize a wire-format change: keep
the 1.x decoder for data that must stay in its format.
