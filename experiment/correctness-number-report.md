# Correctness-fix benchmark: standalone numbers and wide records

Historical diagnostic capture of the initial list-tracking fix. The [final dictionary-tracking and range-check results](correctness-number-final-report.md) supersede its performance conclusions.

Capture: 2026-10-25T23:19:48.036061+00:00. Before revision: `ce233eed218e5bc7a68e171a23c60075c2a389a7`. After: fixed working-tree source, with every source hash retained in [raw results](correctness-number-results.json). No production source changed during capture.

## Method

Six fresh VMs per implementation, target and workload, alternating before/after order. Each VM warms up once and measures five batches. Numbers use 5,000 calls per batch; records use 500. Tables report the median of six VM medians, in microseconds per call. Ranges are the minimum and maximum VM medians, not confidence intervals. Results escape into the observable benchmark sink. Construction, source generation, outcome comparison and compilation are excluded. Both isolated packages build with warnings as errors.

Environment: macOS arm64, Gleam 1.19.2, OTP 29 / ERTS 17.1.1 with `+S 1:1`, Node 24.21.0. No CPU affinity or frequency control. Other task benchmarks and gates had completed before capture. This small benchmark does not measure memory.

Numbers exercise the public standalone `number.parse`, which the typed-decoding benchmark does not isolate. Decimal `19.90` and exponent `-6.02214076e23` use default limits. The safe boundary `1e-9007199254740991` uses `number.limits(100, 100, 9_007_199_254_740_991)`. All timed outcomes agree before/after.

Records use `codec.decode_json` with 20 or 100 unique required integer fields. Their continuation codecs are constructed outside timing. JSON sizes are 161 and 881 bytes. All decoded and re-encoded outcomes agree before/after. Encoding is used only for preflight and is not timed.

## Measurements

| Target | Workload | Before µs (VM range) | After µs (VM range) | Change |
| --- | --- | ---: | ---: | ---: |
| erlang | ordinary_decimal | 0.248 (0.238–0.268) | 0.256 (0.243–0.282) | +3.0% |
| erlang | ordinary_exponent | 0.420 (0.391–0.454) | 0.446 (0.423–0.459) | +6.2% |
| erlang | large_safe_exponent | 0.447 (0.427–0.468) | 0.464 (0.423–0.467) | +3.8% |
| erlang | record_20 | 13.408 (13.163–13.790) | 16.242 (15.954–16.784) | +21.1% |
| erlang | record_100 | 62.163 (59.926–72.420) | 114.978 (114.093–116.407) | +85.0% |
| javascript | ordinary_decimal | 1.655 (1.607–4.363) | 2.080 (2.009–2.220) | +25.6% |
| javascript | ordinary_exponent | 2.417 (2.379–2.469) | 2.893 (2.864–2.913) | +19.7% |
| javascript | large_safe_exponent | 2.390 (2.336–2.952) | 3.065 (2.957–3.161) | +28.2% |
| javascript | record_20 | 64.038 (63.465–64.757) | 66.795 (66.124–68.259) | +4.3% |
| javascript | record_100 | 697.998 (691.437–712.083) | 762.178 (747.702–769.182) | +9.2% |

The Erlang standalone-number differences are small and their VM ranges overlap; this capture does not establish a stable 3–6% regression. JavaScript pays about 0.42–0.68 µs per standalone parse for the checked path. The ordinary-decimal baseline includes one slow VM; the median still shows the same direction as the exponent cases.

Wide records expose a real cost hidden by ordinary three-field workloads: the visited-name list is scanned for each declaration. Erlang 100-field decoding rises from 62.16 to 114.98 µs, with disjoint VM ranges. JavaScript rises from 698.00 to 762.18 µs. This is a width-sensitive correctness cost, not large-input parsing or the standalone-number fix. These before/after measurements are not a comparison against the older optimized strict parser. No additional optimization was applied in this experiment.

## Precision outcomes

These previously misdecoded inputs are checked separately and are not timed.

| Target | Token | Before | After |
| --- | --- | --- | --- |
| erlang | `1.00e-9007199254740991` | `Ok:1e-9007199254740991` | `Ok:1e-9007199254740991` |
| erlang | `100e-9007199254740993` | `Ok:1e-9007199254740991` | `Ok:1e-9007199254740991` |
| javascript | `1.00e-9007199254740991` | `Ok:1e-9007199254740990` | `Ok:1e-9007199254740991` |
| javascript | `100e-9007199254740993` | `Ok:1e-9007199254740990` | `Error:ExponentOutOfRange` |

JavaScript now preserves the representable normalized exponent when the written exponent is safe. It explicitly refuses the second token because its written exponent exceeds the safe integer range, even though cancellation could produce a representable normalized exponent. Erlang remains exact for both. The refusal uses the existing `ExponentOutOfRange` result.

## Reproduction

Run in a Nix development shell, using a fresh scratch directory and output filename:

```sh
python3 experiment/correctness-number-benchmark.py --work /tmp/blueprint-number-new --prepare
# Once other benchmark/test jobs are idle:
python3 experiment/correctness-number-benchmark.py --work /tmp/blueprint-number-new --capture --output /tmp/blueprint-number-new.json
```

[Python harness](correctness-number-benchmark.py), [Gleam runner](correctness-number-runner.gleam), [raw batches, environment and source hashes](correctness-number-results.json). The original runner and harness bytes are retained; do not reformat captured harness files without retaining their original bytes.
