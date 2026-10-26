# Final implementation versus parser prototypes — 2026-10-25

The final Erlang implementation preserves most of the measured native time savings on the quoted response and decimal workloads, but it is not identical in cost to the minimal mitigated prototype. Its large typed-array peak is about 128 MiB rather than the prototype’s 108 MiB. The whole-Value path used by consumers such as `llm_wire` has a different memory result: the dense-array peak is slightly higher than the old strict parser. JavaScript shows no broad final-versus-strict improvement.

This is a fresh comparison at production revision `ce233eed218e5bc7a68e171a23c60075c2a389a7`. It does not splice old and new measurements into one trial. The frozen optimized strict source matches all 19 source hashes in the preceding adoption capture; the plain and mitigated prototypes use that frozen package and their archived source. Final decoding uses a separate snapshot of the production source. No production code was modified.

## Fresh Erlang typed-decoding comparison

All timings are microseconds, medians of fresh-VM medians. Each variant produces identical codec-encoded result text for each admitted fixture before timing; the exact Number row has no equivalent plain-native comparator. These fixtures do not make the plain-native path equivalent for arbitrary JSON.

| Workload | Optimized strict | Plain native prototype | Mitigated native prototype | Final | Strict / final |
| --- | ---: | ---: | ---: | ---: | ---: |
| Small record (44 bytes) | 1.86 | 0.96 | 1.31 | 1.68 | 1.10× |
| Response with 50 records (2,301 bytes) | 94.86 | 46.64 | 53.71 | 57.32 | 1.66× |
| 10,000 integers (20,001 bytes) | 2,199.70 | 857.75 | 1,115.91 | 1,121.07 | 1.96× |
| 262,143 integers (524,287 bytes) | 234,985.19 | 29,492.77 | 34,246.40 | 42,265.71 | 5.56× |
| 1,000 decimals → Float | 3,431.17 | 220.82 | 246.35 | 267.24 | 12.84× |
| 1,000 decimals → exact Number | 961.34 | Not equivalent | 768.45 | 798.20 | 1.20× |
| 51 optional-field records | 27.14 | 15.96 | 16.68 | 18.21 | 1.49× |
| Unicode strings | 251.57 | 297.71 | 297.56 | 153.17 | 1.64× |
| 50 text-heavy records | 1,459.35 | 950.83 | 914.79 | 218.94 | 6.67× |

The tiny-record strict VM medians span 1.817–2.574 µs and final medians 1.474–1.787 µs. The final median is only about 1.10× faster in this capture, versus 1.65× in the preceding capture. Response, array and string workloads should carry more weight than that tiny absolute difference. No CPU frequency or host isolation was controlled.

The final text-heavy and Unicode paths are faster than both prototypes. “Plain native” here includes the prototype’s handwritten typed adapter; it is not the bare OTP parser or a universal speed ceiling. One relevant implementation difference is that the prototype string decoder uses `decode.string`, which validates through `bit_array.to_string`, while the final adapter copies an already parser-validated binary. This difference is visible in source; this benchmark does not isolate its causal share of the gain.

## How much native time saving survives?

For a workload where plain native is faster, retained saving is `(strict − candidate) / (strict − plain native)`. This describes the saving against the same fresh strict/native pair, not candidate speed as a percentage of native speed.

| Erlang workload | Mitigated prototype retains | Final retains | Final versus mitigated time |
| --- | ---: | ---: | ---: |
| Response with 50 records (2,301 bytes) | 85.3% | 77.9% | +6.7% |
| 10,000 integers (20,001 bytes) | 80.8% | 80.4% | +0.5% |
| 1,000 decimals → Float | 99.2% | 98.6% | +8.5% |
| 262,143 integers (524,287 bytes) | 97.7% | 93.8% | +23.4% |

The user-quoted response figures (96 / 46 / 53 µs) imply roughly 86% retention from their rounded numbers; the previous report’s 87% used its underlying measurements. Fresh response retention is about 85% for the prototype and 78% for final. For Float decimals, final retains about 98.6%, close to the historical prototype’s 99%.

## Historical figures versus this fresh capture

| Erlang workload | Quoted historical strict / plain / mitigated, µs | Fresh strict / plain / mitigated, µs | Fresh final, µs |
| --- | ---: | ---: | ---: |
| Response with 50 records (2,301 bytes) | 96 / 46 / 53 | 94.86 / 46.64 / 53.71 | 57.32 |
| 10,000 integers (20,001 bytes) | 2,309 / 883 / 1,088 | 2,199.70 / 857.75 / 1,115.91 | 1,121.07 |
| 1,000 decimals → Float | 3,711 / 221 / 261 | 3,431.17 / 220.82 / 246.35 | 267.24 |
| 1,000 decimals → exact Number | 947 / N/A / 739 | 961.34 / N/A / 768.45 | 798.20 |

The differences between dates/runs are observations, not regressions by themselves. The common runner was extended for output-equality preflight and whole-Value measurements and now routes all candidates through the same decode/consume closure structure; its source hash differs from the historical runner. These harness differences especially matter for microsecond-sized records. The interleaved fresh candidate comparison is the basis for the conclusions here. Historical underlying measurements remain in [MITIGATION.md](MITIGATION.md) and its raw captures.

## Memory: distinguish peak from retained process memory

The dense fixture is **524,287 bytes (approximately 512 KiB)**, not a few-kilobyte ordinary response. Peak RSS includes the complete VM, loaded code, input, intermediates and result. Small Erlang documents already start around 68 MiB total RSS; that is not memory allocated by a tiny JSON record.

| Erlang typed dense array | Peak RSS, MiB | Process memory after GC, MiB |
| --- | ---: | ---: |
| strict | 179.20 | 6.36 |
| plain_native | 102.14 | 6.36 |
| mitigated_native | 107.86 | 6.36 |
| final | 127.48 | 6.36 |

Final peak RSS is **28.9% lower than strict**, but **18.2% higher than the mitigated prototype**. The post-GC process snapshot is effectively unchanged because each path retains the same typed list. That snapshot is process memory, not an exact measurement of the result’s allocated bytes. The final implementation copies escaping strings/keys and implements the complete codec API; these costs differ from the prototype. We have not isolated a single cause for the dense-array peak difference.

For the ordinary 50-record response, peak RSS is 67.83 / 67.77 / 68.05 / 67.95 MiB across strict/plain/mitigated/final—essentially unchanged. Do not extrapolate the dense-array memory saving to small records.

## Whole-Value parsing: the relevant distinction for llm_wire

`codec.decode_json` avoids the intermediate Value tree for built-in codecs. `value.parse` still returns a full Value tree. Consumers that parse Value before validation/typed decoding do not get the same allocation result. These measurements isolate `value.parse`; they are not end-to-end HTTP, schema validation or `llm_wire` call latency. Results are compared after normalizing object order outside timing.

| Target / Value workload | Strict, µs | Final, µs | Speedup | Strict peak RSS, MiB | Final peak RSS, MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| erlang: Response with 50 records (2,301 bytes) | 74.32 | 50.53 | 1.47× | 67.58 | 67.63 |
| erlang: 262,143 integers (524,287 bytes) | 242,595.81 | 44,341.40 | 5.47× | 162.99 | 169.23 |
| erlang: 1,000 decimals → exact Number | 953.17 | 810.17 | 1.18× | 67.55 | 67.86 |
| javascript: Response with 50 records (2,301 bytes) | 261.85 | 259.29 | 1.01× | 53.48 | 53.62 |
| javascript: 262,143 integers (524,287 bytes) | 266,552.15 | 263,163.12 | 1.01× | 243.35 | 243.41 |
| javascript: 1,000 decimals → exact Number | 4,242.78 | 4,125.95 | 1.03× | 60.55 | 59.38 |

**The Erlang dense Value-tree peak increases about 3.8%: 162.99 → 169.23 MiB**, despite parsing about 5.47× faster. Post-GC process memory remains approximately 22.77 MiB on both sides. This is the strongest reason not to claim blanket memory reductions for the current `llm_wire` path. The ordinary Value response parses about 1.47× faster with no material peak-RSS change.

## JavaScript typed decoding

The final JavaScript path retains the exact package parser. The plain-native prototype uses `JSON.parse` and has weaker duplicate/number guarantees; there is no JavaScript mitigated-native prototype.

| Workload | Optimized strict, µs | Plain native prototype, µs | Final, µs | Final versus strict time |
| --- | ---: | ---: | ---: | ---: |
| Small record (44 bytes) | 10.74 | 3.47 | 11.87 | +10.5% |
| Response with 50 records (2,301 bytes) | 377.73 | 83.43 | 374.16 | -0.9% |
| 10,000 integers (20,001 bytes) | 10,617.01 | 1,078.94 | 10,213.88 | -3.8% |
| 262,143 integers (524,287 bytes) | 331,953.50 | 34,263.69 | 323,099.38 | -2.7% |
| 1,000 decimals → Float | 5,553.56 | 173.66 | 5,561.71 | +0.1% |
| 1,000 decimals → exact Number | 4,569.78 | Not equivalent | 4,465.36 | -2.3% |
| 51 optional-field records | 108.44 | 49.87 | 108.12 | -0.3% |
| Unicode strings | 1,014.49 | 96.76 | 1,046.88 | +3.2% |
| 50 text-heavy records | 6,214.83 | 674.10 | 6,189.42 | -0.4% |

There is no broad final-versus-strict JavaScript speedup. The small-record median is about 10.5% slower; its VM ranges overlap in this capture (strict 10.257–11.041 µs, final 10.479–12.470 µs). Response and larger-array ranges also overlap. Do not attribute the tiny-record difference to one implementation detail without a separate profile.

For the JavaScript typed dense array, peak RSS is 263.34 MiB strict, 84.76 MiB plain native and 262.95 MiB final. The final path therefore does not deliver the Erlang memory improvement. JavaScript Value parsing is similarly unchanged at roughly 243 MiB peak on this stress fixture. These costs remain relevant when choosing an application byte allowance.

## Reproduction, coverage and limits

- Toolchain: macOS arm64, Gleam 1.19.2, OTP 29 / ERTS 17.1.1 with `+S 1:1`, Node 24.21.0 with `--expose-gc`, Python 3.14.7.
- Each fixture/variant has four or six fresh timing VMs and the same number of separate memory VMs. Trial counts round up to full rotations of candidate order so each candidate occupies each ordering position equally. Each timing VM runs one warmup batch and five timed batches; batch counts match input size and remain in the raw artifact.
- Input loading, compilation, codec construction and equality checks are outside timed batches. Every decode result reaches an observable sink. Memory retains that result and forces GC for the process snapshot; child `wait4` provides peak RSS. Other repository builds and tests were paused during capture. Host OS activity, CPU frequency and affinity were not controlled.
- All 73 variant/workload/target rows passed their output equality preflight. Source hashes were verified unchanged before/after capture. Exact Number has no plain-native comparator; malformed/duplicate input is not timed. Parser correctness is covered separately by the independent oracle and boundary tests.
- This does not benchmark browser engines, OTP 27 performance, concurrent parser throughput, arbitrary custom codecs, rejection latency, schema validation or end-to-end `llm_wire`. Timing never gates a release.

Artifacts: [raw trials and provenance](final-results.json), [capture harness](final-benchmark.py), [common runner](final-runner.gleam), and [frozen strict source](final-strict-source.zip). The archived prototypes remain under [prototypes/](prototypes/).

Run a complete new capture from the repository in a fresh disposable work directory; use a new output path so historical results remain immutable:

```sh
nix develop --command python3 experiment/final-benchmark.py \
  --work /tmp/blueprint-final-benchmark-new \
  --output /tmp/blueprint-final-results-new.json
```

The script reconstructs both packages, compiles both targets, checks fixture equality, and performs the capture. The checked-in harness/runner bytes are the bytes used for this report; do not reformat them without preserving the capture copies identified by the raw hashes.
