# Final correctness-fix benchmark: standalone numbers and wide records

Capture: 2026-10-25T23:24:25.245444+00:00. Before revision: `ce233eed218e5bc7a68e171a23c60075c2a389a7`. After: final fixed working-tree source using dictionary declaration tracking and JavaScript range checks. Every source hash is retained in [raw results](correctness-number-final-results.json). Source hashes remained unchanged during capture.

This supersedes the performance conclusions of the [initial list-tracking experiment](correctness-number-report.md). That earlier evidence is retained because it identified the avoidable wide-record and JavaScript-number overhead. No additional production changes were made during this capture.

## Method

Six fresh VMs per implementation, target and workload, alternating before/after order. Each VM warms up once and measures five batches: 5,000 calls for numbers, 500 for records. Values below are the median of six VM medians, in microseconds per call. Ranges are minimum/maximum VM medians, not confidence intervals. Results escape into an observable sink. Construction, source generation, outcome checks and compilation are excluded. Both isolated packages build with warnings as errors.

Environment: macOS arm64, Gleam 1.19.2, OTP 29 / ERTS 17.1.1 with `+S 1:1`, Node 24.21.0. No CPU affinity or frequency control. Full gates and other benchmarks had completed before capture. This focused experiment does not measure memory.

Numbers exercise standalone `number.parse`. `19.90` and `-6.02214076e23` use default limits. `1e-9007199254740991` uses `number.limits(100, 100, 9_007_199_254_740_991)`. All timed outcomes agree before/after.

Records exercise `codec.decode_json` with 20 or 100 unique required integer fields in 161-byte or 881-byte JSON objects. Their continuation codecs are constructed outside timing. Decode/re-encode preflight outcomes agree before/after; encoding is not timed.

## Measurements

| Target | Workload | Before µs (VM range) | Final µs (VM range) | Change |
| --- | --- | ---: | ---: | ---: |
| erlang | ordinary_decimal | 0.243 (0.225–0.269) | 0.251 (0.229–0.272) | +2.9% |
| erlang | ordinary_exponent | 0.372 (0.370–0.378) | 0.396 (0.393–0.459) | +6.5% |
| erlang | large_safe_exponent | 0.453 (0.401–0.460) | 0.411 (0.396–0.544) | -9.2% |
| erlang | record_20 | 13.151 (12.582–13.422) | 17.490 (16.963–17.915) | +33.0% |
| erlang | record_100 | 57.704 (55.168–59.703) | 82.505 (80.438–85.252) | +43.0% |
| javascript | ordinary_decimal | 1.599 (1.594–1.645) | 1.825 (1.816–1.845) | +14.1% |
| javascript | ordinary_exponent | 2.407 (2.394–2.422) | 2.663 (2.652–2.690) | +10.6% |
| javascript | large_safe_exponent | 2.344 (2.322–2.431) | 2.532 (2.514–2.588) | +8.0% |
| javascript | record_20 | 63.843 (62.901–67.056) | 66.888 (66.452–67.249) | +4.8% |
| javascript | record_100 | 697.938 (690.298–709.523) | 701.527 (694.426–705.791) | +0.5% |

Standalone JavaScript parsing pays about 0.19–0.26 µs per call (8–14%) for exact exponent checks. The earlier allocating check measured 20–28%; these separate captures show improvement but are not an isolated same-capture comparison of the two remedies. Erlang numeric results remain below 0.5 µs: the ordinary exponent shows about 24 ns added, while decimal/boundary ranges overlap. The apparent boundary speedup is not evidence of a stable optimization.

Declaration validation still has a measurable cost on wide native Erlang records: +4.34 µs for 20 fields and +24.80 µs for 100 fields, with disjoint VM ranges. A dictionary avoids the initial fix's quadratic seen-list scan: the 100-field final time is 82.51 µs versus 114.98 µs in the earlier list capture. However, the 20-field final time is 17.49 µs versus 16.24 µs previously. Different capture baselines prevent treating those cross-capture differences as precise causal estimates. The final implementation has no width threshold or extra placeholder traversal.

JavaScript 100-field results overlap substantially (+0.5% median), while the 20-field median rises by 4.8%. These fixtures measure record width, not large input: both are under 1 KiB. Ordinary small records and response arrays are measured separately in the main benchmark. This table compares against the pre-correctness native implementation, not against the older strict parser.

## Precision outcomes

| Target | Token | Before | Final |
| --- | --- | --- | --- |
| erlang | `1.00e-9007199254740991` | `Ok:1e-9007199254740991` | `Ok:1e-9007199254740991` |
| erlang | `100e-9007199254740993` | `Ok:1e-9007199254740991` | `Ok:1e-9007199254740991` |
| javascript | `1.00e-9007199254740991` | `Ok:1e-9007199254740990` | `Ok:1e-9007199254740991` |
| javascript | `100e-9007199254740993` | `Ok:1e-9007199254740990` | `Error:ExponentOutOfRange` |

JavaScript preserves the representable normalized exponent when the written exponent is safe. It explicitly refuses the second token because its written exponent exceeds the safe integer range, even though cancellation could produce a representable normalized exponent. Erlang remains exact for both. The existing `ExponentOutOfRange` result reports the refusal.

## Reproduction and evidence

In a Nix development shell, use a fresh scratch directory and output file:

```sh
python3 experiment/correctness-number-benchmark.py --work /tmp/blueprint-number-new --prepare
# Once other benchmark/test jobs are idle:
python3 experiment/correctness-number-benchmark.py --work /tmp/blueprint-number-new --capture --output /tmp/blueprint-number-new.json
```

[Python harness](correctness-number-benchmark.py), [Gleam runner](correctness-number-runner.gleam), [raw batches, environment and source hashes](correctness-number-final-results.json). Harness bytes are identical to the initial capture and their hashes are retained.
