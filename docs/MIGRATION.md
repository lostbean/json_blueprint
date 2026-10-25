# Migrating JSON Blueprint from 1.7.1 to 2.0

JSON Blueprint 2.0 includes the legacy decoder and schema modules alongside
typed codecs, exact JSON values, finite runtime contracts, and source generators.
Upgrading the package can retain your legacy wire format. Moving an application
to codecs requires a separate review of its accepted and emitted JSON.

This guide compares published 1.7.1 with the 2.0.0 checkout. It does not claim
complete equivalence for every legacy schema, error path, or numeric boundary.

## Update the dependency

Until 2.0.0 is published to Hex, use a Git or local path dependency on this
checkout. Keep the resolved Git commit in `manifest.toml`. After publication,
update the application with:

```sh
gleam add json_blueprint@2
gleam build --warnings-as-errors
gleam test
```

Run every target your application supports. Update each independently resolved
example, adapter, and consumer through Gleam as well. Do not replace a historical
oracle dependency merely to make it match the application dependency.

## Keep the legacy API first

The `json/blueprint` combinators and `json/blueprint/schema` remain available.
Existing legacy union, enum, optional, tuple, and recursive forms can stay on
that API while you review a codec migration. Address these package-upgrade
changes before changing the application's wire format:

| Change in 2.0                                                          | Application action                                                                                                                                                                                                                                                      |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Decoder` and `FieldDecoder` are opaque                                | Replace constructor calls, pattern matches, and field access with supported combinators and accessors. Use `get_dynamic_decoder` to obtain the decoding function and `generate_json_schema` to render a decoder's schema.                                               |
| `json/blueprint/dynamic` has been removed from the public module paths | Move dynamic decoding and error types to `gleam/dynamic/decode`. Its API is not a mechanical module-name replacement for every old helper.                                                                                                                              |
| `get_dynamic_decoder` returns standard-library decode errors           | Update error annotations and constructor matches to `gleam/dynamic/decode.DecodeError`. The fields remain `expected`, `found`, and `path`. The return value is still `fn(Dynamic) -> Result(t, List(decode.DecodeError))`, rather than a standard-library `Decoder(t)`. |
| `blueprint.decode` has a UTF-8 byte precheck                           | Text above 1,048,576 bytes returns `json.UnableToDecode` before native parsing. Use `blueprint.decode_with_max_bytes(using:, from:, max_bytes:)` with an application-selected bound for larger inputs.                                                                  |

Custom code that constructed raw decoder records may need redesign. There is
no promised one-for-one replacement for those constructors. Prefer a supported
composition of legacy combinators, or review a codec conversion for that boundary.

The legacy path continues to use `gleam/json` for parsing. Raising its byte
bound does not add strict duplicate-key, nesting, value-count, or exact-number
guarantees. Keep `self_decoder` and `reuse_decoder` for recursive types; the
finite codec and runtime-contract profile does not support recursive schemas.

Applications feeding JavaScript objects directly to a Dynamic decoder should
also replay their object-lookup fixtures. Lookup now handles Gleam Dicts,
Maps, WeakMaps, null-prototype objects, and present `undefined` entries more
consistently. These corrections affect direct Dynamic input; the retained
legacy JSON union and enum encoders keep their wire forms.

## Adopt codecs one boundary at a time

A `codec.Codec(a)` describes both native conversion directions and a schema.
Build it with public constructors, use `codec.field` or `codec.optional_field`
with a native getter for each record member, and finish the record with
`codec.success`. Use `codec.decode_json`, `codec.encode_json`, and
`codec.schema_json` at the boundary.

The [compiled migration example](https://github.com/lostbean/json_blueprint/blob/main/examples/test/migration_test.gleam)
converts one legacy `Decoder(Person)` to a `Codec(Person)` and checks both
implementations. It also exercises these intentional differences:

| Boundary                   | Retained legacy API                                                                 | Codec API                                                                                                                       |
| -------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Record members             | Nonempty record decoders ignore unknown members                                     | Built-in record codecs reject unknown members                                                                                   |
| Optional string property   | Missing and `null` both decode to `None`                                            | A plain `optional_field` accepts absence and rejects `null`                                                                     |
| Nullable optional property | Absence and `null` may collapse                                                     | `optional_field` containing `nullable` represents absence, `null`, and a value as `None`, `Some(None)`, and `Some(Some(value))` |
| Payload union              | The encoder emits `{"type":"circle","data":{"radius":2}}` for the example's payload | Its codec emits `{"tag":"circle","value":2}`                                                                                    |
| Enum                       | The encoder emits `{"enum":"high"}`                                                 | A string-enum codec emits `"high"`                                                                                              |

Capture representative stored values and protocol messages before changing a
boundary. Include missing, null, extra, malformed, and recursive cases. Check
both decoding and emitted JSON against those fixtures. If stored data or peers
still use the old form, retain a legacy reader or implement an explicit
application migration before switching writers. There is no automatic conversion
between arbitrary legacy decoders and codecs.

The [optional-field example](https://github.com/lostbean/json_blueprint/blob/main/examples/src/examples/optional_fields.gleam)
shows the three-state representation and its encoding behavior.

## Review parser and number policy

`codec.decode_json` uses the strict `Value` parser. Its defaults are 1 MiB of
UTF-8, depth 64, 262,144 values, and number limits of 1,024 token bytes, 800
significant digits, and exponent magnitude 1,200. It rejects repeated object
keys. Use `codec.decode_json_with_limits` with the `value.with_*` functions
when the application needs different bounds; increasing bytes alone does not
increase the other limits.

`codec.int()` supports at most 24 digits and requires safe integers on
JavaScript. Use `codec.number()` and the exact `Number` operations for values
that must retain mathematical JSON precision. Treat projection into native
`Int` or `Float` as a separate operation that can fail or round. Use
`codec.float()` when binary floating-point conversion is acceptable. The
`gleam/json` and standard dynamic-decoder bridges retain their native parser
and number behavior; they do not inherit strict text-admission guarantees.

See the [larger-input example](https://github.com/lostbean/json_blueprint/blob/main/examples/src/examples/larger_inputs.gleam)
for explicit limits. Run large-number fixtures on each intended target.

## Review schemas and runtime contracts

Legacy schema rendering remains in `json/blueprint/schema`. Its declared
Draft-07 label does not prove that every emitted keyword belongs to that dialect
or that the decoder enforces every described constraint. Keep schema snapshots
when retaining that API.

Modern codecs render Draft 2020-12 schemas through an opaque `codec.Schema`.
Use `codec.view` and its opaque children to inspect a schema. Runtime contracts
admit only the finite profile of supported shapes; a broader legacy description
cannot be passed through as an equivalent contract. References, recursive
definitions, and other unsupported forms are refused. Review provider-specific
schema restrictions in the application as well.

`contract.parse` loads schema text with explicit admission limits, and
`contract.validate` checks a `Value`. Decoding a validated value requires a
codec with the same normalized schema. These checks do not certify custom
callback behavior or application authorization. The
[oracle documentation](https://github.com/lostbean/json_blueprint/blob/main/docs/ORACLE.md)
states the supported profile and the limits of its independent evidence.

## Keep generation in the build

The package now includes `json/blueprint/codegen` and
`json/blueprint/codegen/schema`. The separate `json_blueprint_codegen` package
was an unpublished checkout package; remove that dependency if you used it.
Keep the same generator imports and depend on `json_blueprint` alone.

Generation returns source. Your build task writes, formats, compiles, and reviews
that source for each target. Regenerate checked-in modules with the 2.0
generator, review the diff, and rerun parity and application tests before
committing the output. The schema generator's attribution header now names
JSON Blueprint. Do not edit generator output by hand to make a drift check pass.

Schema-driven generation supports a narrower closed-object subset than runtime
contracts. Admitting a schema as a contract does not guarantee generation support.

The [generation consumer](https://github.com/lostbean/json_blueprint/blob/main/examples/codegen/README.md)
shows a separate build task, generated records, application policy, and
production compilation. Generation does not create new native types at
application runtime.
