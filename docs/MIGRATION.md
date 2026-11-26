# Migrating JSON Blueprint from 1.x

JSON Blueprint 3.0 removes the 1.x decoder and schema modules. Typed codecs,
exact JSON values, finite runtime contracts and source generators replace them.
Moving an application from 1.x to codecs requires a review of its accepted and
emitted JSON.

This guide compares published 1.7.1 with the current codec API. It does not
claim complete equivalence for every 1.x schema, error path, or numeric
boundary.

## Update the dependency

Update the application to the current JSON Blueprint from Hex and retain the resolved
version in `manifest.toml`:

```sh
gleam add json_blueprint
gleam build --warnings-as-errors
gleam test
```

Run every target your application supports. Update each independently resolved
example, adapter, and consumer through Gleam as well. Do not replace a historical
oracle dependency merely to make it match the application dependency.

## The 1.x API is removed

`json/blueprint` (`Decoder`, `FieldDecoder`, `decode0`..`decode9`, `field`,
`optional_field`, the tuple, union and enum helpers, `self_decoder`,
`reuse_decoder`, `decode` and `decode_with_max_bytes`) and
`json/blueprint/schema` are gone in 3.0. They parsed with `gleam/json` behind a
1 MiB byte check only, so they admitted documents nested deeper than the
default depth bound and repeated keys, which every other text decoder refuses,
and they converted each number to a native Int or Float while parsing. The strict
parser keeps each number's exact value until a codec projects it, so
`codec.number()` sees `0.1` exactly, while `codec.float()` still rounds it to
the nearest float. Generated modules lose `decode_<name>_json_native` for the
same reason. Code that still uses either does not compile against 3.0.

| 1.x                                                | Replacement                                                                                                    |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `blueprint.decode(using:, from:)`                  | `codec.decode_json(codec, text)`                                                                               |
| `blueprint.decode_with_max_bytes`                  | `codec.decode_json_with_limits(codec, text, value.default_limits() \|> value.with_max_bytes(n))`               |
| `decode1`..`decode9` with `field`                  | `codec.field(name, child, get:)` chained with `use`, finished by `codec.success`                               |
| `optional_field`                                   | `codec.optional_field`; wrap the child in `codec.nullable` to accept `null`                                    |
| `list`, `tuple2`, `map`                            | `codec.list`, `codec.pair`, `codec.map` / `codec.try_map`                                                      |
| `union_type_encoder` / `union_type_decoder`        | `codec.union` with `variant` and `unit_variant`; the envelope changes (below)                                  |
| `enum_type_encoder` / `enum_type_decoder`          | `codec.string_enum`; the label is no longer wrapped in an object                                               |
| `generate_json_schema`, `json/blueprint/schema`    | `codec.schema_json` and `codec.schema`, Draft 2020-12                                                          |
| `get_dynamic_decoder`                              | `codec.decoder(codec)`, a `gleam/dynamic/decode` decoder for data another parser produced                      |
| `self_decoder`, `reuse_decoder` (recursive types)  | No codec form: `value.parse(text, value.default_limits())`, then walk the `Value` with your own function       |
| generated `decode_<name>_json_native`              | generated `decode_<name>_json`                                                                                 |

Recursive data loses its derived schema. Read it from a parsed `Value`, as the
migration example's `parse_category` does: the depth bound then applies before
your function recurses. Data stored in the 1.x union envelope
(`{"type":...,"data":...}`) or enum object (`{"enum":...}`) needs an
application reader or a data migration before a codec reads it.

## Adopt codecs one boundary at a time

A `codec.Codec(a)` describes both native conversion directions and a schema.
Build it with public constructors, use `codec.field` or `codec.optional_field`
with a native getter for each record member, and finish the record with
`codec.success`. Use `codec.decode_json`, `codec.encode_json`, and
`codec.schema_json` at the boundary.

The [compiled migration example](https://github.com/gleam-dream/json_blueprint/blob/main/examples/test/migration_test.gleam)
converts one 1.x `Decoder(Person)` to a `Codec(Person)`. It also exercises
these intentional differences:

| Boundary                   | 1.x API                                                                             | Codec API                                                                                                                       |
| -------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Record members             | Nonempty record decoders ignore unknown members                                     | Built-in record codecs reject unknown members                                                                                   |
| Optional string property   | Missing and `null` both decode to `None`                                            | A plain `optional_field` accepts absence and rejects `null`                                                                     |
| Nullable optional property | Absence and `null` may collapse                                                     | `optional_field` containing `nullable` represents absence, `null`, and a value as `None`, `Some(None)`, and `Some(Some(value))` |
| Payload union              | The encoder emits `{"type":"circle","data":{"radius":2}}` for the example's payload | Its codec emits `{"tag":"circle","value":2}`                                                                                    |
| Enum                       | The encoder emits `{"enum":"high"}`                                                 | A string-enum codec emits `"high"`                                                                                              |

Capture representative stored values and protocol messages before changing a
boundary. Include missing, null, extra, malformed, and recursive cases. Check
both decoding and emitted JSON against those fixtures. If stored data or peers
still use the old form, write an application reader for it or migrate the data
before switching writers. There is no automatic conversion from 1.x decoders to
codecs.

The [optional-field example](https://github.com/gleam-dream/json_blueprint/blob/main/examples/src/examples/optional_fields.gleam)
shows the three-state representation and its encoding behavior.

## Review parser and number policy

`codec.decode_json` admits at most 1 MiB of UTF-8 nested at most 128 levels
deep by default, and rejects repeated object keys. Use
`codec.decode_json_with_limits` with `value.with_max_bytes` or
`value.with_max_depth` to select other bounds, or `value.unlimited()` for
trusted text. Value-count and global numeric admission limits and their
setters have been removed; the byte bound also bounds the number of values. Explicit
`number.parse(token, limits)` still supports caller-selected numeric limits.
On JavaScript, raising those limits cannot bypass exact integer representation:
unrepresentable written or normalized exponents and comparison magnitudes
return `ExponentOutOfRange` rather than silently rounding. Erlang retains exact
arbitrary-size integer arithmetic.

On Erlang/OTP 27 or later, parsing uses OTP's JSON decoder with duplicate
detection and exact numeric hooks. JavaScript uses native `JSON.parse` with
source-text retention for numbers, followed by a scan for decoded duplicate
names and malformed escaped surrogate pairs. Both targets decode built-in codecs
from the native tree; custom Value callbacks convert only their subtree.
`value.parse` still constructs a complete `Value` tree. This is not streaming:
the JavaScript native tree is allocated before duplicate-key rejection.

JavaScript strict parsing requires reviver `context.source` support. The old
portable parser fallback has been removed. Runtimes without this capability
return `UnsupportedRuntime`, not a syntax error or rounded values. This applies
to strict text/byte parsing and codec JSON decoding. See [browser/runtime requirements and executed checks](https://github.com/gleam-dream/json_blueprint/blob/main/docs/BROWSER-SUPPORT.md).

### Diagnostics and object order

Native parsing changes the JavaScript diagnostic contract as well as the Erlang
contract. Do not match native error wording or depend on source-order errors:

- Native syntax, duplicate-key and raw Unicode-scalar failures have
  `Location(0, 0, 0)`, meaning unavailable, rather than precise byte/line/column
  coordinates. Typed field/index paths remain available.
- Malformed syntax and unpaired escaped surrogates return `NativeSyntax`; raw
  unpaired UTF-16 surrogates return `InvalidUnicodeScalar`. They are rejected
  before UTF-8 conversion can replace them. Errors retain no source text.
- A multiply-invalid document may report a different first failure. Native
  syntax validation precedes duplicate scanning and typed callbacks. Deep
  malformed nesting can report syntax rather than exhausted host capacity.
- Erlang objects follow native map order. JavaScript follows `Object.keys`
  order: array-index names precede other names. Rendering parsed Values and
  choosing the first unknown field can therefore differ from source order.
  Array order is unchanged; manually constructed Values retain their order.

The byte bound is checked first. `parse_bits` rejects invalid UTF-8 and a leading
BOM. JavaScript exact decimal exponents and comparison magnitudes must fit its
safe-integer representation. Deep structures or long numeric tokens can exceed
host capacity and return `RuntimeCapacityExceeded`; the byte limit is not a
memory or stack quota. User callback exceptions remain owned by the caller.
Valid surrogate pairs and the literal replacement character remain accepted.

`codec.int()` supports at most 24 digits in both directions and requires safe
integers on JavaScript. Encoding a longer Erlang integer returns `ExpectedInt`;
`integer_between` retains its separate bound-derived digit allowance.
Use `codec.number()` and the exact `Number` operations for values
that must retain mathematical JSON precision. Treat projection into native
`Int` or `Float` as a separate operation that can fail or round. Use
`codec.float()` when binary floating-point conversion is acceptable. The
`gleam/json` and standard dynamic-decoder bridges retain their native parser
and number behavior; they do not inherit strict text-admission guarantees.

See the [larger-input example](https://github.com/gleam-dream/json_blueprint/blob/main/examples/src/examples/larger_inputs.gleam)
for explicit limits. Run large-number fixtures on each intended target.

## Review schemas and runtime contracts

The 1.x Draft-07 schema renderer is removed. Compare a codec's schema with the
schema snapshots you kept from 1.x before publishing it.

Modern codecs render Draft 2020-12 schemas through an opaque `codec.Schema`.
Use `codec.view` and its opaque children to inspect a schema. Runtime contracts
admit only the finite profile of supported shapes; a broader 1.x description
cannot be passed through as an equivalent contract. References, recursive
definitions, and other unsupported forms are refused. Review provider-specific
schema restrictions in the application as well.

`contract.parse` loads schema text with explicit admission limits, and
`contract.validate` checks a `Value`. Decoding a validated value requires a
codec with the same normalized schema. These checks do not certify custom
callback behavior or application authorization. The
[oracle documentation](https://github.com/gleam-dream/json_blueprint/blob/main/docs/ORACLE.md)
states the supported profile and the limits of its independent evidence.

## Keep generation in the build

The package now includes `json/blueprint/codegen` and
`json/blueprint/codegen/schema`. The separate `json_blueprint_codegen` package
was an unpublished checkout package; remove that dependency if you used it.
Keep the same generator imports and depend on `json_blueprint` alone.

Generation returns source. Your build task writes, formats, compiles, and reviews
that source for each target. Regenerate checked-in modules with the 3.0
generator, review the diff, and rerun parity and application tests before
committing the output. The schema generator's attribution header now names
JSON Blueprint. Do not edit generator output by hand to make a drift check pass.

Typed-definition output now registers specialized text encoding and direct
strict decoding on its codec accessor. Ordinary `codec.encode_json` and
`codec.decode_json` therefore use those functions. Strict decoding shares the
runtime parser and its duplicate-key, Unicode, exact-number and byte guarantees;
it no longer constructs an intermediate complete `Value` tree. From 3.0,
`decode_<name>_json` is the only generated text decoder; regenerate checked-in
modules to drop `decode_<name>_json_native`.

Two observable details now align with runtime codecs. The shared generated
Value decoder checks declared fields before unknown or repeated members, including
for existing generated modules. Regenerated codec accessor construction no longer
evaluates mapped placeholders eagerly.
Placeholder mappings run when a placeholder is needed. Strict text duplicates
still fail before typed callbacks. Replay multi-error fixtures and any mapping
callbacks with observable effects; source references must match the supplied
runtime functions. Mappings should be pure: generated schema and known-field
metadata do not replay runtime placeholder introspection. Conversion order is
preserved, but introspection callback counts are not an equivalence guarantee.

Specialization does not expand the typed generator's supported shapes. Exact
`Number` compilation still returns `NativeNumberUnsupported`. Schema-driven
codecs retain exact-number support through ordinary runtime combinators.
Generated schema structures are retained, but schema JSON text is rendered on
demand. Ordinary composition around a generated codec preserves semantics and
direct child decoding; its outer text encoder uses the ordinary Value path.
As before, a typed-generated object codec can be nested as a child, but cannot
finish a `codec.field` or `codec.optional_field` record continuation. Use an
ordinary runtime record builder to extend a record. Replacement equivalence
covers value, text, and schema operations, not record-builder capability.

Schema-driven generation supports a narrower closed-object subset than runtime
contracts. Admitting a schema as a contract does not guarantee generation support.

The [generation consumer](https://github.com/gleam-dream/json_blueprint/blob/main/examples/codegen/README.md)
shows a separate build task, generated records, application policy, and
production compilation. Generation does not create new native types at
application runtime.
