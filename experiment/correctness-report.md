# Benchmarks after the correctness fixes — 2026-10-25

The fixed implementation retains the native Erlang runtime and typed-array memory gains. JavaScript remains close to the optimized strict parser. These measurements follow the duplicate-record-definition and exact-exponent repairs; they replace the earlier final-source measurements for this working tree. No release was cut.

## Method and provenance

The unchanged [capture harness](final-benchmark.py) and [runner](final-runner.gleam) compare the frozen strict parser, plain and mitigated native prototypes, and a snapshot of the fixed working source. All 73 rows passed result-equality preflight. Source hashes were verified unchanged throughout capture. [Raw results](correctness-final-results.json) retain hashes, versions, fixture sizes, trial medians and peak RSS. Tests/builds were stopped during capture. The harness rotates variant order and uses separate fresh VMs for timing and memory.

The previous final-source column comes from the earlier capture, not an interleaved pre/post experiment; host variation and overlapping trial ranges prevent attributing every difference to the fix. The supplemental paired benchmark separately measures the changed standalone number and record paths.

## Erlang typed decoding

Microseconds; median of VM medians. Plain native is not equivalent for arbitrary duplicate keys or exact numbers.

| Workload | Strict, fresh | Plain native | Mitigated | Before fixes, earlier capture | Fixed |
| --- | ---: | ---: | ---: | ---: | ---: |
| small_record | 1.90 | 0.94 | 1.27 | 1.68 | 1.26 |
| response_50 | 95.77 | 45.17 | 52.12 | 57.32 | 58.30 |
| ints_10000 | 2,160.84 | 818.03 | 1,079.21 | 1,121.07 | 1,055.56 |
| ints_262143 | 219,365.56 | 26,340.29 | 32,201.25 | 42,265.71 | 41,228.81 |
| decimals_float_1000 | 3,310.77 | 219.14 | 239.44 | 267.24 | 248.27 |
| decimals_exact_1000 | 925.49 | Not equivalent | 713.60 | 798.20 | 762.19 |
| optional_51 | 27.15 | 14.17 | 16.48 | 18.21 | 17.63 |
| unicode_strings | 231.84 | 293.94 | 296.12 | 153.17 | 137.28 |
| text_records_50 | 1,400.77 | 878.50 | 899.31 | 218.94 | 223.00 |

## JavaScript typed decoding

| Workload | Strict, fresh | Before fixes, earlier capture | Fixed |
| --- | ---: | ---: | ---: |
| small_record | 9.94 | 11.87 | 10.61 |
| response_50 | 360.69 | 374.16 | 379.23 |
| ints_10000 | 9,166.33 | 10,213.88 | 9,278.83 |
| ints_262143 | 305,635.56 | 323,099.38 | 306,653.21 |
| decimals_float_1000 | 5,065.89 | 5,561.71 | 4,913.29 |
| decimals_exact_1000 | 4,240.33 | 4,465.36 | 4,149.35 |
| optional_51 | 104.10 | 108.12 | 105.27 |
| unicode_strings | 988.49 | 1,046.88 | 1,007.41 |
| text_records_50 | 6,184.73 | 6,189.42 | 6,287.21 |

## Memory and whole-Value parsing

Peak RSS is whole-process memory, including runtime, input, result and intermediates. It is not the retained allocation size of the result. The dense array is 524,287 bytes, not a few kilobytes. Small-response RSS remains approximately 68 MiB on Erlang and 54 MiB on Node.

| Target / operation | Strict peak MiB | Fixed peak MiB | Strict µs | Fixed µs |
| --- | ---: | ---: | ---: | ---: |
| erlang / ints_262143 | 179.29 | 127.38 | 219,365.56 | 41,228.81 |
| erlang / value_response_50 | 66.97 | 67.36 | 71.41 | 47.12 |
| erlang / value_ints_262143 | 162.79 | 168.84 | 226,929.02 | 40,210.40 |
| erlang / value_decimals_exact_1000 | 67.27 | 67.86 | 891.84 | 759.30 |
| javascript / ints_262143 | 262.83 | 263.05 | 305,635.56 | 306,653.21 |
| javascript / value_response_50 | 53.52 | 53.52 | 264.72 | 258.34 |
| javascript / value_ints_262143 | 243.49 | 243.25 | 256,832.00 | 270,899.83 |
| javascript / value_decimals_exact_1000 | 60.40 | 59.38 | 4,174.03 | 3,961.06 |

Erlang dense typed-array peak remains about 127 MiB versus 179 MiB strict and 108 MiB mitigated prototype. Whole-Value parsing, used by llm_wire boundaries, is much faster on Erlang but retains a slightly higher peak than strict (about 169 versus 163 MiB). Do not attribute typed-codec memory savings to those consumer paths. JavaScript shows no broad runtime or memory gain.

## Paired measurements of the changed paths

The [standalone-number and wide-record report](correctness-number-final-report.md) compares the pre-fix implementation and final source in alternating fresh VMs. Erlang 20/100-field records rise from 13.15/57.70 to 17.49/82.51 µs; JavaScript rises from 63.84/697.94 to 66.89/701.53 µs. These quantify the cost of checking every declaration, including omitted optional fields. The dictionary implementation removes the first repair’s quadratic seen-list scan but does not remove all validation cost. JavaScript standalone number parsing adds about 0.2–0.3 µs; Erlang differences are small and mixed.

The earlier [list-based repair capture](correctness-results.json) is retained as intermediate evidence, not the final implementation.

## Reproduction

```sh
nix develop --command python3 experiment/final-benchmark.py \
  --work /tmp/blueprint-correctness-benchmark-new \
  --output /tmp/blueprint-correctness-results-new.json
```

Timing is observational, never a gate. Browser execution and exhaustive parser conformance are outside this evidence.
