# Native decoding adoption: both targets

**Historical Erlang-adoption snapshot.** The JavaScript decision below is superseded by [ADR 0015](adr/0015-adopt-javascript-native-hybrid.md); see the current [migration guide](MIGRATION.md) and [benchmarks](BENCHMARKS.md). Commit pins and verification counts below describe this earlier integration, not the latest checkout.

Status at capture: integrated on 2026-10-25. Production benchmarks and both repositories' full gates pass. The frozen legacy API stays available; 2.0.0 remains the selected release-preparation version. No release or tag has been cut.

## Decision and scope

Adopt native Erlang JSON parsing with direct typed decoding for built-in codecs. Keep duplicate-key rejection and exact numbers. Replace global depth, value-count and numeric-token admission limits with a configurable byte limit, defaulting to 1 MiB. Consumers own additional policies for their decoded data.

On JavaScript, retain the package parser for now, with the same byte-only admission policy. This preserves duplicate detection and exact numbers. It does **not** adopt `JSON.parse`, and no native JavaScript speedup is promised. Choosing native JavaScript parsing later requires a separate decision about duplicate detection, exact-number support and supported runtimes.

## What each target does

| Aspect | Erlang | JavaScript |
| --- | --- | --- |
| JSON grammar | OTP native `json:decode/3` | Existing package parser |
| Default byte allowance | 1 MiB; configurable | 1 MiB; configurable |
| Depth/value-count admission caps | Removed | Removed |
| Global token/digit/exponent admission caps | Removed | Removed; exact exponent still needs a safe native representation |
| Duplicate names | Rejected by OTP object hooks, including escaped-equivalent names | Rejected by the existing parser |
| Integers | Native arbitrary-precision integers until projection | Exact Number representation until projection |
| Decimals | Token retained until a codec requests Float, Int or Number | Exact Number created while parsing |
| Built-in typed codecs | Decode the native tree directly | Decode the Value tree |
| Custom Value callback | Convert the required subtree to Value | Receives existing Value subtree |
| Parsed object order | Native map order | Source order |
| Syntax errors | Generic native syntax reason; source position unavailable | Existing detailed syntax reason/location |
| Extreme nesting | Subject to host capacity | Host stack exhaustion becomes RuntimeCapacityExceeded |

The Erlang native JSON API is available from OTP 27; current local verification uses OTP 29. See the [OTP JSON documentation](https://www.erlang.org/doc/apps/stdlib/json.html#decode/3). Older OTP support is not established by these tests. Browser JavaScript is also not covered by Node tests.

## Runtime architecture

The Erlang path is:

1. Check input byte size before parser tree allocation.
2. Parse the complete document using OTP. Object hooks detect duplicates; numeric hooks retain decimal tokens instead of rounding them.
3. Decode the native tree using the codec's built-in operations. Field continuations, mappings and tagged-union constructors keep their typed behavior and field/index paths.
4. Convert a subtree to Value only when a custom callback or a Value codec needs it.

This is direct decoding **from a native tree**, not streaming token-to-typed decoding. OTP still builds a complete native document. Full syntax admission finishes before typed callbacks run.

`value.parse` remains a Value-producing API. On Erlang it parses natively and then converts the whole tree. It does not obtain the principal allocation saving of built-in `codec.decode_json`. Consumers that parse into Value and subsequently call `codec.decode` should not assume the direct-decoding benchmark gains apply to their path.

## Expected benefits

- Erlang grammar scanning and string/number recognition move to the maintained OTP implementation.
- Ordinary records, lists and response envelopes avoid the intermediate Value wrappers and most exact Number allocations.
- Float arrays avoid constructing and normalizing exact decimals only to convert them immediately to Float.
- Exact-number users retain exact mathematical values; native speed does not require silently rounding decimals or large integers.
- Removing inline admission bookkeeping reduces work and public configuration. This also avoids the extra validation pass required by the guarded-native prototype. Callers choose a byte allowance rather than coordinating four independent budgets.
- Custom codecs, schema-aware runtime contracts and the frozen legacy API remain available.

The existing Draft 2020-12 finite schema profile is unchanged. Native parsing does not add recursive schemas or broader keyword support, and removing admission limits is not a claim of general JSON Schema conformance.

## Expected costs and behavior changes

### Resource policy

A byte limit is neither a heap quota nor a CPU deadline. Deep trees, many small values, very large integers and unusually long exponents can still be expensive. A consumer can inspect decoded structure to apply business or protocol policy, but this happens **after allocation**. It cannot retroactively prevent parser allocation. Transport byte limits, process isolation and execution budgets remain application responsibilities when needed.

JavaScript's parser and some numeric routines are recursive. Removing configured depth and numeric limits exposes host stack capacity for deep trees and unusually long tokens; exhaustion returns a distinct runtime-capacity error rather than crashing or claiming the document is malformed. This is a platform limitation, not a replacement configurable depth cap.

### Ordering and diagnostics

Erlang parsed objects no longer preserve textual member order. This can affect re-rendered JSON, custom callbacks that inspect member lists, and which unknown field is reported first when several are present. JSON object semantics and schema acceptance rules are unchanged, but ordered Value equality is observably different.

Erlang native syntax errors and duplicate errors do not retain the old byte/line/column location. Unknown locations use zeroes and descriptions omit a fictitious source position. Malformed JSON containing duplicate keys can also produce a different first error because native syntax validation completes before a stored duplicate failure is returned. Typed field/index error paths remain meaningful.

### Numeric behavior

Global numeric admission caps disappear; numeric projection contracts do not. `codec.int()` retains its 24-digit policy and JavaScript safe-integer requirement. Float decoding deliberately rounds and rejects overflow. Exact `codec.number()` remains the choice for decimal precision. The explicit standalone `number.parse(token, limits)` API still lets a caller request numeric limits.

JavaScript cannot represent arbitrary exponent integers exactly. Unsupported exponent representation is rejected rather than rounded. Erlang can represent larger exponents, so extreme inputs can have different target acceptance even though ordinary numeric behavior agrees.

### Maintenance and memory

This adoption reduces Erlang parser ownership, but **does not reduce total implementation code immediately**. JavaScript still needs the existing parser, and codecs now have native and Value decoding paths. Regression tests must keep those paths aligned. A later native JavaScript adapter or a simpler shared representation could reduce this duplication; neither is included in this change.

Native strings can be slices of the input binary. The integration copies strings and object keys that escape through native accessors so a retained small field/error does not keep an unrelated large JSON body alive. This has a copying cost, which must be included in production benchmarks.

Custom Value callbacks and exact Number-heavy workloads retain conversion costs. Their gains should be smaller, and some whole-Value workloads can have higher transient allocation because both native and Value trees exist during conversion.

## Performance evidence and its limits

Fresh production measurements compare the integrated adapter (including source-string/key copying) against a frozen snapshot of the optimized strict parser. Toolchain: Gleam 1.19.2, Erlang/OTP 29 (ERTS 17.1.1), Node 24.21.0. Each workload used three fresh VM timing trials and separate memory trials. Source hashes were verified unchanged across capture. See [raw results and provenance](../experiment/adoption-results.json) and the [measurement report](../experiment/adoption-report.md).

| Erlang workload | Optimized strict | Production native | Speedup | Peak RSS: old → new |
| --- | ---: | ---: | ---: | ---: |
| Small record, 44 bytes | 2.07 µs | 1.25 µs | 1.65× | 67.86 → 67.83 MiB |
| Response containing 50 records, 2.3 KiB | 99.13 µs | 55.88 µs | 1.77× | 67.92 → 68.05 MiB |
| 10,000 integers, 20 KiB | 2.23 ms | 1.16 ms | 1.92× | 69.59 → 68.91 MiB |
| 1,000 decimals decoded as Float | 3.48 ms | 0.269 ms | 12.91× | 67.75 → 68.03 MiB |
| 1,000 decimals decoded as exact Number | 0.962 ms | 0.773 ms | 1.24× | 67.86 → 68.27 MiB |
| 262,143 integers, 512 KiB | 235.95 ms | 41.34 ms | 5.71× | 178.94 → 127.88 MiB |

The ordinary record/response gains are real in this local sample; the recommendation does not depend on the especially favorable decimal-to-Float workload. Small-document total memory is essentially unchanged because the VM baseline dominates. For the large integer array, total peak RSS drops about **29%**, not the roughly 40% seen in the earlier minimal prototype. Retained Erlang process memory after garbage collection stays at approximately **6.36 MiB** on both paths: the returned typed list is the same size. The saving is in transient parsing work. The production measurement supersedes that prototype expectation.

| JavaScript workload | Optimized strict | Production byte-only parser | Change | Peak RSS: old → new |
| --- | ---: | ---: | ---: | ---: |
| Small record | 10.54 µs | 11.28 µs | About 7% slower | 52.75 → 53.11 MiB |
| Response containing 50 records | 383.21 µs | 387.25 µs | About 1% slower | 53.80 → 54.42 MiB |
| 10,000 integers | 10.20 ms | 10.02 ms | About 2% faster | 63.31 → 63.02 MiB |

JavaScript shows no broad performance improvement. The small-record regression costs about 0.74 µs in this sample; removing counters does not guarantee a win once runtime-capacity handling and changed execution paths are included. The larger two differences are small enough that they should not drive architecture decisions.

RSS includes the VM and supporting runtime, **not just live JSON objects**. It must not be described as the input alone allocating that amount of retained memory. These local observations are not an SLA or a guaranteed memory ceiling. The evidence is finite: it does not establish whole-Value parsing performance, every custom callback, browser behavior or all possible adversarial input. The benchmark's separate retained-process observations and per-VM timing ranges are in the raw artifact.

## Implementation and release plan

1. Implement byte-only admission and remove obsolete setters/error variants. Preserve explicit number parsing limits and native projection checks.
2. Integrate native Erlang parsing and direct built-in codec decoding, with selective Value conversion for custom callbacks. Keep JavaScript's exact parser and handle host capacity failures explicitly.
3. Update tests and documentation for the accepted ordering, diagnostics and resource-policy changes. Add regressions for duplicate keys, exact numbers, callbacks, long tokens, deep/wide documents and input-binary retention.
4. Run warnings-as-errors builds, both-target tests, compiled examples, generated-code consumers and independent parser/schema/number oracles.
5. Benchmark the production path against a frozen optimized-parser snapshot on both targets. Include ordinary records/envelopes as well as numeric arrays; report memory separately from timing.
6. Prepare the llm_wire migration against a temporary local dependency. Its classification tests that inherited Blueprint limits must change; this adoption does not add replacement structural checks there. Existing llm_wire-owned provider/transcription bounds remain separate and unchanged. Publish an authored patch and validation evidence without moving its Git pin to an unpublished worktree.
7. Review the evidence before release. Preserve the frozen legacy API and 2.0.0 release preparation; adopting this implementation does not itself publish a release.

## Verification status

The full repository gate passes: Erlang and JavaScript warnings-as-errors builds and tests, compiled examples, generated-code consumers, all 85 schema/decoder/contract cases, 50 schema-profile fixtures, 62 independent exact-number cases, and 318 upstream plus 901 generated parser cases on each target. The parser oracle uses symbolic exact decimal comparison for huge exponents. Design rendering and validation both pass. Independent implementation review found and fixed source-binary retention and inefficient exponent construction; no remaining correctness issue was identified within the stated contract.

Fresh production benchmarking is complete, with unchanged source hashes verified.

The `llm_wire` migration is committed as `33a732fd956cfbe90c8324e262d0c3b18ac06df7`. Repository integration pins `llm_wire` and its nested consumer to Blueprint commit `909ceb74864898082bf0c6323bb9b3a3af8346ab` through their Git dependency declarations and Gleam-reconciled manifests. The real consumer migration passes its full gate: 403 Gleam tests, 3 Python tests, fresh external API-boundary consumers, native compilation, local TLS/HTTP2 stream cancellation, and concurrency checks through 1,000 callers with no failures. Existing separately owned provider/transcription guards remain unchanged. The earlier [prepared patch](../experiment/llm-wire-byte-admission.patch) and [temporary validation details](../experiment/llm-wire-byte-admission.md) remain historical evidence.

Blueprint's implementation is integrated on `main`. The frozen legacy API remains available. Version 2.0.0 remains the selected release-preparation version; no release or tag has been cut.

## Recommendation

Proceed with the Erlang-first adoption. It preserves duplicate rejection, exact supported numeric values, closed typed contracts and callback ordering while simplifying admission policy and removing costly intermediate allocations for ordinary typed decoding. Treat JavaScript as a deliberately different implementation with the same common-case contract, not as a completed native-parser migration. Judge the release on production measurements and consumer compatibility rather than the best decimal-array result.
