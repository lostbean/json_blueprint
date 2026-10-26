# Benchmarks

Local timing and allocation observations for the runtime contracts, the codec
paths and the schema-driven generator. They describe specific checkouts and
machines, give no guarantee for a published release or another workload, and
never gate a change. The [oracle](ORACLE.md) is the companion document for
correctness evidence. The [design](design/design.typ#repository-verification)
states the verification model, and [AGENTS.md](../AGENTS.md#references) points here.

## Scope

| Capture | Question | Decision record |
| --- | --- | --- |
| Strict and native parsing, 2026-10-25 | What do strict admission and its Value tree cost on representative and near-limit inputs? | [ADR 0003](adr/0003-strict-parsing-and-independent-resource-bounds.md), existing parser guarantees unchanged |
| Contract encoding, 2026-10-08 | What does symmetric validation in `contract.value_codec` cost on encoding? | [ADR 0010](adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md) |
| Object validation, 2026-10-08 | What does indexing objects above 40 members change? | [ADR 0009](adr/0009-index-object-validation-above-forty-members.md) |
| Schema-driven generation, 2026-10-08 | How do generated, handwritten and dynamic codecs compare, and what does generation cost? | [ADR 0008](adr/0008-development-time-source-generation.md) |
| Timed calls, 2026-09-20 | Historical baselines of the first harness | [ADR 0010](adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md) |

Summaries and provenance sit beside each capture under
[`benchmarks/`](benchmarks/) and are not markdown. A summary holds every VM
median and its range, and the schema-generation `results.json` holds every
trial, so the tables here do not depend on raw logs. Raw per-run logs and command
output are not retained in the tree; they remain in repository history at commit
`c79211d`.

## Method

- Each target (Erlang and JavaScript) starts three fresh VMs per capture. Each VM
  runs timed batches per operation after an untimed warmup. A table cell is the
  median of the three VM medians; the bracketed range is the minimum and maximum
  of the VM medians, not a confidence interval.
- Parsing, fixture construction, codec construction, contract loading, semantic
  checks and compilation are outside timed batches unless a row says otherwise.
  Every timed call sends its result to an observable sink; sink and loop cost stay
  in both sides of a comparison.
- Before and after captures run in fixed order, all baseline VMs first, with the
  same harness, runtime flags, inputs and iteration settings. Provenance manifests
  identify every measured source file by SHA-256 and retain dirty status, lockfile
  hashes and machine and runtime metadata.
- Fixture tests check values, preserve encoded text and locate invalid bounds on
  every benchmark VM before timing. Compiler and semantic evidence stay separate
  from timing observations.
- Rows that perform different work, such as an accepted encoding against a
  rejection, report no speedup ratio.

## Run it

```sh
sh scripts/benchmark.sh                       # current codegen harness on both targets
nix develop --command python3 scripts/contract_encoding_benchmark.py \
  --output .ci-results/contract-encoding-local --trials 3
nix develop --command python3 scripts/schema_generation_benchmark.py \
  --output /tmp/schema-generation-results
nix develop --command python3 scripts/parser_benchmark.py \
  --output /tmp/parser-results --trials 3
```

Every runner creates a fresh evidence directory and refuses to reuse one. The
`Benchmark observations` workflow runs `scripts/benchmark.sh` weekly and on demand
and retains the raw logs, source revision and dirty status, lockfile hashes,
runtime versions and OS and architecture for 14 days. The ordinary gate keeps the
benchmark fixtures' semantic tests and no speed ceiling.

## Environment of the 2026-10-08 captures

Four Cortex-A76 CPUs, Linux 6.18.34 on aarch64, Gleam 1.18.1, Erlang/OTP 28 (ERTS
16.4.0.6) with `+S 1:1`, and Node 24.21.0. No CPU pinning, frequency control or
host isolation; other builds and tests were paused during captures. Garbage
collection, JIT, scheduling and frequency can change end-to-end figures, so small
deltas are not causal estimates.

## Retained results

### Strict and native parsing, 2026-10-25

The [capture](benchmarks/parser-2026-10-25/) retains all 264 observations,
source and fixture hashes, commands, toolchain and host identity. It includes
the handwritten codec's symmetric plain-integer encoding repair and JavaScript
host-string Unicode check on top of revision `7875416`; the dirty source
fingerprints identify the measured implementation. The subsequent generated
integer-helper parity repair is outside these measured parser paths.

This capture used macOS 27.0.1 on arm64, Gleam 1.19.2, Erlang/OTP 29 with
`+S 1:1`, and Node 24.21.0. Each fixture/backend/target has three fresh sequential
timing processes and three separate one-parse memory processes. Timing uses one
warmup batch and five timed batches, with fewer iterations for larger inputs.
The table reports the median of the three process medians. Full ranges and
iteration counts remain in the artifacts. No CPU pinning or host isolation was
used; repository builds and tests were paused during the capture.

Both parsers receive the same text. Before timing, accepted fixtures compare
exact values after normalizing object order; rejected fixtures must fail in both
parsers. Every timed parse result reaches an observable sink. Strict parsing
returns exact `Value` trees with duplicate and resource checks. Native parsing
returns `Dynamic` through `gleam/json`, with different guarantees and
representations. These are parser observations, not typed codec or equivalent-work
comparisons. Fixture loading and semantic checks are outside the timing.

| Fixture | Erlang strict / native, µs | Node strict / native, µs |
| --- | ---: | ---: |
| Small record | 1.330 / 0.366 | 8.302 / 0.760 |
| 100-field object | 70.279 / 13.328 | 187.822 / 3.044 |
| 500-field object | 332.643 / 82.525 | 1,029.490 / 47.069 |
| 1,000 decimals | 856.100 / 139.591 | 4,239.725 / 27.683 |
| 262,143 zeroes (524,287 bytes) | 235,273.041 / 7,755.292 | 265,235.084 / 1,474.417 |
| Invalid first character, near-limit text | 0.292 / 0.375 | 2,175.125 / 8.167 |
| Invalid final value, near-limit array | 221,936.875 / 7,645.500 | 284,629.042 / 2,358.417 |

The JavaScript strict text path validates host-string scalar values and converts
to UTF-8 before syntax parsing. An early syntax error therefore still incurs
whole-input work. The 10-field object, 10,000-element array and escaped-Unicode
cases are also retained in the summary.

Memory processes invoke only the selected parser once, retaining its result.
`wait4` records each process's high-water RSS, converted to bytes according to
the operating system's units. This is **total process RSS**, including the VM,
source and result; it is neither allocation nor isolated parser heap. No baseline
subtraction is performed.

| Fixture / target | Strict peak RSS, MiB | Native peak RSS, MiB |
| --- | ---: | ---: |
| Null / Erlang | 66.77 | 67.19 |
| Null / Node | 49.78 | 49.64 |
| Near-limit zero array / Erlang | 163.42 | 88.62 |
| Near-limit zero array / Node | 241.73 | 54.16 |

The near-limit case demonstrates substantial latency and memory costs even for
half a MiB of text. Limits bound admission, not acceptable service latency or
concurrency. The capture does not establish a consumer capacity budget, browser
behavior, or that strict and native parsing are interchangeable. It supports
further optimization work and explicit workload budgets, not a speed claim or
a change to parser policy.

### Contract encoding, 2026-10-08

`contract.value_codec` returned its supplied `Value` unchecked during encoding.
The changed adapter validates against the contract first. The baseline is commit
`1003904cd9962ffd5eeb4f5b8ccabc60dd51d451`. Complete-text encoding of valid input,
µs per operation:

| Workload | Erlang before → after | Node before → after |
| --- | ---: | ---: |
| String scalar | 0.217 → 0.251 | 0.687 → 1.173 |
| Six-field record, one bounded integer | 4.371 → 5.771 | 3.234 → 14.561 |
| Closed object, 100 string fields | 63.671 → 342.254 | 42.128 → 1,954.414 |
| Closed object, 500 string fields | 322.217 → 7,021.016 | 210.169 → 46,961.214 |
| 10,000 integers, each bounded | 1,483.533 → 2,151.877 | 3,935.678 → 12,415.492 |
| `AnySchema`, array of 10,000 strings | 2,769.455 → 2,712.282 | 2,346.616 → 2,337.759 |
| Typed Order control | 9.097 → 7.786 | 26.405 → 26.003 |
| Generated Order control | 3.968 → 3.665 | 10.642 → 10.389 |

- Wide closed objects pay the most: the contract validator scans lists for allowed
  names, duplicates and property lookup. Runtime validation is not negligible
  because a schema has no numeric refinements.
- The typed and generated controls run unchanged code; their shift between captures
  is measured variation, not an optimization from the adapter change.
- Validating 1,000 records and then encoding costs `validate_then_encode_json` 1.16×
  on Erlang and 1.76× on Node against validating once and calling `value.to_string`
  (0.99× and 1.00×), which is the existing one-validation path.
- Rejecting a 1,000-integer array at index 0 or 999 differs in work from a
  successful encoding, so no ratio is given (Erlang 0.169 µs first, 58.111 µs last).

### Object validation, 2026-10-08

Runtime contracts use string-specific searches for small objects and a temporary
dictionary above 40 input members; a direct check of the first 32 members rejects
early name failures before the dictionary. The baseline is commit
`b3d894000c9bb814cc4b95932fc2fb7e61f1964e`. µs per operation:

| Public task | Erlang before → after | Node before → after |
| --- | ---: | ---: |
| Six-field native record | 1.45 → 1.36 | 11.47 → 6.37 |
| 100-field object | 280.41 → 69.55 | 1,909.65 → 210.28 |
| 500-field object | 6,763.64 → 369.66 | 53,468.94 → 1,099.52 |
| 500-field object with JSON rendering | 7,333.90 → 685.88 | 48,526.41 → 1,473.39 |
| 1,000 native records | 1,583.33 → 1,262.46 | 13,323.03 → 7,279.01 |
| Typed Order control | 1.32 → 1.31 | 35.56 → 28.39 |

- The 40-member cutoff is an internal CPU and allocation compromise, not an
  admission limit. It is not optimal for every workload: the earlier cutoff
  comparison traded roughly 10–13% BEAM CPU at 39–40 fields for lower allocation.
- Indexing allocates more than the improved linear search for wide valid objects,
  and lower allocation per call does not establish lower peak memory. An earlier
  mixed workload observed aggregate worker-memory peaks of about 6.6 MiB for the
  previous index and 10.0 MiB for the approved prototype with 16 BEAM workers; the
  sibling-workspace artifacts that report cited are no longer retained.
- The change passed 244 Erlang and 243 Node root tests, and a replay of 58,936
  inputs per runtime matched the baseline's outcomes.

### Schema-driven generation, 2026-10-08

Generated native `Order` codecs (G) against a handwritten public-combinator codec
(H) and a runtime contract over prebuilt `Value` (D). Native conversion constructs
the requested representation; the dynamic path validates an existing `Value`, so D
measures different work. µs per operation, 100 items:

| Target | encode_value G / H / D | decode_value G / H / D | encode_text G / H / D |
| --- | ---: | ---: | ---: |
| Erlang | 135.05 / 134.39 / 86.06 | 94.50 / 93.86 / 86.12 | 1000.53 / 1007.44 / 955.16 |
| JavaScript | 1882.75 / 1830.32 / 1417.81 | 1685.96 / 1716.20 / 1411.65 | 5333.37 / 5157.31 / 4611.60 |

| Target | Codec construction | Time µs | Allocated KiB |
| --- | --- | ---: | ---: |
| Erlang | generated / handwritten / dynamic | 3.842 / 2.128 / 0.051 | 6.492 / 5.859 / 0.219 |
| JavaScript | generated / handwritten / dynamic | 66.378 / 55.842 / 0.362 | 26.660 / 23.653 / 0.563 |

- Generated and handwritten encoding cost the same at 100 items; one-item records
  show larger relative differences (3.56 against 2.94 µs on Erlang), which do not
  establish parity. Generation supplies types and maintained source, not speed.
- Pure source generation takes a median 0.332 ms per module on Erlang and 0.820 ms
  on Node (200 generations per VM after 20 warmups).
- Allocation uses separate VMs from CPU timing: Erlang reports `call_memory`
  process-heap allocation including memory later collected, Node a sampled
  managed-heap estimate. Neither is RSS, a concurrent peak or total process memory.
- No live service, upstream oracle, full conformance or concurrency test is claimed.
  The interrupted first capture is excluded; the final capture starts after the
  implementation was frozen.

### Timed calls recorded on 2026-09-20

The first harness ran 200 untimed warmup calls and timed 1,000 calls in one
interval; the reported mean is the integer quotient of elapsed nanoseconds. It
recorded no distribution, hardware, OS, compiler version or raw output, and later
parser, codec and API changes prevent treating the figures as current baselines.
The retired report for that run named starting commit
`cf378926647ed83dc0669f49d4bb8591b5e1381f`; the figures below are the only
retained record of it.

| Workload | Unit | Erlang/OTP 28 | Node 24.15.0 |
| --- | --- | ---: | ---: |
| `number_parse_canonical_7_token_batch` | ns per seven-token batch | 2,247 | 17,712 |
| `parser_document_admission` | ns per parsed document | 9,847 | 41,057 |
| `runtime_contract_validation` | ns per validated value | 295 | 4,450 |
| `codec_encode_decode_roundtrip` | ns per `Value` encode and decode pair | 346 | 6,581 |

### Historical memory observations

Recorded for `value.parse` at the defaults (README of commit
[`94438b9`](https://github.com/lostbean/json_blueprint/blob/94438b93b638a2ecf2e4443bd9c2c3cbf97b7713/README.md#defaults),
implementation change dated 2026-10-02). Erlang figures are peak process heap with
old and new heaps counted together at garbage-collection events; Node figures are
heap growth. They are different measurements.

| Input at the defaults | Text | Peak heap, OTP 28 | Parsed value, OTP 28 | Heap growth, Node 24 |
| --- | --- | ---: | ---: | ---: |
| 262,143 integers (the value limit) | 512 KiB | 42 MB | 16 MB | about 120 MB |
| 262,143 strings | 1 MiB | 40 MB | 16 MB | about 75 MB |
| 87,001 small objects | 680 KiB | 32 MB | 13 MB | about 75 MB |
| 61,001 fifteen-digit decimals | 1 MiB | 16 MB | 6 MB | about 80 MB |

With the value limit raised, 1 MiB of 524,288 integers peaked at an 80 MB Erlang
heap by the same method. The record has no retained command, run date, sample
count, hardware or raw allocation trace, and the `MB` convention was not recorded.
Parser limits are admission bounds, not heap quotas.

## Limits of these claims

- Three fresh VMs identify large differences and variation; they do not establish
  tail latency, capacity, browser behavior or concurrency.
- A timing observation is never an acceptance test. Behavior is judged by the
  [oracle](ORACLE.md) and the package gate.
- To reconstruct a baseline, use an isolated checkout of the baseline commit, copy
  the retained harness and runner into their current paths and apply
  [the formatting-only runner patch](benchmarks/contract-encoding-2026-10-08/before/runner-formatting.patch).


## Strict string-scanning optimization, 2026-10-25

This behavior-preserving pass keeps the strict Value parser. It scans ordinary
string bytes in pairs and avoids chunk-list construction and concatenation for
unescaped strings. Escape decoding, exact numbers, duplicate-key admission,
resource limits, error locations and copied-string ownership are unchanged.
There is no new FFI, dependency, parsing mode or public API.

The existing parser harness now accepts `--workloads representative`. Its seven
fixtures cover a small record, a response containing 50 records, a tagged event,
plain/escaped/multilingual text, and a schema-shaped document. They are synthetic
application-shaped inputs, not a measured production distribution. The default
`stress` workload remains unchanged. This measures parsing into Value, not
end-to-end application decoding or encoding.

```sh
nix develop --command python3 scripts/parser_benchmark.py \
  --workloads representative --output /tmp/parser-observation
```

The capture used Gleam 1.19.2, OTP 29 and Node 24.21.0 on macOS arm64. Each
backend/fixture/mode used three fresh sequential VMs; timing used a warmup batch
and five timed batches. Peak RSS came from separate one-parse processes with the
result retained. It includes the runtime and input and is not an allocation or
retained-heap measurement. The installed Git binary was placed on PATH because
the system Git shim was unavailable inside this machine's Nix shell.

The [before](benchmarks/parser-optimization-2026-10-25/before/summary.json) and
[final](benchmarks/parser-optimization-2026-10-25/after/summary.json) captures give
these strict-parser medians, in microseconds:

| Workload | Erlang before | Erlang after | JavaScript before | JavaScript after |
| --- | ---: | ---: | ---: | ---: |
| `record` | 6.48 | 6.80 | 28.45 | 25.57 |
| `response_50` | 277.92 | 295.11 | 1244.07 | 1094.74 |
| `tagged_event` | 9.64 | 9.53 | 39.38 | 35.12 |
| `text_plain` | 90.57 | 70.84 | 517.57 | 311.81 |
| `text_escaped` | 137.19 | 121.46 | 732.00 | 597.59 |
| `text_unicode` | 52.89 | 46.16 | 318.52 | 198.61 |
| `schema_document` | 11.69 | 11.82 | 49.11 | 41.23 |

Text-heavy gains were repeatable across captures. Small Erlang record results
were variable: this final sequential capture is slower for the record and
50-record response, while the alternating capture improved the record and left
the response close to baseline. Do not claim a reliable Erlang record speedup.
The [alternating results](benchmarks/parser-optimization-2026-10-25/alternating/summary.json)
rotate baseline, four-byte (`batched`) and selected two-byte (`pair`) variants
between fresh VMs to reduce ordering bias. The two-byte variant avoids the
four-byte variant's observed wide-object regression. Its source differs from the
final file only in the scanner comment. Timing remains observational, never a
correctness gate.

In the separate [memory stress comparison](benchmarks/parser-optimization-2026-10-25/memory.json),
the dense 262,143-zero array stayed at approximately 165 MiB total peak RSS on
Erlang and 242 MiB on JavaScript. The heavily escaped fixture was also effectively
unchanged. This optimization does not resolve the memory cost of large Value
trees. Representative fixture RSS differences were small.

Erlang `eprof` and Node CPU profiles identified string scanning, byte-array slices
and string assembly as relevant costs. For the same record profiling run,
`scan_string` calls fell from 351,117 to 207,069, and the 48,016 concatenation calls
for unescaped strings disappeared. Node's plain-text profile decreased from 623
to 369 samples, with `bitArraySlice` samples falling from 445 to 226. These are
instrumented diagnostics, not independent speed or allocation estimates.
[Profile summaries](benchmarks/parser-optimization-2026-10-25/javascript-profiles.json)
and the [raw profiles, source snapshots, rerun scripts and validation log](benchmarks/parser-optimization-2026-10-25/profile-and-source-evidence.zip)
retain the evidence. Early captures used the same harness before formatting;
the exact measured harness is in the archive.

Rejected variants included four-byte scanning, index-based scanning, and a narrow
JavaScript run-scanning FFI with a Gleam fallback. Some improved long JavaScript
text more, but introduced Erlang regressions or extra maintained code. Skipping
unescaped-string assembly alone had little clear benefit; combined with two-byte
scanning it is retained as a small reduction in per-string allocation.

Validation: 301 root tests on each target, generated-code and schema consumers,
compiled examples, the finite schema and profile oracles, 62 independent number
cases, and all 318 JSONTestSuite plus 901 generated parser cases on each target
passed through `sh scripts/gate.sh` in the Nix shell. Added tests compare parsed
values and exact failure locations across varying string lengths, UTF-8 text,
escapes and literal controls through both text and byte entry points. The
existing input-retention tests remain in the gate. See [ORACLE.md](ORACLE.md) for
the limits of the correctness claims.

## Native Erlang adoption (2026-10-25)

At this capture, the production adapter adopted OTP parsing with duplicate rejection, exact
native integers and deferred decimal tokens. Built-in codecs decode the native
tree directly; custom callbacks convert their Value subtree. Admission is byte
limited. JavaScript still retained its exact parser with byte-only admission and
a runtime-capacity error boundary. The later JavaScript hybrid capture below
supersedes that implementation choice.

A fresh comparison against the frozen optimized-parser worktree used three
separate VM timing and memory trials per workload. Source hashes stayed unchanged.
The integrated adapter includes copies of escaping strings and object keys to
avoid retaining unrelated input bytes. [Raw measurements](../experiment/adoption-results.json)
include toolchain versions, source and input hashes, all samples and memory snapshots.

Erlang small records improved from 2.07 to 1.25 µs and 50-record responses from
99.13 to 55.88 µs. The 262,143-integer fixture improved from 235.95 to 41.34 ms;
peak RSS decreased from 178.94 to 127.88 MiB (about 29%). Small-document peak RSS
was essentially unchanged. Decimal-to-Float arrays improved 12.91×; exact Number
arrays improved 1.24×. These are different projection workloads.

JavaScript small records changed from 10.54 to 11.28 µs, responses from 383.21
to 387.25 µs, and 10,000 integers from 10.20 to 10.02 ms. This does not establish
a broad JavaScript gain. RSS includes the complete runtime and is not retained
JSON allocation. Timings and memory observations never gate a change.

The [adoption report](NATIVE-DECODING-ADOPTION.md) records the complete comparison,
accepted behavior changes, consumer consequences and release checks. The
[independent oracle](ORACLE.md) remains separate from these performance observations.

## JavaScript native hybrid adoption, 2026-10-25

This capture supersedes the earlier JavaScript byte-only-parser measurements
for the native hybrid path. It compares baseline commit `2c6df61` with the
final native-only source (portable fallback removed), identified by full source and harness hashes in the
[raw results](benchmarks/javascript-hybrid-2026-10-25/results-native-only.json).

Node 24.21.0, Gleam 1.19.2, macOS arm64. Six fresh timing VMs per
candidate/workload, rotating candidate order; five timed batches per VM. Separate
fresh processes measure peak RSS and forced-GC retained heap. All 17 fixture
parity checks pass, 43 rows complete, and source/support hashes are unchanged.
There is no CPU affinity/frequency control. These application-shaped fixtures
are not an observed production traffic distribution.

| Workload | Previous parser (µs) | Native-only hybrid (µs) | Speedup | Peak RSS MiB: previous → hybrid |
| --- | ---: | ---: | ---: | ---: |
| Small record | 10.78 | 5.71 | 1.89× | 53.04 → 52.89 |
| 50-record response | 392.33 | 162.45 | 2.42× | 54.06 → 53.01 |
| 51 optional-field records | 107.50 | 69.42 | 1.55× | 53.15 → 53.09 |
| 10,000 integers | 10,365.17 | 4,376.79 | 2.37× | 63.31 → 56.64 |
| 262,143 integers | 319,978.23 | 162,570.42 | 1.97× | 263.22 → 103.41 |
| 1,000 decimals → Float | 5,235.10 | 602.41 | 8.69× | 58.88 → 53.44 |
| 1,000 decimals → exact Number | 4,289.06 | 2,800.63 | 1.53× | 58.82 → 56.22 |
| Unicode strings | 1,058.46 | 124.00 | 8.54× | 55.41 → 53.26 |
| 50 text-heavy records | 6,411.73 | 1,102.98 | 5.81× | 56.32 → 54.23 |
| Whole Value: 262,143 integers | 271,636.77 | 292,551.33 | 0.93× | 243.77 → 258.89 |
| Custom callback: response | 382.40 | 287.50 | 1.33× | 53.91 → 53.13 |

The large typed array lowers peak RSS about 61%, while retained heap after GC
stays around 16.4 MiB in both variants. The gain is transient allocation, not a
smaller returned list. Small-record process RSS is dominated by Node. The large
whole-Value array is about 8% slower and uses about 6% more peak RSS in this
capture; do not generalize direct typed-decoding gains to whole-Value consumers.

The native-only hybrid small-record/response results (5.71/162.45 µs) remain
close to the earlier prototype (5.52/157.47 µs) and the first adoption capture
with fallback retained (5.72/164.07 µs). Dense typed peak RSS is 103.41 MiB versus
103.46/104.86 MiB in those earlier captures. These are separate captures, not a
controlled causal comparison of the cleanup. Removing the fallback simplifies
maintenance without claiming another performance gain. The final runtime has
188 fewer source lines than baseline, including its new 233-line JS adapter.
The [previous adoption capture](benchmarks/javascript-hybrid-2026-10-25/results.json)
is retained with its own source hashes for provenance.

Reproduce with `nix develop --command python3 experiment/js-hybrid-benchmark.py
--work /tmp/blueprint-js-hybrid-fresh --output /tmp/blueprint-js-hybrid-fresh.json`
(on one shell line). The harness snapshots the baseline commit and current
source, checks native feature selection, and refuses stale snapshots or existing
output. Plain native rows lack strict guarantees and are only a cost reference.

[ADR 0015](adr/0015-adopt-javascript-native-hybrid.md) owns the decision;
[the migration guide](MIGRATION.md) describes diagnostic changes and
[browser validation](BROWSER-SUPPORT.md) records executed engines.
