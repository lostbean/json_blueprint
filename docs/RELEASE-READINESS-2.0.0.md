# JSON Blueprint 2.0.0 release-readiness review

## Current assessment — 2026-10-26

The specialized generated-code adoption is locally validated and has no known
unresolved correctness blocker in the reviewed paths. This is a release
candidate with a successful local package preview. No release or tag has been cut.

- Full repository gate: 382 Erlang and 387 JavaScript root tests; 24 example
  tests and 10 generated-consumer tests per target; fresh generated compilation,
  isolated production compilation, and all independent oracles pass.
- Host formatting, README snippet synchronization and rendered design checks
  pass. Browser execution evidence for the JavaScript hybrid is retained in
  [BROWSER-SUPPORT.md](BROWSER-SUPPORT.md); the subsequent generated-code change
  has been executed on Erlang and Node, not rerun in browsers.
- Local `gleam export hex-tarball` and `gleam docs build` pass. The package
  contains runtime/generator source and both FFI targets, excludes tests and
  experiment evidence, and the generated documentation includes the migration
  page. The manifest declares MIT, but no root license text is present; add
  the appropriate license file as release packaging cleanup.
- Runtime/generated parity tests cover strict duplicate admission, numeric
  projection, Unicode, byte limits, located errors, optional fields and mapping
  conversions. Pure mappings are required: cached metadata skips placeholder
  introspection. Generated objects cannot finish record-builder continuations.
  These limits and migration details are in [MIGRATION.md](MIGRATION.md).
- The [adoption benchmarks](benchmarks/generated-specialization-2026-10-26/REPORT.md)
  retain the prototype's runtime and memory gains with direct source emission.

Before publication, validate the exact committed candidate in CI, then update
llm_wire to that candidate, reconcile all
affected manifests through Gleam, and rerun its full gate. At this review its
root dependency and manifest still pin `2c6df6148c9357b03041be2c95a3a46a6694120d`,
before the JavaScript hybrid, added oracles and generated-code adoption.
The older downstream gate below therefore does not certify this candidate.

Further parser rewrites, removal of the frozen legacy API, and removal of
explicit Value/standard-native generated APIs are not release prerequisites.
Historical experiment evidence can be consolidated later without deleting
referenced provenance. Installation text should switch from prerelease Git
instructions to Hex only after publication succeeds.

## Historical correction review — 2026-10-25

The remainder records the earlier snapshot. Its test counts, downstream evidence
and browser-scope statements are historical; the assessment above supersedes
them for the current candidate.

Review and correction date: 2026-10-25. Initial production revision: `ce233eed218e5bc7a68e171a23c60075c2a389a7` (native implementation `909ceb74864898082bf0c6323bb9b3a3af8346ab`). The follow-up repairs the reviewed correctness defects and retains the verification evidence; no release is cut.

## Current status after corrections

Both correctness findings below are repaired in this changeset. Duplicate declarations now reject during the existing encode/decode traversals using a record-local dictionary, including absent optional fields; valid callback ordering is preserved without an extra placeholder traversal. JavaScript standalone number parsing preserves exact supported exponents and explicitly refuses unsupported written/normalized exponents or comparison magnitudes. Erlang retains exact arithmetic without extra integer-to-string validation work.

The stale native-decoding, byte-limit, symbolic-oracle and JavaScript capacity descriptions are corrected. The design PDF was rerendered and passed the design gate. A focused visual inspection of changed pages 14, 16 and 23 plus neighbors 13, 15, 17, 22 and 24 found no clipping or readability defect; this is not a complete presentation audit.

Final verification on the fixed source:

- Blueprint full gate: 320 Erlang and 324 JavaScript tests; 24 example tests and 10 generated-consumer tests per target; 85 schema cases, 50 profile fixtures, 62 arithmetic cases and 318 upstream plus 1,179 generated parser cases per target all pass.
- Host formatting check (`nix flake check`) and design render/check pass. Other operating-system Nix checks were not run.
- llm_wire full gate passes against an isolated path override to the fixed Blueprint source: 403 tests, external consumers, TLS/H2 cancellation and concurrency through 1,000 callers. Root and nested scratch manifests were reconciled through Gleam; original consumer pins remain unchanged. Source hashes remained unchanged during the gate.
- Independent subagent review finds no unresolved correctness blocker in the changed paths and associated documentation. Its JavaScript differential probe covers 3,280 numeric cases (1,078 exact acceptances and 2,202 correct refusals), with zero mismatches. It also checks all optional-encoding presence combinations and valid continuation/getter ordering.
- The [post-fix benchmark report](../experiment/correctness-report.md) and [raw capture](../experiment/correctness-final-results.json) supersede the earlier final-source timings. All 73 comparisons pass equality preflight; source hashes remain unchanged during measurement.

Evidence: [Blueprint gate](../experiment/final-review-evidence/correctness-full-gate.log), [format check](../experiment/final-review-evidence/correctness-flake-check.log), [design check](../experiment/final-review-evidence/correctness-design-check.log), [llm_wire gate](../experiment/final-review-evidence/correctness-llm-wire-gate.log), [downstream provenance](../experiment/final-review-evidence/correctness-llm-wire-provenance.json), [numeric differential](../experiment/final-review-evidence/numeric-differential-final.json), [callback review](../experiment/final-review-evidence/record-callbacks-final.json), [source hashes](../experiment/final-review-evidence/correctness-source-hashes.json).

The [paired standalone-number and wide-record measurements](../experiment/correctness-number-final-report.md) quantify the remaining correction cost: Erlang records with 20/100 fields take about 4/25 additional microseconds, while JavaScript standalone number parsing adds about 0.2–0.3 microseconds. This is an explicit performance trade-off, not a correctness blocker. The first list-based repair had substantially higher wide-record cost and was replaced before final verification.

The original blockers are resolved. Browser execution, exhaustive conformance and universal resource guarantees remain outside the evidence. This report records verification before Git integration; the repository history and consumer manifests identify the integrated commits. Consumers must pin a commit containing these repairs before release. Version remains 2.0.0; no release or tag has been created.

## Initial review retained for provenance

The remainder describes the pre-fix snapshot and its original findings. Its hold verdict and measurements are superseded by the correction status above.

## Verdict

Hold the release for two confirmed correctness defects and a small documentation correction set. The independent parser evidence is substantially stronger, and no native-parser correctness regression was confirmed in the inspected paths. Passing gates do not negate the reproduced defects below.

## Adherence

The accepted byte-only policy, native Erlang parsing, exact supported numeric values, duplicate-key rejection and JavaScript host-string validation are implemented. Frozen legacy root/schema modules are unchanged by native adoption. This is not proof of exhaustive equivalence with published 1.7.1.

**P2: explicit number parsing silently rounds extreme exponents on JavaScript.** With `number.limits(100, 100, 9_007_199_254_740_991)`, the mathematically equal tokens `1e-9007199254740991`, `1.00e-9007199254740991` and `100e-9007199254740993` should produce equal Numbers or an explicit representation refusal. JavaScript instead accepts all three and gives the last two exponent `-9007199254740990`. Erlang returns the correct exponent `-9007199254740991` for all three.

Two operations contribute to the same defect: `src/json/blueprint/number.gleam:356` uses an unsafe intermediate during normalization; `:883` permits unsafe exponent accumulation when headroom exceeds JavaScript's exact integer range. Merely regrouping the subtraction/addition does not fix the second case. The supplied limit is itself a safe JavaScript integer, and the input is valid JSON number syntax. Ordinary default limits are unaffected. The newer JSON token admission path uses different checks; this finding concerns the public standalone `number.parse` API and values/bounds constructed with it.

Recommended cure: `(in-place-fix, now)`. Check exponent accumulation and normalization against target representation limits, or return an explicit refusal instead of silently rounding. Add cross-target equality/refusal regressions for both spellings. Preserve the independent resource-limit behavior of explicit parsing.

Evidence: [normalization reproducer](../experiment/final-review-evidence/exponent-normalization.gleam.txt), [normalization output](../experiment/final-review-evidence/exponent-normalization.log), [accumulation reproducer](../experiment/final-review-evidence/exponent-accumulation.gleam.txt), [accumulation output](../experiment/final-review-evidence/exponent-accumulation.log).

**P2: duplicate record definitions can bypass first-use validation and accept an extra field.** The count-only success paths at `src/json/blueprint/codec.gleam:1326` and `:1342` return before `fields.names()` checks uniqueness. Define two fields both named `x`, then decode `{"x":1,"extra":2}`. On Erlang and JavaScript, both `codec.decode_json` and `codec.decode(Value)` return `Ok(#(1, 1))`, although `codec.check` returns `DuplicateFieldName("x")`.

The module documentation promises failure when a mistaken definition is first used; the design also promises closed records. This defect requires an invalid codec definition, so it does not demonstrate an unknown-field bypass for a correctly defined codec. It predates native adoption and affects both decoding paths. Existing duplicate-record coverage tests encoding, leaving this decoding case uncovered.

Recommended cure: `(in-place-fix, now)`. Check definition uniqueness independently of input-member count, with regressions on both targets. Preserve continuation invocation and error ordering. Do not blindly add placeholder traversal to every decode: it can introduce work and callback changes. Until repaired, callers can use `codec.check` at startup to reject this definition. Repeat record benchmarks after the correction, since the current measurements include this fast path.

[Reproducer](../experiment/final-review-evidence/duplicate-definition.gleam.txt) and [observed output](../experiment/final-review-evidence/duplicate-definition.log).

**P2: design descriptions still contradict the adopted architecture.**

- `docs/design/contracts/design.typ:167` says strict text parsing produces Value first. Erlang built-in codecs now decode the native tree directly.
- `docs/COVERAGE.md:11` still names independent limits and cites ADR 0003; it should identify byte-only admission under ADR 0014 and explicitly cover the native adapter/FFI.
- `docs/design/contracts/design.typ:386` still describes the parser differential oracle as using Python Decimal. It now uses symbolic normalized coefficients/exponents, including values beyond Decimal's representation.

Recommended cure: `(design-change, now)`. Correct these descriptions and rerender/check the design. The structural design gate passed previously; it does not detect this semantic drift. This review inspected semantic documentation, not every rendered page for presentation quality.

## Spec

The requested parser improvements are now independently exercised:

- All 318 pinned upstream JSONTestSuite parsing fixtures run on both targets. Original bytes, archive hash and fixture identity are checked; upstream must-reject cases cannot silently become accepted.
- 1,179 deterministic generated/differential cases run per target, adding 278 boundary cases in this review. They cover literal/escaped controls, Unicode scalar boundaries, malformed UTF-8 in names and values, equivalent escaped duplicate names, bytewise truncation, precision-sensitive and large numbers, deep/wide malformed inputs and no-crash outcomes.
- Python's JSON decoder supplies independent grammar judgment, with explicit duplicate/scalar-string policy and symbolic exact decimal comparison. The package is not its own semantic oracle.
- Every one of the 2,048 unpaired UTF-16 units is checked in names and values through `value.parse` and `codec.decode_json`: 8,192 rejection checks. Valid surrogate pairs and literal U+FFFD remain accepted. Invalid UTF-8 wire bytes are tested separately.

The quoted raw-surrogate replacement bug was already fixed before this review. The new exhaustive boundary checks strengthen that evidence; no production change was needed to obtain rejection. Byte admission precedes host-scalar validation, and valid UTF-8 wire input is distinct from malformed JavaScript host strings.

Deliberate differences remain explicit: duplicate names reject even where the upstream corpus permits them; malformed scalar escapes reject; Erlang reports native syntax diagnostics; JavaScript's numeric representation and runtime capacity can refuse extreme inputs. These are finite, reproducible checks, not a proof of universal no-crash behavior, continuous fuzzing maturity or general JSON Schema conformance.

## Standards

The full repository gate passes after the evidence additions: warnings-as-errors builds, 314 Erlang and 318 JavaScript unit tests, executed examples, generated-code consumers, 85 schema/decoder/contract cases, 50 schema-profile fixtures, 62 independent arithmetic cases and the expanded parser corpus. Version remains 2.0.0; no release or tag is created.

The retained llm_wire integration pins the implementation commit in both root and nested manifests. Its full gate passed during integration, including 403 tests, external consumers, TLS/HTTP2 cancellation and concurrency through 1,000 callers. This turn does not rerun that unchanged consumer gate or change its dependency pins.

No additional standing-rule violation was identified in the reviewed implementation. The semantic documentation issues above remain separate from mechanical formatting/gate outcomes.

## Craft and runtime coverage

Reviewed paths include native parsing callbacks, duplicate propagation, number normalization/projection, built-in record/list/union decoding, custom Value fallback, continuation ordering, frozen legacy surfaces and generated entry points. Targeted native-versus-Value numeric probes agree for precision-sensitive decimals, enormous signed exponents, signed underflow and overflow boundaries. `1.00000000000000001` still fails integer decoding.

OTP 29 and Node 24 are covered by the full gate. A separate clean package build on installed OTP 27.3.4.18 / ERTS 15.2.7.13 passes warnings-as-errors compilation and 313 pre-expansion unit tests; the final expanded parser corpus also passes on OTP 27. Its recorded source/oracle/corpus hashes match this review. This verifies that patch release, not every OTP 27 version or the original 27.0 release. Browser JavaScript was not executed.

Evidence: [full gate](../experiment/final-review-evidence/full-gate.log), [host-string checks](../experiment/final-review-evidence/host-string-tests.log), [parser oracle](../experiment/final-review-evidence/parser-oracle.log), [OTP 27 corpus](../experiment/final-review-evidence/otp27-oracle.log), [OTP 27 provenance](../experiment/final-review-evidence/otp27-provenance.json).

## Final benchmark conclusions

The [fresh benchmark report](../experiment/final-report.md) compares the frozen optimized strict parser, plain-native prototype, mitigated-native prototype and final implementation in balanced fresh-VM trials. All 73 workload/variant/target rows pass equality preflight; production source hashes remain unchanged.

For the requested Erlang response/10k-integer/Float-decimal/exact-Number workloads, final medians are 57.32 / 1,121.07 / 267.24 / 798.20 microseconds, compared with mitigated prototype 53.71 / 1,115.91 / 246.35 / 768.45. Final retains 77.9% of plain-native time saving for responses and 98.6% for Float decimals. It is substantially faster than the strict baseline on these workloads, but the mitigated prototype is cheaper on several paths. Text-heavy and Unicode workloads favor the final adapter over the prototypes.

For the 512 KiB dense typed array, final peak RSS is 127.48 MiB versus 179.20 strict and 107.86 mitigated. Retained process memory after GC stays approximately 6.36 MiB. Whole-Value parsing is faster but its dense-array peak rises from 162.99 to 169.23 MiB. JavaScript shows no broad improvement; its dense typed-array peak remains about 263 MiB. These are whole-process peaks, not memory allocated or retained by a few-kilobyte response.

The measurements apply to the current implementation before the two proposed fixes. Repeat affected record/numeric measurements after fixing them; do not assume the current fast path's figures certify the corrected release.

## Migration and performance boundaries

The migration guide already covers native object ordering, unavailable Erlang syntax locations, removed global limits, explicit byte limits, exact versus native numeric projection, optional-field distinctions, wire envelopes and finite-schema restrictions. JavaScript capacity wording should also mention unusually long numeric tokens, not only deep input: `(design-change, now)`.

Whole-Value parsing is a separate performance path. llm_wire classification and tool boundaries call `value.parse` before validation/decoding, so direct typed-codec speedups cannot be attributed to those paths. The final benchmark includes both operations and compares current implementations in the same capture; historical prototype figures remain secondary.

No new native JavaScript parser, recursive-schema support, broader schema profile, legacy deprecation or release publication is implied by this work.
