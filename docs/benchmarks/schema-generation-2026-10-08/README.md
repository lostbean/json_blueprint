# Schema-driven native generation measurements, 2026-10-08

## Interpretation

- At 100 items, generated and handwritten native encoding have similar measured cost: 135.05 versus 134.39 µs on Erlang and 1882.75 versus 1830.32 µs on Node. Their allocation is also similar; generation supplies types and maintained codec source, rather than a runtime acceleration claim.
- Smaller records show greater relative differences and trial variation. For one item, generated encoding took 3.56 versus 2.94 µs on Erlang and 56.63 versus 49.97 µs on Node; these observations do not establish exact performance parity.
- Generated codec construction costs 3.84 µs and 6.49 KiB of process-heap allocation on Erlang, or 66.38 µs and an estimated 26.66 KiB on Node. Retaining the codec keeps that construction outside repeated conversion calls; this is caller-owned reuse, not a hidden cache.
- The dynamic path often allocates less because it validates prebuilt values. Native conversion pays for constructing the requested representation; this experiment does not justify replacing it with a second dynamic validation pass.

## Comparison boundary

- This capture compares generated native `Order` codecs with a handwritten public-combinator codec over the same generated types and a runtime contract over prebuilt `Value`. No previous schema-to-native implementation exists; the handwritten codec is a comparison rather than a before/after baseline.
- The generated and handwritten codecs prebind child codecs before record continuations; the handwritten example additionally shares identical primitive codec values. The dynamic codec is constructed from a previously loaded contract. Conversion measurements reuse each constructed codec and prebuilt input; schema loading and codec construction are outside those measurements.
- Native encoding constructs a `Value` from a record; dynamic encoding validates an existing `Value`. Native decoding constructs records; dynamic decoding validates and returns its input. These are different operations, so dynamic results describe the cost of that application choice rather than an equivalent native-conversion baseline.
- Text operations include strict parsing or serialization on each call. Number fields retain exact decimals; each item has a bounded integer quantity, string SKU, and bounded exact price. The fixed envelope includes nested shipping, a number pair, optional labels, optional nullable note, and required nullable reference.

## CPU observations

- Entries are medians of three fresh VMs in microseconds per operation. G/H/D mean generated native codec, handwritten native codec, and dynamic contract respectively; the [summary CSV](summary.csv) retains each minimum and maximum.

| Target | Items | Operation | G, µs | H, µs | D, µs |
|---|---:|---|---:|---:|---:|
| erlang | 1 | encode_value | 3.56 | 2.94 | 3.06 |
| erlang | 1 | decode_value | 2.68 | 3.18 | 3.06 |
| erlang | 1 | encode_text | 31.72 | 31.04 | 31.47 |
| erlang | 1 | decode_text | 21.97 | 21.71 | 21.22 |
| erlang | 25 | encode_value | 35.99 | 36.74 | 23.33 |
| erlang | 25 | decode_value | 25.70 | 25.76 | 23.35 |
| erlang | 25 | encode_text | 272.35 | 271.71 | 267.34 |
| erlang | 25 | decode_text | 171.40 | 170.40 | 162.62 |
| erlang | 100 | encode_value | 135.05 | 134.39 | 86.06 |
| erlang | 100 | decode_value | 94.50 | 93.86 | 86.12 |
| erlang | 100 | encode_text | 1000.53 | 1007.44 | 955.16 |
| erlang | 100 | decode_text | 610.61 | 596.72 | 572.23 |
| javascript | 1 | encode_value | 56.63 | 49.97 | 31.22 |
| javascript | 1 | decode_value | 52.55 | 46.90 | 26.21 |
| javascript | 1 | encode_text | 168.42 | 157.49 | 131.79 |
| javascript | 1 | decode_text | 258.34 | 219.77 | 193.58 |
| javascript | 25 | encode_value | 484.35 | 481.56 | 397.39 |
| javascript | 25 | decode_value | 454.44 | 449.83 | 365.12 |
| javascript | 25 | encode_text | 1426.07 | 1431.55 | 1261.17 |
| javascript | 25 | decode_text | 1730.68 | 1981.57 | 1683.82 |
| javascript | 100 | encode_value | 1882.75 | 1830.32 | 1417.81 |
| javascript | 100 | decode_value | 1685.96 | 1716.20 | 1411.65 |
| javascript | 100 | encode_text | 5333.37 | 5157.31 | 4611.60 |
| javascript | 100 | decode_text | 6320.93 | 6534.15 | 6057.74 |

## Allocation observations

- Erlang entries are exact process-heap allocation counters from OTP `call_memory`, including allocations later collected. They exclude off-heap binary payloads and native allocator memory. Node entries are sampled managed-heap allocation estimates with objects collected by minor and major GC included; they are not exact counts.
- The probes measure allocation in separate VMs from CPU timing. Neither metric is a before/after heap-size difference, RSS, a concurrent peak, or a measurement of total process memory. Cross-runtime byte magnitudes have different accounting boundaries.
- Entries are KiB per value-only encoding operation; generated and handwritten encoders construct output while dynamic encoding retains its supplied value.

| Target | Items | G, KiB | H, KiB | D, KiB |
|---|---:|---:|---:|---:|
| erlang | 1 | 9.93 | 9.91 | 2.83 |
| erlang | 25 | 81.59 | 81.57 | 34.70 |
| erlang | 100 | 305.41 | 305.40 | 134.31 |
| javascript | 1 | 51.50 | 49.64 | 23.70 |
| javascript | 25 | 545.98 | 546.02 | 391.38 |
| javascript | 100 | 2046.27 | 2089.72 | 1542.56 |

## Construction and generation

- Each codec accessor constructs a codec; no global cache is installed. Reusing the returned codec retains its child codecs and parsed numeric bounds. Ordinary record continuations still perform runtime work; generation does not remove the existing codec machinery.
- Codec-construction time and allocation are measured separately below. Dynamic construction excludes contract admission; source generation starts from the admitted schema and excludes file I/O, formatting, dependency compilation, and compilation of the returned Gleam source. Source-generation allocation was not measured.

| Target | Construction | Time, µs | Allocated KiB |
|---|---|---:|---:|
| erlang | generated codec | 3.842 | 6.492 |
| erlang | handwritten codec | 2.128 | 5.859 |
| erlang | dynamic codec | 0.051 | 0.219 |
| javascript | generated codec | 66.378 | 26.660 |
| javascript | handwritten codec | 55.842 | 23.653 |
| javascript | dynamic codec | 0.362 | 0.563 |

- Pure source generation on erlang: median **0.332 ms**, range 0.330–0.332 ms per module (200 generations per VM after 20 warmups).

- Pure source generation on javascript: median **0.820 ms**, range 0.816–0.825 ms per module (200 generations per VM after 20 warmups).

## Method and limits

- Toolchain: gleam 1.18.1, OTP 28 ERTS 16.4.0.6 word bytes 8, Node v24.21.0; Linux-6.18.34-aarch64-with-glibc2.44, 4 visible CPUs. Erlang uses `+S 1:1`; no CPU affinity, frequency control, or host isolation was applied.
- Each mode/runtime has three fresh VMs. Case order is forward/reverse/forward; each CPU case warms and calibrates toward a 150 ms batch with a two-million-iteration cap. Allocation iterations are independently bounded; profile instrumentation is excluded from CPU captures.
- Source generation uses an independent development-task process. Application/compiler work was paused during the final measurement window. Three observations identify large differences and variation; they do not establish stable tail latency, capacity, browser behavior, or a universal performance guarantee.
- The allocation probes adapt the project-owned retained experiment at `oversight/.artifacts/search-validation-experiment-20261008/sandbox/codegen/test/allocation_probe.{erl,mjs}`. Erlang retains its `call_memory` wrapper and GC accounting; Node retains inspector sampling of collected allocations and removes unrelated operational-heap observations. The retained source hashes in [probe provenance](probe-provenance.json) identify the originals; the adapted probe source is committed in the consumer.
- An earlier capture was interrupted when a naming correction changed the generator source. That capture is excluded from every table; the final capture starts after the implementation was frozen.

## Behavior and reproducibility

- [Initial red](consumer-red.txt): the separate build task failed because `json/blueprint/codegen/schema` did not exist. [Final green](consumer-green.txt): generated output matched regeneration, ten consumer tests passed on each runtime, and a source-only package with development dependencies removed built on both targets without a generator dependency.
- The consumer includes a 95-value acceptance corpus and direct recovery tests. Native-number projection is separate: `1e30` is contract-valid but refused by native `Int` on both targets, while `9007199254740993` projects exactly on Erlang and is refused on JavaScript. Exact `Number` fields preserve `1.234567890123456789e1000` through strict text round trips.
- No live service, upstream oracle, full JSON Schema conformance, or concurrency test is claimed here. The parent package gate is separate from this consumer capture.
- [Runner](../../../scripts/schema_generation_benchmark.py), [consumer](../../../codegen/consumer/README.md), [raw captures](capture/), [input fingerprints](capture/inputs.sha256.json), and [all records](capture/results.json) retain the executable evidence. The source fingerprints describe the measured working tree based on the recorded revision; the base revision alone does not include this uncommitted implementation.

```sh
nix develop --command python3 scripts/schema_generation_benchmark.py --output /tmp/schema-generation-results
nix develop --command sh scripts/check-schema-consumer.sh
```
