# Changelog

## Unreleased — intended 2.0

2.0 adds `json/blueprint/codec`: one `Codec(a)` that encodes, decodes JSON
strictly and describes a Draft 2020-12 schema. The 1.x API stays in
`json/blueprint`, frozen. See [the 1.x → 2.0 guide](docs/migration-2.0.md);
code written against the unreleased 2.0 branch has
[its own guide](docs/migration-wave-2.md). The manifest version remains 1.7.1
until a release decision.

### Codecs

- Describe records with a `use`-based builder: `codec.field`,
  `codec.optional_field` (an `Option`) and `codec.success`. Objects are
  closed; unknown fields, duplicate keys and wrong types fail with a path.
- Describe sum types with `codec.union`, `variant`, `unit_variant` and
  `match`, on the `{"tag": ..., "value": ...}` envelope; a unit variant has
  no `"value"`. Gleam checks the `match` for exhaustiveness.
- Build codecs from `string`, `int`, `float` (rounds to the nearest float),
  `number` (exact), `bool`, `list`, `pair`, `nullable` (an `Option`),
  `string_enum`, `integer_between`, `number_between`, `describe`, `map`,
  `try_map` and `custom`. `try_map` and `custom` take an explicit
  placeholder value.
- Use a codec with `encode`, `decode`, `encode_json`, `decode_json`,
  `decode_json_with_limits`, `schema`, `schema_json`, `schema_value` and
  `schema_document`, and with `gleam/json` through `codec.to_json` (exact; a
  number without an exact form is an `UnrepresentableNumber` error) and
  `codec.decoder`.
- Errors are flat `DecodeError(path, reason)` and `EncodeError(path, reason)`
  records with one `Reason` union and no string payloads.
  `describe_decode_error` and `describe_encode_error` render them without
  input values; `is_limit_exceeded` tells a too-large input from an invalid
  one.
- Constructors return `Codec(a)`. A mistaken definition, such as a field
  named twice, a repeated enum label or reversed bounds, panics with a
  message naming the field, label or bounds where it is first used.
  `codec.check` returns the mistake as a `DefinitionError` instead, for
  definitions built from runtime data.

### Values, numbers and parsing

- `json/blueprint/value` holds the exact `Value` model, the strict parser
  (`parse`, `parse_bits`), the opaque `Limits`, the compact renderer
  (`to_string`), and the `gleam/json` bridges `to_json` and `decoder`.
- Parsing is bounded by default: 1 MiB, depth 64, 262,144 values (one per 4
  bytes of text) and number tokens of 1,024 bytes, 800 digits and exponent
  1,200. Change a bound with `with_max_bytes`, `with_max_depth`,
  `with_max_elements` or `with_number_limits`; a bound below 1 rejects
  every input. The value bound keeps the densest input at a 42 MB heap peak
  on Erlang/OTP 28, where 1 MiB of `[1,1,...]` peaked at 80 MB without it.
  Parse errors carry a location, contain no input text, and name the setter
  of the limit they hit.
- Parsing reads UTF-8 bytes directly and stores small integers natively, so
  1 MiB of 15-digit decimals peaks at 16 MB, down from 106 MB.
- `value.to_string` writes a number with a decimal exponent from -7 to 20 in
  plain form, such as `12.5` or `0.001`.
- `json/blueprint/number` holds exact JSON numbers: `parse`, `to_string`,
  `compare` (a `gleam/order.Order`), `is_integer`, `to_int` with a digit
  bound, `from_int`, `from_float` (shortest decimal), `from_float_exact`,
  `to_float` (nearest float) and `to_float_exact`.

### Contracts

- `json/blueprint/contract` accepts schemas at runtime: `from_codec`,
  `from_schema`, `load` and `parse` for Draft 2020-12 documents inside the
  codec profile (closed objects, pairs, lists, nullable values, bounded
  integers and numbers, string enums and tagged unions with unit variants).
  `validate` checks a value, with the codec's `Reason` and path vocabulary;
  `decode` decodes a validated value and fails with `ContractMismatch` when
  the codec's schema differs; `value_codec` is a `Codec(Value)` that
  validates while decoding. Errors have `describe_*` renderers.

### 1.x

- `json/blueprint/dynamic` is internal; use `gleam/dynamic/decode`.
- `Decoder` and `FieldDecoder` are opaque. `get_dynamic_decoder` returns
  `gleam/dynamic/decode.DecodeError` values.
- `blueprint.decode` rejects text above 1 MiB before `gleam/json` parses it,
  with one error that names the limit; `blueprint.decode_with_max_bytes`
  accepts another bound.
- The 1.x schema renderer still labels its output Draft-07 and uses `$defs`.

### Code generation

- `json/blueprint/codegen` is a separate dev-only package,
  `json_blueprint_codegen`, in `codegen/`. Generated modules call
  `json/blueprint/internal/generated`, whose names stay stable within a major
  version, and their `decode_<name>_json_native` returns `json.DecodeError`
  after a 1 MiB check.

### Docs and gate

- The README leads with the common path and lists every default with its
  setter and the measured heap. Every public module has a module doc whose
  example a test compiles and runs verbatim; the README examples are tested
  the same way. The 1.x examples moved to [docs/v1.md](docs/v1.md).
- `scripts/gate.sh` runs formatting, warnings-as-errors builds and the tests
  on Erlang/OTP 28 and Node.js 24 for both packages. Browser JavaScript is
  not tested. On JavaScript, native integers are limited to the safe range.
