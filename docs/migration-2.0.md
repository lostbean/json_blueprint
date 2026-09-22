# Planned 2.0 source migration

Blueprint 2.0 keeps the released `json/blueprint.Decoder` and `json/blueprint/schema` implementation for recursive typed decoding and its existing schema output. The legacy renderer labels output as Draft-07 and currently uses `$defs`; this guide does not assert strict dialect interoperability. For ordinary application data, `json/blueprint/codec.Codec(a)` is the canonical bidirectional definition: one codec provides value and JSON-text encoding, decoding, and a known Draft 2020-12 schema. The package manifest remains at 1.7.1 until the 2.0 release decision; this guide describes the intended source changes and does not announce a publication.

| 1.x source | 2.0 source or decision |
| --- | --- |
| `blueprint.decode2` / `decode3` with `blueprint.field` | `codec.record2` / `record3` with `codec.required`, a constructor, and field accessors. For larger records, use `codec.combine`, `codec.object`, and `codec.imap`. |
| `blueprint.optional(inner)` for a present `null` | `codec.nullable(inner)` yields `codec.Null` or `codec.NonNull(value)`. |
| `blueprint.optional_field(name, inner)` for absent or `null` | `codec.optional(name, codec.nullable(inner))` keeps absence (`codec.Missing`) distinct from present `null` (`codec.Present(codec.Null)`). Flatten explicitly only when the application intentionally treats both alike. |
| `blueprint.union_type_decoder` with `blueprint.union_type_encoder` | `codec.tagged` works for a two-case union but uses `{"tag": ..., "value": ...}`. The released union utilities retain their `{"type": ..., "data": ...}` envelope; retain them or write explicit custom encode/decode when that wire format must stay stable. |
| `blueprint.self_decoder` and `blueprint.reuse_decoder` | Keep the released decoder. Modern `codec.Schema` has no recursive `$ref` constructor and cannot represent the same finite recursive schema. The compiled [recursive example](../test/examples/recursive_types_test.gleam) covers nested trees and `$defs`. |
| `json/blueprint/schema` legacy AST and constraints | Keep this module for refs, `pattern`, `format`, `multipleOf`, and other constraints outside the modern codec's finite Draft 2020-12 profile. Its schema output and behavior remain distinct from `codec.schema_json`. |
| `migration.adapt(legacy_decoder, encoder)` | Removed. It converted a `Value` to JSON text, reparsed it through the legacy decoder, collapsed decode errors, and returned `UnknownSchema`. Define a `Codec` directly for bidirectional data; retain `Decoder` directly when recursion or Draft-07 behavior is needed. |
| `migration.value_to_json_string(value)` | `json_text.render_value(value)`. |
| `value.null()`, `value.bool(x)`, `value.string(x)`, `value.number(x)`, `value.array(xs)` | These released one-line aliases remain supported. New code can use `value.Null`, `value.Bool(x)`, `value.String(x)`, `value.Number(x)`, `value.Array(xs)` directly. Keep `value.object(entries, value.RejectDuplicates)` when duplicate-key validation is required. |

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
