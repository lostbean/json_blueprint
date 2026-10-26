# THROWAWAY: JavaScript native hybrid evaluation

Date: 2026-10-25 (America/Sao_Paulo). Baseline: `2c6df6148c9357b03041be2c95a3a46a6694120d`. Prototype is confined to the separate `javascript-hybrid-parser` worktree. Main branches, dependency pins, version and release state are unchanged.

## Question and answer

Can native JavaScript parsing with a strict scanner and direct typed projection preserve the adopted Erlang admission guarantees while materially improving ordinary JavaScript workloads and memory?

**Yes for the exercised guarantees and built-in typed workloads.** The hybrid improves ordinary small records and 50-record responses by about 2×, with larger gains for text and Float arrays. The large typed-array peak falls about 61%. Whole-Value parsing does not uniformly improve: the dense-array case has no demonstrated runtime or memory benefit. This is a promising implementation direction, not a production-ready drop-in replacement or a general conformance proof.

## Architecture

1. Apply the existing byte bound and validate raw JavaScript string scalars.
2. Run native `JSON.parse` with a reviver. Safe lexical integers stay native numbers; other numeric tokens retain their source text and rounded native value. The existing JavaScript exponent/magnitude representation domain is checked without eagerly constructing every exact Number.
3. Scan the syntax-valid original source for decoded duplicate names and malformed escaped surrogate pairs. Keep one key set per open object; do not build a second tree or implement JSON grammar. This catches members overwritten by native parsing and strings in fields a codec never requests.
4. Decode built-in codecs from the native tree. Materialize Value only for public Value parsing or custom callback subtrees. Pure conversion capacity guards remain outside user callbacks.

The native parser still constructs a complete JavaScript tree. This is not streaming or one-pass typed parsing. Native syntax and reviver allocations happen before duplicate rejection, unlike an early duplicate hook in OTP.

## Runtime and memory

Fresh paired/rotating processes on Node 24.21.0, Gleam 1.19.2, macOS arm64. Six timing VMs per candidate/workload, five batches per VM, and separate fresh memory VMs. All 17 fixture equality preflights and 43 measured rows completed; source and harness hashes remained unchanged. Tests and builds were stopped during timing. These fixtures represent application shapes, not an observed production traffic distribution.

Microseconds per decode, median of VM medians:

| Workload | Current parser | Hybrid | Speedup |
| --- | ---: | ---: | ---: |
| Small record | 11.30 | 5.52 | 2.05× |
| 50-record response | 372.14 | 157.47 | 2.36× |
| 51 optional-field records | 105.05 | 68.55 | 1.53× |
| Unicode strings | 1,005.52 | 120.09 | 8.37× |
| 50 text-heavy records | 6,213.21 | 1,013.00 | 6.13× |
| 10,000 integers | 9,203.55 | 4,234.15 | 2.17× |
| 262,143 integers (512 KiB input) | 306,391.50 | 144,148.17 | 2.13× |
| 1,000 decimals → Float | 4,897.02 | 588.93 | 8.32× |
| 1,000 decimals → exact Number | 4,123.83 | 2,631.29 | 1.57× |
| Whole Value: 50-record response | 262.10 | 165.41 | 1.58× |
| Whole Value: dense array | 259,663.40 | 270,999.73 | 0.96× |
| Custom subtree fallback: response | 368.21 | 284.43 | 1.29× |

The plain-native prototype is a weaker-semantics reference, not an equivalent alternative. For the 50-record response, hybrid retains approximately 73% of the plain-native time saving. Reviver/scanner overhead remains material; this experiment does not isolate each phase's causal cost.

| Memory case | Current peak RSS | Hybrid peak RSS |
| --- | ---: | ---: |
| 50-record response | 53.78 MiB | 53.27 MiB |
| Dense typed array | 263.17 MiB | 103.46 MiB |
| Dense whole-Value array | 243.76 MiB | 246.82 MiB |

Peak RSS includes Node, input, result and transient allocations; it is not the result's size. The dense typed result's retained heap after GC is approximately 16.4 MiB in both variants (about 10 MiB above the pre-decode heap). The main saving is transient allocation. Small-response RSS is dominated by the approximately 53 MiB runtime baseline. Whole-Value dense timing ranges overlap, and its peak/retained memory show no benefit. Custom fallback and consumers such as llm_wire must be evaluated by the subtrees they materialize, not assigned the built-in typed-array gain.

[Detailed benchmark report](js-hybrid-benchmark-report.md), [raw results and hashes](js-hybrid-results.json), [benchmark harness](js-hybrid-benchmark.py).

## Guarantees and compatibility

Independent review found no unresolved correctness blocker in the exercised paths:

- 8,327 public adversarial checks pass, including raw/escaped Unicode, decoded duplicate names, special object keys, numeric boundaries, byte admission, closed/optional records, callback ordering, capacity and user exceptions.
- 5,904 independent BigInt numeric-admission cases pass with zero value failures or disagreements with the existing kernel.
- 318 JSONTestSuite plus 1,179 generated cases pass acceptance and exact-value checks. There are 26 classified Unicode-escape-to-native-syntax diagnostic differences.
- The original JavaScript suite passes 313 tests with 11 classified compatibility failures on the native path. Nine concern diagnostics/locations, one assumes native support is unavailable, and one expects capacity instead of native syntax rejection for deeply malformed input. The unchanged suite passes all 324 tests when source-context support is removed to exercise the portable fallback.
- Both-target warnings-as-errors compilation, 320 Erlang tests, 24 examples per target, 10 generated-consumer tests per target, 85 schema cases, 50 profile fixtures, 62 arithmetic cases and the 1,497-case Erlang parser corpus pass. The remaining-gate command deliberately excluded the separately classified JavaScript root suite and used the separately reviewed JavaScript corpus; this is not an all-green unmodified full gate.

Three defects discovered during the experiment were repaired before measurement: an unsupported-runtime internal call could throw; UTF-8 conversion stripped a BOM; projection exhaustion was mislabeled invalid number syntax. Final evidence is in the [independent review](js-hybrid-review-report.md) and [remaining gate log](js-hybrid-remaining-gate.log).

The shared guarantees are byte admission, duplicate rejection, scalar-valid strings, exact numeric evidence until projection, deliberate Float rounding and syntax-before-user-callbacks. JavaScript retains its safe-integer and exact exponent/magnitude representation limits; it does not acquire BEAM's arbitrary-integer domain. Unsupported native features fall back to the current strict parser.

Adoption changes observable JavaScript behavior: precise source locations disappear on the native path; syntax categories and multiply-invalid error precedence change; native Object.keys reorders integer-like keys, so Value rendering and unknown-field selection may differ. These resemble Erlang's native boundary but do not guarantee identical ordering across targets. Fallback was simulated on Node, not certified on browser engines. No claim of universal no-crash behavior or complete JSON/schema conformance is made.

## Complexity and recommendation

The prototype changes four runtime source files: a new 233-line JavaScript adapter plus 117 net Gleam lines in native/value/codec, approximately 350 net lines total. The scanner owns duplicate names and escaped Unicode, not JSON grammar. Roughly 35 lines duplicate the exact-number kernel's representation-admission calculation to avoid constructing Numbers for Float-only decoding. Capacity error propagation and feature fallback require additional integration code.

This is **more code to maintain today**, because the portable parser remains for older runtimes. It avoids a new schema planning engine or a full handwritten JavaScript JSON parser, but adds a second JavaScript path, an admission calculation that must stay aligned with the kernel, scanner tests and runtime feature coverage.

I recommend pursuing this hybrid for built-in JavaScript codecs: normal-workload gains and lower transient memory are substantial enough to justify this bounded extra implementation. Do not adopt it as an invisible replacement. Production work should explicitly accept the JavaScript diagnostic/order migration, decide the supported runtime/fallback policy, retain the new regressions and oracle checks, and check actual supported browser engines. Keep the whole-Value limitation visible; this experiment rules out claiming a universal memory improvement or zero maintenance cost.

## Reproduce

From this prototype worktree, with no competing test/build jobs:

```sh
nix develop --command python3 experiment/js-hybrid-benchmark.py \
  --work /tmp/blueprint-js-hybrid-new \
  --output /tmp/blueprint-js-hybrid-new.json
```

The single command builds isolated baseline and hybrid packages, checks equivalent outputs and native-path selection, then captures timing and memory. The review report supplies the independent correctness commands. New artifacts are marked THROWAWAY. No merge, commit, dependency update, tag or release was made by this experiment.
