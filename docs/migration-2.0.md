# Planned 2.0 source migration

This guide compares the published 1.7.1 source with the intended 2.0 source. The 1.7.1 tag contains `json/blueprint`, `json/blueprint/dynamic`, and `json/blueprint/schema`; the `codec`, `codegen`, `value`, `number`, `parser`, and `migration` modules were developed later on the implementation branch.

Blueprint 2.0 keeps the released `json/blueprint.Decoder` and `json/blueprint/schema` implementation for recursive typed decoding and its existing schema output. The legacy renderer labels output as Draft-07 and currently uses `$defs`; this guide does not assert strict dialect interoperability. For ordinary application data, `json/blueprint/codec.Codec(a)` is the canonical bidirectional definition: one codec provides value and JSON-text encoding, decoding, and a known Draft 2020-12 schema. The package manifest remains at 1.7.1 until the 2.0 release decision; this guide describes the intended source changes and does not announce a publication.

| 1.x source                                                         | 2.0 source or decision                                                                                                                                                                                                                                       |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `blueprint.decode2` / `decode3` with `blueprint.field`             | `codec.record2` / `record3` with `codec.required`, a constructor, and field accessors. For larger records, use `codec.combine`, `codec.object`, and `codec.imap`.                                                                                            |
| `blueprint.optional(inner)` for a present `null`                   | `codec.nullable(inner)` yields `codec.Null` or `codec.NonNull(value)`.                                                                                                                                                                                       |
| `blueprint.optional_field(name, inner)` for absent or `null`       | `codec.optional(name, codec.nullable(inner))` keeps absence (`codec.Missing`) distinct from present `null` (`codec.Present(codec.Null)`). Flatten explicitly only when the application intentionally treats both alike.                                      |
| `blueprint.union_type_decoder` with `blueprint.union_type_encoder` | `codec.tagged` works for a two-case union but uses `{"tag": ..., "value": ...}`. The released union utilities retain their `{"type": ..., "data": ...}` envelope; retain them or write explicit custom encode/decode when that wire format must stay stable. |
| `blueprint.self_decoder` and `blueprint.reuse_decoder`             | Keep the released decoder. Modern `codec.Schema` has no recursive `$ref` constructor and cannot represent the same finite recursive schema. The compiled [recursive example](../test/examples/recursive_types_test.gleam) covers nested trees and `$defs`.   |
| `json/blueprint/schema` legacy AST and constraints                 | Keep this module for refs, `pattern`, `format`, `multipleOf`, and other constraints outside the modern codec's finite Draft 2020-12 profile. Its schema output and behavior remain distinct from `codec.schema_json`.                                        |

The new `json/blueprint/value` module models JSON values without native-number rounding and rejects duplicate object keys when constructed through `value.object(entries, value.RejectDuplicates)`. Its short constructors (`value.null()`, `value.bool(x)`, `value.string(x)`, `value.number(x)`, and `value.array(xs)`) and its variants are all new in 2.0; they are not 1.x compatibility aliases. `json_text.render_value(value)` renders a value to JSON text.

The new codec text path uses Blueprint's bounded strict parser by default, including generated codecs. Duplicate keys are rejected and exact number tokens are retained. `codec.decode_json_native(generated_codec, text)` and generated `decode_<name>_json_native(text)` explicitly opt into the native `gleam/json` parser, which may collapse duplicate keys or normalize numbers. For callers that used the 1.x `blueprint.decode` parser, review inputs that depended on native parsing behavior before switching to `codec.decode_json`. The strict parser's default limits are 10 MiB, depth 128, 1024 number-token bytes, 800 significant digits, and absolute exponent 1200. Use `parser.default_limits()`, `parser_limits.with_max_bytes`, `parser_limits.with_max_depth`, or `parser_limits.with_number_limits` with `codec.decode_json_with_limits` when a tighter policy is needed. JavaScript native integers remain limited to the safe integer range; Erlang bignums are supported by bounded integer codecs when within the declared range.

No `json/blueprint/migration` adapter was published in 1.7.1. Intermediate implementation-branch snapshots had `migration.adapt` and `migration.value_to_json_string`; both were removed before the intended 2.0 release. If an application used those snapshots, replace `migration.adapt` with a direct `Codec` definition (or retain the legacy `Decoder` for recursion) and replace `migration.value_to_json_string` with `json_text.render_value`. The adapter reparsed JSON text through a legacy decoder, discarded located decode errors, and returned `UnknownSchema`; preserving it would imply a schema contract it could not provide. Intermediate generated decoders also changed from native to strict admission; regenerate checked-in source with the current `codegen.compile` implementation.

A migrated two-field record has one codec and a known schema. This is compiled in [test/migration_test.gleam](../test/migration_test.gleam):

```gleam
pub type Person {
  Person(name: String, age: Int)
}

pub fn person_codec() -> codec.Codec(Person) {
  let assert Ok(person) =
    codec.record2(
      codec.required("name", codec.string()),
      codec.required("age", codec.int()),
      Person,
      fn(person) { person.name },
      fn(person) { person.age },
    )
  person
}
```

Object acceptance changes during this migration: the released decoder ignored unrelated object fields, while `codec.object` and `codec.record2` reject them. The compiled migration test checks both behaviors on the same JSON text. Review callers that rely on permissive decoding before switching their definitions. `codec.tagged` also changes the union envelope as shown above; changing a decoder does not by itself authorize a wire-format change.

For code generation, keep one `codegen.Definition(a)` and use it for `codegen.runtime` and `codegen.compile`. Generated modules rely on codec's low-level helper functions; application code normally uses the returned `Codec(a)` instead. Exact `Number` and `Value` semantics, bounded parser admission, and runtime validation contracts remain available as separate advanced capabilities.

The new `codec.optional_option` and `codegen.optional_option` bridge optional fields directly to standard `Option(a)` without removing `codec.Optional(a)`. For a nullable property, map missing to `None`, JSON `null` to `Some(codec.Null)`, and a value to `Some(codec.NonNull(value))`. `codec.try_imap` supports application-owned validation in both conversion directions while preserving the base schema and located codec errors.
