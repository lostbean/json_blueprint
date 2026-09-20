# Schema-Aware Core Oracle Corpus & Provenance

## Baseline Environment and Commits

- Package Repository: `/code/gleam-dream/json_blueprint`
- Baseline commit: `0e379c6491d34aca49795f716e87b9003df0130e` (`v1.7.1`, `main`)
- Package License: MIT (`LICENCE.md` in `json_blueprint`)
- Oversight Baseline commit: `bd0b83743533313eb9b4eee2bf7f99ed68a26750`
- Oversight License: No declared LICENSE file in `/code/gleam-dream/oversight` (internal design and oracle repository)
- Branch: `implementation/schema-aware-core`

## Provenance Table

| New test | source file/case | revision/hash/license | normalization | matched semantic |
| --- | --- | --- | --- | --- |
| `number_test.exact_number_kernel_test` | `playground/interface_lab/number_check.py` (`"1.2300e2"`, `"123"`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Renamed `JsonNumber` -> `Number`; invoked `parse_number`, `number_text`, `compare`, `to_int_exact` | Canonical scientific exponent `1.23e2`, mathematical equality with `123`, and exact integer projection `123` |
| `number_test.number_resource_limits_test` | `playground/interface_lab/number_check.py` (`TokenTooLong`, `TooManySignificandDigits`, `ExponentOutOfRange`, `InvalidSyntax`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Tested explicit positive limits and syntax validation | Rejection of tokens exceeding byte limits, digit limits, or normalized exponent range |
| `number_test.integer_projection_limits_test` | `playground/interface_lab/number_check.py` (`FractionalInteger`, `IntegerDigitLimitExceeded`) | `bd0b83743533313eb9b4eee2bf7f99ed68a26750` / no declared LICENSE (oversight) | Tested exact integer projection constraints | Distinct rejection of fractional values and digits exceeding projection limit |
| `json_blueprint_test.string_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | String decode and Draft 7 schema generation |
| `json_blueprint_test.int_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Integer decode and Draft 7 schema generation |
| `json_blueprint_test.float_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Float decode and Draft 7 schema generation |
| `json_blueprint_test.bool_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Boolean decode and Draft 7 schema generation |
| `json_blueprint_test.list_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | List decode and Draft 7 schema generation |
| `json_blueprint_test.optional_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Optional field decode |
| `json_blueprint_test.person_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Object decode and Draft 7 schema generation |
| `json_blueprint_test.nested_object_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Nested object decode |
| `json_blueprint_test.tuple_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Tuple2/3 decode |
| `json_blueprint_test.decoder_error_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Syntax error and type error handling |
| `json_blueprint_test.json_schema_string_format_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | String constraint schema generation |
| `json_blueprint_test.json_schema_number_constraint_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Number constraint schema generation |
| `json_blueprint_test.reuse_decoder_test` | `test/json_blueprint_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Reused decoder reference generation |
| `examples/union_type_test.union_type_test` | `test/examples/union_type_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Union type encode/decode |
| `examples/union_type_test.constructor_type_decoder_test` | `test/examples/union_type_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Union type schema matching |
| `examples/enum_tuple_and_optional_test.drawing_test` | `test/examples/enum_tuple_and_optional_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Record with tuple and optional field |
| `examples/enum_tuple_and_optional_test.drawing_match_str_test` | `test/examples/enum_tuple_and_optional_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Drawing wire match and schema validation |
| `examples/enum_tuple_and_optional_test.enum_type_test` | `test/examples/enum_tuple_and_optional_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Historical {"enum":"red"} envelope encode/decode |
| `examples/enum_tuple_and_optional_test.palette_test` | `test/examples/enum_tuple_and_optional_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Complex nested enum and tuple record |
| `examples/recursive_types_test.tree_decoder_test` | `test/examples/recursive_types_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Recursive tree decode and self_decoder |
| `examples/recursive_types_test.tree_decoder_match_str_test` | `test/examples/recursive_types_test.gleam` | `0e379c6491d34aca49795f716e87b9003df0130e` / MIT | None (legacy baseline) | Recursive tree schema generation |

## Source-Coverage Ledger

| Family | Total upstream cases | Status in this Checkpoint | Rationale / Detail |
| --- | --- | --- | --- |
| Legacy 1.7.1 API & Tests | 21 test functions | Ported / Preserved (21 passed) | All baseline tests preserved and pass on Erlang and JavaScript without modifications |
| Compatibility Baseline | 2 packages (1.1.0, 1.7.1) | Traced / Passing | Checksums verified: 1.1.0 (`8798...`), 1.7.1 (`6260...`). Probes in `playground/blueprint_compatibility/` verified clean |
| Exact Number Vertical | Focused parse/canonical/compare/exact-int slice | Ported / Passing (3 tests, Erlang) | Single vertical implemented and tested: parse `"1.2300e2"`, canonical `"1.23e2"`, compare equal to `"123"`, exact integer projection `123`, plus token/digit/exponent limits and projection constraints |
| Remaining Number Engine | 62 cases in `number_check.py` | Backlog / Planned for dedicated number wave | Broad numeric engine (IEEE-754 float parts, `from_float_exact`, `to_float_exact`, `from_int`, `is_integer`, JS port) retained as honest named todos; no fake FFI |
| Schema Agreement Oracle | 61 cases in `schema_check.py` | Traced / Planned | Agreement between Draft 2020-12, runtime validator, and codecs is planned for schema wave |
| Runtime Contracts | `blueprint_runtime.gleam` suite | Scaffolding complete; planned | Signatures typed with honest named todos in `src/json/blueprint/runtime.gleam` |
| Document Loading | `blueprint_document.gleam` suite | Scaffolding complete; planned | Signatures typed with honest named todos in `src/json/blueprint/document.gleam` |
| Type Boundary Negatives | 8 fixtures in `negative/` | Traced / Planned | Fixtures checked in oversight; type-system enforcement planned for respective waves |
| Source Generation | 16 modules, 4 negatives | Excluded from initial facade | Source generation is experimental backlog tooling outside the initial public API freeze |

## Historical Expected-Red Catalog

| Catalog Property | Detail |
| --- | --- |
| Focused Command | `nix develop --command gleam test --target erlang` (isolating `number_test.exact_number_kernel_test`) |
| Public Behavior | Parse `"1.2300e2"` under explicit limits `(1024, 100, 1000)`, format canonical `"1.23e2"`, compare equal to `"123"`, exact integer projection `123` |
| Expected Failure Site / Message | `src/json/blueprint/number.gleam` `parse_number`: `todo as "construct exact decimal representation from validated number token"` |
| Observed Failure | Runtime panic: `todo dependency: construct exact decimal representation from validated number token` |
| Removal Condition | Implementation of the focused exact decimal parser, canonical exponent formatter, mathematical magnitude comparison, and exact integer projection in `src/json/blueprint/number.gleam` on `@target(erlang)` |
| Transition to Green | Passing (3 focused tests green, 0 failures) without float conversions or dynamic decoders |
