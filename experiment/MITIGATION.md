# Erlang-native duplicate and precision mitigation

THROWAWAY experiment, 2026-10-25. Question: can Erlang native parsing reject duplicate keys and preserve numeric precision while retaining most of the plain-native speed gains?

**Yes, for the measured supported shapes. Prefer deferred decimal conversion over eagerly constructing every exact Number.** The deferred candidate keeps approximately 87% of the plain-native elapsed-time saving on the 50-record response and 99% on decimals decoded as Float. It remains approximately 1.8× and 14.2× faster than the optimized strict decoder respectively. These are local observations, not promises for arbitrary codecs.

This continues in the isolated `native-direct-decoding` worktree. All additions are test modules and experiment evidence. Production source hashes match `baseline.json`; no public API, design or release change was made. An implementation subagent built the two adapters; an independent subagent reviewed OTP hook behavior, FFI representations and numeric semantics.

## Candidates

1. **Plain native:** previous `gleam/json` parse plus direct typed decoding; no duplicate rejection, decimal precision already lost before decoding.
2. **Duplicate-only:** OTP object hooks reject repeated decoded names, including escaped equivalents; default native numbers remain.
3. **Eager exact:** duplicate rejection plus OTP integer/float callbacks constructing exact Number values for every token, then typed conversion.
4. **Deferred decimals:** duplicate rejection, native arbitrary-precision Erlang integers, and tagged decimal-token binaries. Typed Int projection checks decimal mathematical integrality exactly; `number()` builds an exact Number on demand; Float projection deliberately rounds through native binary64 conversion.

All candidates parse a complete native tree before typed decoding; none is streaming from source to the final record. The deferred tree holds numeric tokens until conversion. Plain integers never pass through Float. `1.00000000000000001` therefore fails Int decoding, while `1.0` and `1e0` succeed. Requesting an exact Number preserves the fractional value. Requesting Float intentionally rounds, consistent with the purpose of the existing float codec.

## Fresh Erlang measurements: deferred candidate

Median microseconds per complete parse+typed decode. A larger speedup is better.

| Fixture | Strict µs | Plain native µs | Deferred µs | Strict/deferred speedup | Native time saving retained |
|---|---:|---:|---:|---:|---:|
| small_record | 1.86 | 0.94 | 1.18 | 1.58× | 74% |
| records_50 | 96.28 | 43.65 | 50.08 | 1.92× | 88% |
| response_50 | 96.20 | 46.01 | 52.67 | 1.83× | 87% |
| ints_10000 | 2309.48 | 882.62 | 1088.24 | 2.12× | 86% |
| ints_limit | 231350.38 | 25257.12 | 37457.38 | 6.18× | 94% |
| nested_100x100 | 2263.83 | 821.74 | 1104.26 | 2.05× | 80% |
| decimals_1000 | 3710.64 | 221.43 | 261.07 | 14.21× | 99% |
| text_records_50 | 1398.00 | 941.08 | 944.58 | 1.48× | 99% |
| optional_51 | 27.19 | 15.50 | 16.07 | 1.69× | 95% |
| unicode_strings | 242.43 | 262.78 | 291.53 | 0.83× | — |
| escaped_strings | 422.00 | 275.06 | 251.88 | 1.68× | 116% |
| exact_numbers_1000 | 946.97 | — | 738.93 | 1.28× | — |

“Saving retained” is `(strict time − candidate time) / (strict time − plain native time)`, not a speedup ratio. Values above100% reflect measurement variation or candidate differences; they are not a claim of reliable superiority over native defaults. The Unicode-heavy case is slower than strict under both native paths. The exact-Number fixture has no plain-native comparator because plain native parsing cannot supply the same precision.

The Float fixture was rerun after the zero-normalization correction; its table row uses that fresh three-path comparison. Other timed paths were unaffected. Dedicated raw Float rerun data is retained.

The 50-record response retains about 87% of the native time saving; the small record retains about 74%. The 10k integer array retains about 86%; decimals decoded as Float retain about 99%. Exact Number output is a separate result: about 947→739 µs,1.28× faster, because exact representation construction still has to happen. Do not cite the 14.2× Float result as an exact-Number result.

## Memory

| Fixture | Strict peak MiB | Plain native peak MiB | Deferred peak MiB |
|---|---:|---:|---:|
| small_record | 68.05 | 68.06 | 68.25 |
| response_50 | 67.88 | 67.77 | 68.12 |
| ints_10000 | 70.14 | 68.16 | 68.73 |
| ints_limit | 179.41 | 101.75 | 108.14 |
| decimals_1000 | 68.17 | 67.78 | 67.78 |
| exact_numbers_1000 | 67.91 | — | 67.64 |

The largest fixture is 262,143 zero integers in 524,287 bytes. Deferred decoding uses about 108 MiB peak whole-process RSS versus179 MiB strict and 102 MiB plain native. Small-input memory remains dominated by runtime overhead; sub-MiB differences are not meaningful improvements. The final typed values are equal. Retained/post-GC and raw timing samples are in `lossless-results.json`.

## Why not eager exact conversion?

The first experiment separately measured all four eager-stage paths. It used its own freshly rerun baseline; do not treat its samples and the second run as a single paired measurement.

| Fixture | Strict µs | Native µs | Duplicate-only µs | Eager exact µs |
|---|---:|---:|---:|---:|
| small_record | 1.78 | 0.94 | 1.15 | 1.33 |
| response_50 | 95.45 | 44.77 | 50.70 | 59.47 |
| ints_10000 | 2255.86 | 858.28 | 916.12 | 2128.87 |
| decimals_1000 | 3379.27 | 214.72 | 230.05 | 3166.10 |
| text_records_50 | 1421.17 | 929.58 | 911.54 | 952.54 |

Duplicate rejection alone is relatively inexpensive. Eager Number construction still helps ordinary records, but largely erases the gain for numeric arrays. This prototype uses number.parse for every numeric callback rather than the strict parser's small-integer shortcut; it is not a proof that every possible eager implementation has the same cost. Deferred conversion is the simpler demonstrated way to avoid doing exact decimal work when the requested output is already a rounded Float.

## Guarantees restored and remaining differences

**Restored for the supported Erlang candidate:** duplicate rejection after decoded-key comparison; exact integer storage; preservation of decimal mathematical values until projection; exact decimal-to-Int checks; exact Number output on demand; explicit Float rounding/overflow rejection. Typed callbacks run only after complete native syntax parsing and duplicate admission succeed. Existing1 MiB byte admission and typed record/presence checks remain.

**Not restored:**

- Default strict depth/value-count limits during parsing. Large integer tokens can allocate BEAM bignums before typed rejection, even when the final requested Int would fail. The byte cap remains, but is not an allocation quota.
- Global numeric token/significand/exponent admission limits in the deferred candidate. Numeric projections have their own bounds: decimal Int/Number projections use default Number limits; native-integer Number construction uses `from_int` without those parse limits. Float can round1e-1201 to0 where strict parsing rejects the exponent before projection.
- Exact source-token limit semantics. OTP normalizes numeric-hook tokens: e.g.1e2 becomes1.0e2. Eager default limits, and deferred decimal Int/Number projection limits, can therefore reject a boundary input accepted by the strict parser. Confirmed cases include800 coefficient digits followed by e0 and a1024-byte exponent token. No claim of full strict numeric-domain acceptance is made.
- Strict error ordering and byte/line/column diagnostics. A later syntax or trailing-content failure wins over a duplicate/numeric sentinel; strict parsing may have already returned the earlier admission error. Duplicate checks happen only once a member value has parsed.
- Source ordering for multiple unknown fields: native Erlang maps still control enumeration.
- Full codec integration: concrete record/list/optional fixtures are implemented, not arbitrary existing custom Value callbacks, dependent records, schemas or union combinators.

On syntactically valid duplicate-containing input, duplicate rejection is deterministic. Which error wins when the input contains multiple different defects is not the strict parser's contract. No fallback silently accepts a rounded fraction as an Int.

## OTP callback implementation detail

Throwing from hooks proved unsafe for error classification: OTP's float parsing catch can intercept an exception from a later callback and report it as an unexpected number sequence. Both prototypes instead return unforgeable-by-JSON tuple sentinels and propagate them through object/array accumulators. Parsing finishes, then returns the recorded admission error. There is no process dictionary state, second text scan or separate recursive post-parse validation walk. This preserves duplicate/number error classification on syntax-valid documents while deliberately giving syntax failures precedence.

The foreign adapters are roughly 60 lines each, plus experimental Gleam typed decoders and tests. A production implementation should share the native decoding/container machinery rather than ship copied prototype modules. It would still need integration throughout Codec; the narrow FFI does not make that work disappear.

## Verification and method

Both targets compile with warnings as errors. These mitigation adapters are Erlang-only: JavaScript returns UnsupportedRuntime; no JavaScript performance or equivalent duplicate policy is claimed. The requested preference for Erlang is reflected in the measured scope.

Tests cover ordinary/escaped-equivalent duplicate keys, duplicates after float tokens, no typed callback on malformed documents, numeric values near integer boundaries, overflow/underflow, optional/null fields, Unicode rejection, syntax precedence and normalized-token boundary differences. A deterministic 112-token probe compares exact Number, Int and Float Results with the strict decoder (336 projection comparisons), within their shared admitted domain. Gleam Result equality on this Erlang runtime detected a signed-zero mismatch. The final candidate normalizes mathematically zero coefficients to positive zero while retaining signed underflow from nonzero coefficients. Dedicated parity checks cover both. The full repository gate independently runs both-target tests and schema/number/parser oracles.

Measurement method matches the earlier native prototype: three fresh timing VMs per fixture/path, one warmup and five batches per VM, median 15 samples; three separate fresh memory processes retaining output with explicit GC; wait4 whole-process peak RSS. Fixtures compare equal typed output before timing in a separate process. OTP 29/ERTS 17.1.1 JIT, one scheduler, Gleam 1.19.2. Results are observations, never gates; data files retain samples and runtime memory details.

The full repository gate, both mitigation check suites and all 336 numeric projection comparisons passed. Production source hashes remain unchanged. See `mitigated-validation.log`.

## Recommendation

For an Erlang-first native option, use **duplicate-checking container hooks plus native integers and deferred decimal tokens**. This directly addresses the two most consequential plain-native differences while retaining most measured gains. Keep it an explicit native policy until the remaining bounds/diagnostic differences and full codec integration are accepted. Do not market it as an interchangeable strict parser. JavaScript needs a separate strategy; this result does not solve its duplicate-evidence problem.

## Reproduce

```sh
XDG_CACHE_HOME=/tmp/json-blueprint-review-nix-cache nix develop --command sh -c 'gleam build --target erlang --warnings-as-errors && gleam build --target javascript --warnings-as-errors && python3 experiment/exact_run.py && python3 experiment/lossless_run.py && BLUEPRINT_PARSER_INPUT=experiment/numeric-tokens.txt gleam run -m native_numeric_probe'
```

Use `--check-only` on either Python runner to skip benchmarks. The full gate is `nix develop --command sh scripts/gate.sh`. Evidence: `exact-results.json`, `lossless-results.json`, `numeric-tokens.txt` and `mitigated-validation.log`. No production source was modified.
