# Wave 4 Completion Report: JSON Blueprint Release Candidate

**Date:** 2026-09-20

**Repository:** `/code/gleam-dream/json_blueprint`

**Branch:** `implementation/schema-aware-core`

**Starting HEAD:** `cf378926647ed83dc0669f49d4bb8591b5e1381f`

**Status:** Reviewed Release Candidate (Pending Sol Medium Acceptance)

---

## 1. Review Findings Resolved (review-4.md)

1. **Checked Safe-Integer Construction Boundary (`from_int`)**:
   - `number.from_int` returns `Result(Number, IntegerConstructionError)` with typed errors: `NonFiniteInteger`, `NonIntegerValue`, and `UnsafeNativeInteger`.
   - On JavaScript: validates safe native integer range `[-9007199254740991, 9007199254740991]` (`Number.MIN_SAFE_INTEGER` to `Number.MAX_SAFE_INTEGER`), rejecting non-finite values (`NaN`, `±Infinity`), non-integers, and numbers rounded before construction (`9007199254740993` rounded to `9007199254740992`).
   - On Erlang: validates `is_integer(Value)`, preserving arbitrary-precision bignums and rejecting non-integers without exceptions.
   - Legacy `json/blueprint` API remains 100% untouched.

2. **Aligned CR/LF/CRLF Parser and Scanner Behavior**:
   - Aligned `advance_char` and `find_invalid_utf8` in `src/json/blueprint/parser.gleam` so that standalone `CR` (`\r`), `LF` (`\n`), and `CRLF` (`\r\n`) uniformly advance `line + 1` and reset `column` to 1.
   - Added regression tests in `test/parser_test.gleam` covering CR followed by invalid bytes, LF followed by invalid bytes, CRLF followed by invalid bytes, and standalone CR whitespace.

3. **Sub-Quadratic Parser Duplicate Detection & Wide-Object Boundary Test**:
   - Replaced quadratic `list.contains seen_keys` in `parse_object_members` (`src/json/blueprint/parser.gleam`) with `gleam/dict` (`dict.Dict(String, Nil)`), providing $O(\log n)$ lookup and insert.
   - Added `wide_object_resource_and_duplicate_boundary_test` in `test/parser_test.gleam` proving 2,000 distinct properties parse cleanly and a duplicate property at the end is rejected with exact byte offset, line, and column.

4. **Pinned Semantic IDs & Checked Manifest for 61 Schema Fixtures**:
   - Replaced generated `label#index` with stable semantic IDs (`family/case-name`) across all 61 cases in `test/schema_oracle_runner.gleam`.
   - Frozen exact manifest in `test/schema_manifest.json` across 13 families.
   - Updated `test/schema_check.py` to strictly validate exact schemas, instances, and outcomes, reject duplicate payloads in the same family, and execute fail-closed mutation proofs verifying that missing, extra, duplicate, or replaced fixtures fail closed.

5. **Runnable Timed Microbenchmark Suite**:
   - Replaced placeholder count loops in `test/bench_test.gleam` with a runnable timed benchmark suite using monotonic timer FFI (`test/bench_ffi.erl` and `test/bench_ffi.mjs`).
   - Measures warmup iterations, sample iterations, total elapsed nanoseconds, mean nanoseconds/op, and operations/second across 4 operations: number parsing/canonicalization, parser whole-document admission, runtime contract validation, and codec encode/decode roundtrip.
   - Reports measured baselines for Erlang/OTP 28 and Node.js v24.15.

6. **Hostile Property Suite with Deterministic Generated Law Corpus**:
   - Expanded `test/hostile_test.gleam` with a deterministic PRNG and edge-value corpus across strings, integers (including boundary and 64-bit/53-bit limits), booleans, lists, nullables, pairs, integer ranges, and records.
   - Verifies identity roundtrip, idempotence, type mismatch rejection, integer range boundary rejection, string enum domain rejection, tagged union discriminator rejection, and closed object extra property rejection on both Erlang and JavaScript targets.

7. **Distinct Exact Decimal Capability in Consumer Admission**:
   - Updated `Feature` in `test/consumer_admission_test.gleam` with `ExactDecimalValues` and `DecimalBounds(min, max)`.
   - Mapped `codec.NumberSchema` and `codec.NumberRangeSchema` distinctly from `IntegerValues`.
   - Added `exact_decimal_admission_distinction_test` verifying admission policies for integer-only vs decimal-capable consumers.

8. **README Example as Checked Source of Truth**:
   - Implemented `test/readme_example_test.gleam` with `readme_snippets_exact_match_test`, extracting published Gleam snippets from `README.md` and verifying character-for-character equality against executable test code.
   - Executable examples compile and run on both targets with honest error handling (handling safe integer construction results without panics).

9. **Honest Target Support Matrix**:
   - Full Support documented only for independently exercised environments: Erlang/OTP 28 and Node.js v24.15. Browser JavaScript is classified as unverified.

---

## 2. Target Support Matrix

| Target | Status | Exact Number Model | Native Integer Bounds | Binary64 Float Projections | Exercised Environment |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **BEAM / Erlang** | Full Support | Arbitrary-precision decimal | Unlimited (bignum) | Lossless binary64 conversion | OTP 28 (all 99 tests pass) |
| **JavaScript (Node.js)** | Full Support | Arbitrary-precision decimal | `[-9007199254740991, 9007199254740991]` (typed `UnsafeNativeInteger` refusal / `UnsupportedNativeInteger` refusal) | Lossless binary64 conversion via BigInt | Node.js v24.15 (all 99 tests pass) |
| **JavaScript (Browser)** | Unverified | Target-neutral ESM (`TextEncoder`, `DataView`, `BigInt`), but unverified in test suite | Same as Node.js | Same as Node.js | Untested in CI |

---

## 3. Measured Local Benchmark Baselines

Measured with warmup (200 batches/ops) and 1,000 timed samples per benchmark.

For `number_parse_canonical_7_token_batch`, one operation is one seven-token parse/canonical batch (`["0", "1", "1.2300e2", "123.45", "-0.5", "9007199254740992", "1e400"]`). 1,000 batches = 7,000 number operations, with 200 batches warmup. Units are reported as ns/batch and batches/sec. Other benchmark units remain ns/op and ops/sec.

### Erlang / OTP 28:
- `number_parse_canonical_7_token_batch`: 1,000 samples, **2,247 ns/batch** (~321 ns/token), **445,037 batches/sec** (~3,115,259 tokens/sec)
- `parser_document_admission`: 1,000 samples, **9,847 ns/op**, **101,553 ops/sec**
- `runtime_contract_validation`: 1,000 samples, **295 ns/op**, **3,389,830 ops/sec**
- `codec_encode_decode_roundtrip`: 1,000 samples, **346 ns/op**, **2,890,173 ops/sec**

### JavaScript / Node.js v24.15.0:
- `number_parse_canonical_7_token_batch`: 1,000 samples, **17,712 ns/batch** (~2,530 ns/token), **56,458 batches/sec** (~395,206 tokens/sec)
- `parser_document_admission`: 1,000 samples, **41,057 ns/op**, **24,356 ops/sec**
- `runtime_contract_validation`: 1,000 samples, **4,450 ns/op**, **224,719 ops/sec**
- `codec_encode_decode_roundtrip`: 1,000 samples, **6,581 ns/op**, **151,952 ops/sec**

---

## 4. Exact Gate Verification Results

| Gate Command | Environment | Status / Output |
| :--- | :--- | :--- |
| `gleam format --check src test` | nix develop (`json_blueprint`) | Clean exit code 0; zero unformatted files |
| `gleam check` | nix develop (`json_blueprint`) | Clean exit code 0; zero compiler warnings |
| `gleam test --target erlang` | Erlang/OTP 28 | **99 passed, 0 failures** |
| `gleam test --target javascript` | Node.js v24.15 | **99 passed, 0 failures** |
| `python3 test/schema_check.py` | Python 3.12 + `jsonschema` 4.26.0 | **PASS: all 61 cases agree** with `Draft202012Validator`; **PASS: fail-closed mutation proofs passed** |
| `gleam docs build` | nix develop (`json_blueprint`) | Rendered to `build/dev/docs/json_blueprint/index.html` |
| `gleam export hex-tarball` | nix develop (`json_blueprint`) | Tarball generated to `build/json_blueprint-1.7.1.tar` |
| `gleam export erlang-shipment` | nix develop (`json_blueprint`) | Shipment generated to `build/erlang-shipment` |

---

## 5. Changed and Added Files Inventory

### Source Files:
- `src/json/blueprint/codec.gleam`: Fixed tagged union discriminator wrong-type error at `tag`; updated `int()` and `integer_between()` to handle checked native int construction errors.
- `src/json/blueprint/number.gleam`: Added `IntegerConstructionError` (`NonFiniteInteger`, `NonIntegerValue`, `UnsafeNativeInteger`) and safe integer construction guard to `from_int`; added `UnsupportedNativeInteger` to `IntegerProjectionError`; unified kernel across Erlang and JavaScript; removed all target isolation annotations.
- `src/json/blueprint/parser.gleam`: Sub-quadratic dictionary duplicate key detection; aligned CR/LF/CRLF byte, line, and column tracking across `advance_char` and `find_invalid_utf8`.
- `src/json/blueprint/migration.gleam`: Legacy 1.7.1 migration bridge module.
- `src/json_number_ffi.erl`: Complete Erlang FFI for float parts, candidate parsing, rational expansion, safe native int projection, and `validate_native_int/4`.
- `src/json_number_ffi.mjs`: Complete JavaScript FFI with BigInt-based rational expansion, safe native integer bounds checking, and `validate_native_int` construction guard.

### Test Files:
- `test/number_test.gleam`: Unified 62-case exact number kernel tests running on both Erlang and JavaScript; adversarial tests for safe integer construction.
- `test/number_test_ffi.erl` & `test/number_test_ffi.mjs`: Test FFI for float bit hex encoding/decoding and raw untyped `from_int` testing.
- `test/bench_ffi.erl` & `test/bench_ffi.mjs`: High-resolution monotonic timing and runtime detection FFI.
- `test/bench_test.gleam`: Runnable timed microbenchmark suite with warmup, sample batches, and reported statistics.
- `test/readme_test_ffi.erl` & `test/readme_test_ffi.mjs`: Test FFI for reading file contents in README verification test.
- `test/readme_example_test.gleam`: Extracts README code blocks and asserts character-for-character equality against executable tests.
- `test/parser_test.gleam`: Bounded byte admission tests (12 tests), including wide object resource boundary test (2,000 members) and CR/LF/CRLF invalid byte location regressions.
- `test/hostile_test.gleam`: Hostile/property test suite with deterministic generated law corpus and rejection property tests.
- `test/consumer_admission_test.gleam`: Relay, Fabric, and LLM admission profiles with distinct `ExactDecimalValues` and `DecimalBounds` feature tracking.
- `test/schema_oracle_runner.gleam`: Emits 61 cases with stable semantic IDs across 13 families.
- `test/schema_manifest.json`: Frozen manifest of all 61 cases with schema, instance, and expected outcome.
- `test/schema_check.py`: Strictly validates live emitted cases against manifest and Draft202012Validator, and runs fail-closed mutation verification.
- `test/examples/schema_aware_core_example_test.gleam`: End-to-end example and README migration example compile check with honest error handling.

### Documentation & Reports:
- `README.md`: Verified quickstart snippet, migration contract snippet, target support matrix, supported Draft 2020-12 profile.
- `test/oracle/schema-aware-core.md`: Full provenance and capability ledger.
- `test/oracle/wave-4-capabilities.md`: Records capability probes.
- `test/oracle/wave-4-report.md`: This report.

---

## 6. Todo & Blocker Inventory

- **Production `todo` count on advertised release paths**: 0.
- **Throwing FFI shims**: 0.
- **Review Blockers**: All 6 review-4 findings resolved with direct native evidence.
- **Release Status**: Candidate submitted for Sol Medium acceptance review.

---

## 7. Retained Design-Deferred Families (Post-Release)

The following capabilities are explicitly outside the initial release facade per `PUBLIC-API.md`:
1. **Source Code Generation**: Paused for application naming research.
2. **Recursive Schema References (`$ref`, `$defs`)**: Deferred pending resource and cycle policies.
3. **Arbitrary Union Schemas**: Untagged unions (`anyOf`, general `oneOf`) deferred pending subtyping policy.
4. **Pattern / Regex**: String format regex validation deferred.

---

## 8. Operational Constraints Confirmed

- **Working tree**: Modified and uncommitted on branch `implementation/schema-aware-core`.
- **Git history**: Zero commits created, no push, no publication performed.
- **Oversight repository**: Read-only reference context; zero files modified.
- **Background jobs**: 0 running tasks; all child processes awaited synchronously.
