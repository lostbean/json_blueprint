# JavaScript hybrid benchmark — 2026-10-25

THROWAWAY experiment. Question: does native JavaScript parsing plus strict admission and direct typed decoding reduce runtime and memory compared with the current portable parser?

## Answer

Yes for the measured built-in typed codecs and ordinary records. The small record is about 2.05× faster and the 50-record response 2.36× faster. The dense typed integer array is 2.13× faster with 60.7% lower peak process RSS. Decimal-to-Float and Unicode workloads show larger gains. Whole-Value and custom-callback paths retain less benefit; the dense whole-Value array has no demonstrated time or memory improvement.

These results support the hybrid as a performance candidate, not automatic adoption. They do not demonstrate that native parsing alone supplies the strict guarantees; the scanner, exact-token adapter and independent correctness evidence remain necessary. The plain-native comparator is deliberately weaker on duplicate names and precision.

## Method and provenance

Capture UTC: `2026-10-26T01:05:33.073819+00:00`. Baseline: `2c6df6148c9357b03041be2c95a3a46a6694120d`. The hybrid is a snapshot of the uncommitted prototype worktree. [Raw results](js-hybrid-results.json) retain every source and harness hash, environment, input/result hash, batch sample and process-memory observation.

- Node v24.21.0, Gleam gleam 1.19.2, macOS arm64; no CPU affinity or frequency control.
- Six fresh timing VMs and six separate fresh memory VMs per implementation/workload. Implementation order rotates across trials. Each timing VM warms up, then measures five batches.
- Codec construction, input-file loading, compilation and equality checks are outside timing. Results escape into an observable sink.
- All 17 fixtures pass current-versus-hybrid result equality; the nine applicable plain-native references also agree on these particular inputs. Whole-Value equality normalizes object order, because source order is deliberately outside the native guarantee.
- The current snapshot reports native support false; the hybrid reports true. Capture asserts these flags so a portable fallback cannot silently be measured as the hybrid.
- All 43 timing/memory rows completed, and source/support hashes were verified unchanged afterward. Other gate and benchmark jobs were stopped during capture.
- Peak RSS comes from wait4 for each fresh process. GC runs before and after one decode for heap observations; the result is retained. Heap deltas may include lazy runtime allocations and are not exact object sizes.

## Built-in typed decoding

Microseconds, median of six VM medians. “Speedup” is current divided by hybrid.

| Workload | Current | Hybrid | Speedup | Plain native, weaker guarantees |
| --- | ---: | ---: | ---: | ---: |
| Small record (44 bytes) | 11.30 | 5.52 | 2.05× | 3.36 |
| Response with 50 records (2,301 bytes) | 372.14 | 157.47 | 2.36× | 78.96 |
| 10,000 integers | 9,203.55 | 4,234.15 | 2.17× | 1,041.51 |
| 262,143 integers (512 KiB) | 306,391.50 | 144,148.17 | 2.13× | 33,667.27 |
| 1,000 decimals → Float | 4,897.02 | 588.93 | 8.32× | 169.69 |
| 1,000 decimals → exact Number | 4,123.83 | 2,631.29 | 1.57× | Not equivalent |
| 51 optional-field records | 105.05 | 68.55 | 1.53× | 48.66 |
| Unicode strings | 1,005.52 | 120.09 | 8.37× | 85.59 |
| 50 text-heavy records | 6,213.21 | 1,013.00 | 6.13× | 687.44 |
| Nested arrays | 337.77 | 176.82 | 1.91× | 48.37 |

For the response, the hybrid retains 73.2% of the time saved by the plain-native reference: `(current − hybrid) / (current − plain)`. Float decimals retain 91.1%; the dense typed array retains 59.5%. This is a complete typed-decoding comparison, not an isolated parser-speed comparison. The plain-native adapter is a prototype, not a universal native performance ceiling.

## Whole-Value and custom fallback

| Workload | Current µs | Hybrid µs | Speedup |
| --- | ---: | ---: | ---: |
| Whole Value: 50-record response | 262.10 | 165.41 | 1.58× |
| Whole Value: dense integer array | 259,663.40 | 270,999.73 | 0.96× |
| Whole Value: 1,000 exact decimals | 3,986.10 | 2,969.42 | 1.34× |
| Custom callback: response items subtree | 368.21 | 284.43 | 1.29× |
| Custom callback: 10,000 integers | 9,343.26 | 7,690.06 | 1.21× |
| Whole Value: tagged event | 34.00 | 22.79 | 1.49× |
| Whole Value: schema document | 40.45 | 27.67 | 1.46× |

The custom-response case wraps the entire `items` array in a custom Value callback; the outer record still uses direct decoding. The custom-integer case wraps the full list. These show the materialization cost rather than treating custom callbacks as free. Encoding is used for parity checking, but is not timed.

For the dense whole-Value array, the current VM medians span 255.77–269.98 ms and hybrid 264.12–279.45 ms. The median is 4.4% slower and the ranges overlap; this finite capture does not establish a stable 4.4% regression, but it provides no evidence of a gain. Whole-Value consumers should not inherit the typed-array claims.

## Memory

MiB, median of fresh-process observations. “Heap after GC” includes the runtime and retained result. The dense array is 524,287 input bytes; it is not a few-kilobyte payload.

| Workload | Current peak RSS | Hybrid peak RSS | Current heap after GC | Hybrid heap after GC |
| --- | ---: | ---: | ---: | ---: |
| Small record (44 bytes) | 53.07 | 53.04 | 5.80 | 5.81 |
| Response with 50 records (2,301 bytes) | 53.78 | 53.27 | 5.99 | 5.89 |
| 10,000 integers | 63.35 | 56.41 | 6.30 | 6.23 |
| 262,143 integers (512 KiB) | 263.17 | 103.46 | 16.40 | 16.33 |
| 1,000 decimals → Float | 58.86 | 53.45 | 6.19 | 5.91 |
| 1,000 decimals → exact Number | 58.64 | 56.20 | 6.37 | 6.21 |
| Whole Value: dense integer array | 243.76 | 246.82 | 68.37 | 68.36 |
| Custom callback: 10,000 integers | 63.08 | 63.98 | 6.30 | 6.28 |

The dense typed-array heap delta after GC is 10.14 MiB current and 10.03 MiB hybrid. Its retained result therefore has approximately the same cost; the large improvement is in transient peak memory. Plain native peaks at 81.34 MiB for that fixture, compared with hybrid 103.46 MiB and current 263.17 MiB.

For ordinary small records and responses, total process RSS stays around 53 MiB. Differences under a MiB should not be advertised as meaningful application memory savings. The whole-Value dense array retains about 62 MiB above its pre-decode heap on both paths, and its peak is slightly higher for the hybrid. The 10,000-integer custom fallback also has a slightly higher peak despite faster execution.

## What this rules out

- It rules out the claim that strict scanning and exact tokens necessarily erase all native gains: ordinary typed records retain a clear, repeated improvement.
- It rules out applying the large typed-array memory reduction to every consumer: Value materialization and custom callbacks change that result.
- It does not establish browser performance, old-engine performance, general JSON conformance, a heap quota, or a representative production workload distribution. Browser runtimes were not executed.
- It does not measure malformed-input throughput or encoding throughput. Correctness and error-behavior evidence belong to the separate prototype review.

## Reproduction

One command in an otherwise idle environment, from this prototype worktree:

```sh
nix develop --command python3 experiment/js-hybrid-benchmark.py \
  --work /tmp/blueprint-js-hybrid-new \
  --output /tmp/blueprint-js-hybrid-new.json
```

The command exports the exact baseline Git commit, snapshots the hybrid, builds both, checks native-path selection and result equality, then captures timings and memory. Use fresh paths; existing captures are not overwritten. The retained harnesses are [Python](js-hybrid-benchmark.py), [Gleam](js-hybrid-runner.gleam), and [memory FFI](js-hybrid-bench-ffi.mjs). Timing is observational and never a gate.
