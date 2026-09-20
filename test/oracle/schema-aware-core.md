# Schema-Aware Core Oracle Corpus & Provenance

## Baseline Environment and Commits

- Package Repository: `/code/gleam-dream/json_blueprint`
- Wave 3 Baseline commit: `fc8dae8d1c4eabf97d7ae8d4fa201cdc24f6b289` (`implementation/schema-aware-core`)
- Upstream Baseline commit: `0e379c6491d34aca49795f716e87b9003df0130e` (`v1.7.1`, `main`)
- Package License: MIT (`LICENCE.md` in `json_blueprint`)
- Oversight Baseline commit: `bd0b83743533313eb9b4eee2bf7f99ed68a26750`
- Oversight License: No declared LICENSE file in `/code/gleam-dream/oversight` (internal design and oracle repository)
- Branch: `implementation/schema-aware-core`

## Provenance Table

| New test / harness | source file/case | revision/hash/license | normalization | matched semantic |
| --- | --- | --- | --- | --- |
| `number_test.exact_number_kernel_test` | `playground/interface_lab/number_check.py` (`"1.2300e2"`, `"123"`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Renamed `JsonNumber` -> `Number`; invoked `parse_number`, `number_text`, `compare`, `to_int_exact` | Canonical scientific exponent `1.23e2`, mathematical equality with `123`, and exact integer projection `123` |
| `number_test.number_resource_limits_test` | `playground/interface_lab/number_check.py` (`TokenTooLong`, `TooManySignificandDigits`, `ExponentOutOfRange`, `InvalidSyntax`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Tested explicit positive limits and syntax validation | Rejection of tokens exceeding byte limits, digit limits, or normalized exponent range |
| `number_test.integer_projection_limits_test` | `playground/interface_lab/number_check.py` (`FractionalInteger`, `IntegerDigitLimitExceeded`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Tested exact integer projection constraints | Distinct rejection of fractional values and digits exceeding projection limit |
| `number_test.parse_syntax_and_resource_errors_test` | `playground/interface_lab/number_check.py` (16 rejection tokens: `"+1"`, `"01"`, `"1."`, `".1"`, `"1e"`, `"1e+"`, `"--1"`, `"1.2.3"`, `"9"*33+"e+"`, `"9"*33+"e1"`, `"١"`, `" 1"`, `"1e1201"`, `"0e1266"`, `"9"*33`, `"9"*65`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Direct package assertions against `json/blueprint/number` | Rejection of 16 invalid syntax or resource limit tokens with typed `NumberError` |
| `number_test.parse_accepted_numbers_test` | `playground/interface_lab/number_check.py` (23 accepted tokens: `"-0"`, `"0"`, `"1"`, `"1.0"`, `"10e-1"`, `"100e-2"`, `"123.45"`, `"1.2300e2"`, `"123.45e1201"`, `"100e-1202"`, `"0.5"`, `"0.1"`, `"0.125"`, `"9007199254740992"`, `"9007199254740993"`, `"123456789012345678901234567890"`, `"1e400"`, `"1e-400"`, `"1e-324"`, `"1.7976931348623157e308"`, `"1.7976931348623159e308"`, `"-0.5"`, `"-123.45"`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Direct package assertions against `json/blueprint/number` | Exact canonical text, mathematical integrality, checked integer projection, exact IEEE-754 float projection, and overflow/underflow/inexact validation |
| `number_test.comparison_pairs_test` | `playground/interface_lab/number_check.py` (11 comparison pairs) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Direct package assertions against `json/blueprint/number` | Exact mathematical magnitude comparison (`EqualTo`, `LessThan`, `GreaterThan`) without machine float rounding |
| `number_test.from_float_exact_cases_test` | `playground/interface_lab/number_check.py` (7 float fixtures) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Direct package assertions against `json/blueprint/number` | Exact rational binary expansion, canonical decimal text, and roundtrip float preservation |
| `number_test.from_int_cases_test` | `playground/interface_lab/number_check.py` (5 integer fixtures) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Direct package assertions against `json/blueprint/number` | Exact conversion `from_int`, canonical scientific exponent text, and lossless `to_int_exact` roundtrip |
| `value_test.gleam` (2 suites) | `blueprint-design.md` §3 | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Package module `json/blueprint/value` | `Value` constructors (`Null`, `Bool`, `String`, `Number`, `Array`, `Object`) and checked `RejectDuplicates` key policy |
| `codec_test.gleam` (12 suites) | `blueprint-design.md` §4, `playground/interface_lab/src/lab/blueprint.gleam` | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Package module `json/blueprint/codec` | Bidirectional encode/decode, `imap`, primitives (`string`, `int`, `number`, `bool`), combinators (`pair`, `list`, `nullable`, `object`, `field`, `string_enum`, `tagged`, `integer_between`, `number_between`), and Draft 2020-12 schema rendering |
| `runtime_test.gleam` (4 suites) | `blueprint-design.md` §6, `playground/interface_lab/src/lab/blueprint_runtime.gleam` | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Package module `json/blueprint/runtime` | Schema normalization (sorting of properties, enum labels, tagged branches; range and duplicate invariants), located root-to-leaf validation errors, `matches`, and retained-codec `decode` |
| `document_test.gleam` (4 suites) | `blueprint-design.md` §5, `playground/interface_lab/src/lab/blueprint_document.gleam` | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Package module `json/blueprint/document` | Strict Draft 2020-12 dialect loading, closed object enforcement, unknown keyword rejection, and schema invariant mapping |
| `schema_oracle_test.gleam` (13 suites, 61 cases) | `playground/interface_lab/src/schema_corpus.gleam` (61 cases across 13 families) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Package test module `schema_oracle_test` | Direct package execution of all 61 cases verifying codec decode, runtime validation, and document load roundtrip |
| `schema_check.py` (61 cases) | `playground/interface_lab/schema_check.py` | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Independent differential validator | Direct comparison of emitted package schemas and normalized schemas against `jsonschema 4.26.0` `Draft202012Validator` (100% agreement) |
| `json_blueprint_test.gleam` + `examples/` (21 suites) | `test/json_blueprint_test.gleam`, `test/examples/*` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Preserved legacy 1.7.1 API, decoders, and schema generation passing on both Erlang and JavaScript |

## Source-Coverage Ledger

| Family | Total upstream cases | Status in Wave 3 | Rationale / Detail |
| --- | --- | --- | --- |
| Legacy 1.7.1 API & Tests | 21 test functions | Ported / Preserved (21 passed) | All baseline tests preserved and pass on Erlang and JavaScript without modifications |
| Compatibility Baseline | 2 packages (1.1.0, 1.7.1) | Traced / Passing | Checksums verified: 1.1.0 (`8798...`), 1.7.1 (`6260...`). Probes in `playground/blueprint_compatibility/` verified clean |
| Exact Number Kernel (Erlang) | 62 cases in `number_check.py` across 4 families | Ported / Passing (9 tests green) | Full Erlang exact number kernel implemented and tested on package: 39 parse tokens (16 rejections + 23 accepted), 11 comparison pairs, 7 float fixtures, 5 integer fixtures. Executed via `nix develop --command gleam test --target erlang` |
| Exact Number Kernel (JavaScript) | 62 cases | Deferred / Honest Named Todos | `@target(javascript)` public functions fail only via explicit named Gleam todos; no fake FFI or throwing runtime shims; 21 legacy JS tests remain green |
| Value & Key Policy | `Value` constructors, `RejectDuplicates` | Ported / Passing (2 tests green) | Algebra complete; duplicate rejection tested and verified |
| Finite Codec & Combinators | Primitives, pairs, lists, nullable/optional, objects, enums, tagged unions, ranges | Ported / Passing (12 tests green) | Bidirectional codecs with typed `EncodeReason`/`DecodeReason` and `Schema` emission |
| Runtime Contracts & Normalization | `from_codec`, `from_schema`, `validate`, `matches`, `decode` | Ported / Passing (4 tests green) | Schema normalization, structural matching, and root-to-leaf located typed errors |
| Strict Document Loading | `load` from parsed `Value` | Ported / Passing (4 tests green) | Draft 2020-12 root declaration checks, keyword white-listing, closed object enforcement, located `DocumentError` |
| Schema Agreement Oracle | 61 cases in `schema_corpus.gleam` and `schema_check.py` | Ported / Passing (13 tests green + python oracle green) | All 61 cases pass package tests and exhibit 100% agreement with `jsonschema 4.26.0` `Draft202012Validator` |
| Type Boundary Negatives | 8 fixtures in `negative/` | Traced / Planned | Fixtures checked in oversight; type-system enforcement verified by Gleam compiler |
| Source Generation | 16 modules, 4 negatives | Excluded from initial facade | Source generation is experimental backlog tooling outside the initial public API freeze |

## Capability Inventory & Roadmap

| Capability Area | Status / Target | Disposition & Revisit Trigger |
| --- | --- | --- |
| Finite Value/Codec/Schema Facade | Implemented (Wave 3) | Complete initial production facade on supported target (Erlang) |
| Draft 2020-12 Schema Agreement | Implemented (Wave 3) | 61/61 cases verified against `Draft202012Validator` (`jsonschema 4.26.0`) |
| Strict Document Loading | Implemented (Wave 3) | Loads parsed `Value` into `RuntimeContract` with strict Draft 2020-12 syntax and closed forms |
| Legacy 1.7.1 API Preservation | Implemented (Wave 3) | All 21 legacy tests pass unmodified on Erlang and JavaScript targets |
| JavaScript Exact-Number Parity | Wave 4 (Integration) | Implement exact-number arithmetic/projection in JS using BigInt or decimal arithmetic to replace honest named todos |
| Whole-Document Byte Parser | Wave 4 (Integration) | Byte-level JSON parser with configurable duplicate-key, UTF-8, number token limits, recursion depth, and location tracking |
| Legacy 1.7.1 Migration Layer | Wave 4 (Integration) | Ergonomic migration path and interoperability between legacy `json_blueprint` decoders and new schema-aware codecs |
| Consumer Profiles (Relay / Fabric / LLM) | Wave 4 (Integration) | Validate that emitted schema documents satisfy the specific consumers in the `gleam-dream` ecosystem |
| Hostile Input & Resource Hardening | Wave 5 (Release) | Fuzzing, maximum token byte limits, deep nesting limits, and performance profiling against adversarial payloads |
| Packaging, Hex Publication & Docs | Wave 5 (Release) | Final Hex package publication, comprehensive documentation, and removal of remaining release-blocking todos |
| Recursive References (`$ref`, `$defs`) | Retained Post-Release Family | Explicit backlog in `blueprint-design.md`; requires consumer demand and cycle-safe validator oracle |
| Broader Constraints & Arbitrary Unions | Retained Post-Release Family | Open unions (`anyOf` beyond nullable, pattern regex, array length bounds); deferred to future design waves |
| Codec Source Generation Tooling | Retained Post-Release Family | Experimental code generation tooling (`blueprint_codegen`); explicitly out-of-scope for initial runtime package |
