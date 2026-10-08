# Benchmarks

These measurements describe specific local checkouts and machines. They do not
guarantee performance for a published release or another workload. Historical
observations below retain their original evidence limits.

## Symmetric contract encoding, 2026-10-08

- `contract.value_codec` previously returned its supplied `Value` without checking it
  during encoding. The changed adapter validates against the contract before returning
  the same value or a located `EncodeError`.
- The [focused consumer](../codegen/test/contract_encoding_bench_test.gleam) measures
  the actual public adapter before and after that change. Typed and generated encoders
  are controls; they receive no new validation pass.
- These local observations show a substantial cost for wide closed objects. The
  500-field string-only object increases from 0.322 ms to 7.021 ms on Erlang and from
  0.210 ms to 46.961 ms on Node. Runtime validation cannot be treated as negligible
  merely because a schema has no numeric refinements.

### Method and provenance

- The baseline uses runtime source at commit `1003904cd9962ffd5eeb4f5b8ccabc60dd51d451`.
  The after capture uses the changed working tree based on that commit; the
  [before](benchmarks/contract-encoding-2026-10-08/before/provenance.json) and
  [after](benchmarks/contract-encoding-2026-10-08/after/provenance.json) manifests
  identify every measured source file by SHA256 and retain dirty status, lockfile
  hashes, and machine/runtime metadata.
- The measured host has four Cortex-A76 CPUs, Linux 6.18.34 on aarch64, Gleam 1.18.1,
  Erlang/OTP 28 with ERTS 16.4.0.6, and Node 24.21.0. Erlang uses `+S 1:1`; process
  affinity permits CPUs 0–3, with no CPU pinning or frequency control. The captured
  scaling-frequency metadata changed from 62% to 66%.
- Each target starts three fresh VMs for each capture. Each VM runs seven timed batches
  per operation after an untimed warmup. There are 44 operations and 1,848 timed batches
  in each capture.
- Every timing cell reports the median of the three VM medians; each VM median uses its
  seven batch means. Brackets give the minimum and maximum of the three VM medians, not
  a confidence interval. The [before
  summary](benchmarks/contract-encoding-2026-10-08/before/summary.json) and [after
  summary](benchmarks/contract-encoding-2026-10-08/after/summary.json) also retain each
  VM median and the full batch range.
- Parsing, fixture construction, codec construction, contract loading, semantic checks,
  and compilation are outside timed batches. `encode` measures `Value` conversion;
  `encode_json` also includes rendering. Every timed call sends its result to the
  existing observable sink; sink and loop costs remain included in both captures.
- Scalars use 100,000 calls per batch; the six-field record, Order and ten-element
  arrays use 5,000; depth 8 uses 1,000; larger collections and wide objects use 100.
  Warmup uses the smaller of the batch size and 1,000 calls. The same already
  constructed immutable payloads are reused; no input-diversity or memory-allocation
  measurement is claimed.
- All baseline VMs ran before all after VMs, and cases run in fixed order. Other review
  builds/tests were paused during captures, but the machine was not isolated. GC, JIT,
  workload history, scheduling, and frequency can change end-to-end measurements; small
  deltas are not causal estimates of validation cost.
- The source manifest is checked again after each complete capture and matched in both
  runs. The Gleam harness, runtime flags, inputs, and iteration settings are
  byte-identical across captures. The expected source differences are the adapter
  implementation/documentation, codec documentation, a new consumer test, and formatting
  of one Python runner expression.

### Complete-text encoding

- These are valid-input `codec.encode_json(contract.value_codec(schema), value)` calls.
  Success preserves the same output bytes before and after. Array values are integer 3;
  bounded arrays constrain each integer to 1–10; the six-field record has five strings
  and one bounded integer.
- Wide objects contain only strings, use names `field_1` through `field_N`, and reject
  unknown or missing fields. The depth 8 object repeatedly wraps a string under `child`.
  AnySchema receives an array of 10,000 strings without imposing element constraints.

#### Erlang/OTP 28

| Workload | Before µs/op [trial range] | After µs/op [trial range] | After / before |
| --- | ---: | ---: | ---: |
| String scalar | 0.217 [0.217–0.218] | 0.251 [0.250–0.251] | 1.16× |
| Integer scalar | 0.139 [0.139–0.140] | 0.184 [0.184–0.185] | 1.32× |
| Integer scalar, range 1–10 | 0.140 [0.139–0.140] | 0.220 [0.220–0.221] | 1.58× |
| Six-field record, one bounded integer | 4.371 [4.327–4.385] | 5.771 [5.752–5.784] | 1.32× |
| Nested object, depth 8 | 7.038 [7.037–7.261] | 8.095 [7.983–8.169] | 1.15× |
| Closed object, 10 string fields | 6.126 [6.110–6.288] | 11.401 [11.171–11.409] | 1.86× |
| Closed object, 100 string fields | 63.671 [63.009–63.698] | 342.254 [342.184–343.549] | 5.38× |
| Closed object, 500 string fields | 322.217 [320.584–322.518] | 7,021.016 [7,013.769–7,022.252] | 21.79× |
| 10 integers | 1.783 [1.772–1.796] | 1.958 [1.957–1.965] | 1.10× |
| 1,000 integers | 120.325 [119.647–121.321] | 139.477 [139.218–139.971] | 1.16× |
| 10,000 integers | 1,691.114 [1,676.637–1,692.732] | 1,861.674 [1,851.871–1,909.428] | 1.10× |
| 10 integers, each bounded | 1.775 [1.758–1.783] | 2.315 [2.300–2.327] | 1.30× |
| 1,000 integers, each bounded | 120.355 [120.344–122.757] | 175.498 [175.158–175.586] | 1.46× |
| 10,000 integers, each bounded | 1,483.533 [1,480.404–1,485.706] | 2,151.877 [2,142.430–2,175.230] | 1.45× |
| 1,000 six-field records, one bound each | 8,227.059 [8,123.010–8,807.415] | 8,212.118 [8,156.458–8,288.349] | 1.00× |
| AnySchema, array of 10,000 strings | 2,769.455 [2,768.398–2,835.552] | 2,712.282 [2,698.842–2,714.124] | 0.98× |
| Order record | 7.070 [6.881–7.089] | 7.970 [7.930–7.971] | 1.13× |

#### Node 24.21.0

| Workload | Before µs/op [trial range] | After µs/op [trial range] | After / before |
| --- | ---: | ---: | ---: |
| String scalar | 0.687 [0.685–0.699] | 1.173 [1.169–1.176] | 1.71× |
| Integer scalar | 0.773 [0.761–0.775] | 1.271 [1.268–1.276] | 1.64× |
| Integer scalar, range 1–10 | 0.810 [0.810–0.814] | 1.895 [1.879–1.896] | 2.34× |
| Six-field record, one bounded integer | 3.234 [3.177–3.242] | 14.561 [14.488–14.759] | 4.50× |
| Nested object, depth 8 | 3.099 [3.098–3.143] | 11.765 [11.655–11.881] | 3.80× |
| Closed object, 10 string fields | 4.649 [4.644–4.683] | 29.560 [29.245–29.825] | 6.36× |
| Closed object, 100 string fields | 42.128 [41.967–42.987] | 1,954.414 [1,949.125–1,954.434] | 46.39× |
| Closed object, 500 string fields | 210.169 [210.022–210.180] | 46,961.214 [46,960.086–47,068.332] | 223.44× |
| 10 integers | 4.032 [4.018–4.035] | 7.527 [7.488–7.621] | 1.87× |
| 1,000 integers | 363.604 [354.769–370.649] | 650.310 [646.471–667.147] | 1.79× |
| 10,000 integers | 3,837.744 [3,713.618–4,017.008] | 6,855.399 [6,694.651–6,887.263] | 1.79× |
| 10 integers, each bounded | 4.032 [4.015–4.055] | 13.308 [13.211–13.392] | 3.30× |
| 1,000 integers, each bounded | 363.634 [360.181–372.579] | 1,229.969 [1,220.970–1,246.163] | 3.38× |
| 10,000 integers, each bounded | 3,935.678 [3,912.518–3,975.938] | 12,415.492 [12,336.779–12,547.899] | 3.15× |
| 1,000 six-field records, one bound each | 3,664.814 [3,605.064–3,702.253] | 15,886.010 [15,697.055–16,027.837] | 4.33× |
| AnySchema, array of 10,000 strings | 2,346.616 [2,335.070–2,423.374] | 2,337.759 [2,305.623–2,398.053] | 1.00× |
| Order record | 4.531 [4.493–4.575] | 15.677 [15.569–15.711] | 3.46× |

### Value-only encoding

- These calls exclude text rendering. The baseline merely wraps the existing value in
  `Ok`, so the 100-iteration large-payload baseline batches are especially sensitive to
  sink and timer costs. Ratios against that small baseline would imply unjustified
  precision; the table reports absolute differences instead.

#### Erlang/OTP 28

| Workload | Before µs/op [trial range] | After µs/op [trial range] | Median difference µs/op |
| --- | ---: | ---: | ---: |
| String scalar | 0.045 [0.045–0.045] | 0.069 [0.069–0.069] | +0.024 |
| Integer scalar, range 1–10 | 0.045 [0.045–0.045] | 0.134 [0.134–0.135] | +0.089 |
| Closed object, 500 string fields | 0.058 [0.056–0.059] | 6,631.545 [6,628.500–6,635.051] | +6,631.487 |
| 10,000 integers | 0.056 [0.054–0.057] | 174.996 [174.612–178.844] | +174.939 |
| 10,000 integers, each bounded | 0.058 [0.055–0.059] | 510.513 [507.585–510.893] | +510.456 |
| 1,000 six-field records, one bound each | 0.056 [0.056–0.057] | 1,378.944 [1,377.668–1,378.985] | +1,378.887 |
| AnySchema, array of 10,000 strings | 0.067 [0.057–0.070] | 0.121 [0.120–0.122] | +0.054 |

#### Node 24.21.0

| Workload | Before µs/op [trial range] | After µs/op [trial range] | Median difference µs/op |
| --- | ---: | ---: | ---: |
| String scalar | 0.282 [0.278–0.290] | 0.784 [0.780–0.786] | +0.502 |
| Integer scalar, range 1–10 | 0.275 [0.275–0.285] | 1.378 [1.374–1.387] | +1.103 |
| Closed object, 500 string fields | 0.300 [0.289–0.315] | 47,021.031 [46,986.906–47,056.013] | +47,020.731 |
| 10,000 integers | 0.289 [0.282–0.301] | 2,939.142 [2,877.409–2,960.709] | +2,938.853 |
| 10,000 integers, each bounded | 0.292 [0.282–0.295] | 8,523.477 [8,481.242–8,688.697] | +8,523.185 |
| 1,000 six-field records, one bound each | 0.291 [0.286–0.295] | 11,852.386 [11,772.935–11,940.191] | +11,852.094 |
| AnySchema, array of 10,000 strings | 0.291 [0.289–0.293] | 0.899 [0.895–0.908] | +0.608 |

### Typed/generated controls and repeated validation

- The Order controls encode the same application-native record and verify equal wire
  output. The typed control uses `codec.encode_json` with a reused runtime codec; the
  generated control calls `order_codec.encode_order_json`, whose native rendering path
  differs. Their purpose is to observe unchanged code across captures, not rank
  equivalent implementations.

| Target and operation | Before µs/op [trial range] | After µs/op [trial range] | After / before |
| --- | ---: | ---: | ---: |
| erlang: `typed_encode_json` | 9.097 [9.089–9.242] | 7.786 [7.770–8.221] | 0.86× |
| erlang: `generated_encode_json` | 3.968 [3.943–4.036] | 3.665 [3.663–3.740] | 0.92× |
| javascript: `typed_encode_json` | 26.405 [26.235–26.450] | 26.003 [25.976–27.300] | 0.98× |
| javascript: `generated_encode_json` | 10.642 [10.543–11.503] | 10.389 [10.329–10.624] | 0.98× |

- Unchanged Erlang typed/generated control code became faster between captures; their
  displayed trial ranges do not overlap. This is measured variation, not an optimization
  delivered by the adapter change. The nearly unchanged Erlang sparse-record
  complete-text result likewise does not establish free validation: its Value-only
  measurement shows additional work.
- The following calls first run `contract.validate` over 1,000 records.
  `validate_then_encode_json` extracts the value and calls the adapter, so the changed
  adapter validates it again. `validate_then_render` extracts the already checked value
  and calls `value.to_string`; this existing explicit path performs one validation and
  requires no new API.

| Target and operation | Before µs/op [trial range] | After µs/op [trial range] | After / before |
| --- | ---: | ---: | ---: |
| erlang: `validate_then_encode_json` | 7,106.132 [7,095.405–7,147.272] | 8,233.536 [8,184.011–8,433.361] | 1.16× |
| erlang: `validate_then_render` | 7,097.473 [7,041.137–7,150.337] | 7,048.482 [7,046.631–7,086.976] | 0.99× |
| javascript: `validate_then_encode_json` | 15,482.323 [15,359.358–16,022.379] | 27,323.062 [27,166.417–29,107.224] | 1.76× |
| javascript: `validate_then_render` | 15,410.511 [15,363.971–15,922.564] | 15,373.692 [15,256.352–16,197.843] | 1.00× |

### Invalid input

- Both cases are 1,000-element bounded-integer arrays containing 99 at the named
  position. The baseline succeeds and renders invalid output; the changed adapter
  returns `IntegerOutsideRange(1, 10)` at index 0 or 999. These calls perform different
  work and produce different outcomes, so no speedup ratio is reported.

| Target and rejected position | Before successful text encoding µs/op [trial range] | After rejection µs/op [trial range] |
| --- | ---: | ---: |
| erlang: first | 165.192 [164.770–165.348] | 0.169 [0.166–0.170] |
| erlang: last | 163.056 [162.694–164.983] | 58.111 [58.085–58.118] |
| javascript: first | 347.560 [343.944–351.303] | 1.772 [1.734–1.787] |
| javascript: last | 347.407 [343.184–348.171] | 866.091 [850.645–866.365] |

### Consequences and reproduction

- The existing [contract validator](../src/json/blueprint/contract.gleam) repeatedly
  scans lists for allowed names, duplicates, and property lookup. Wide-object results
  grow much faster than width; this is a concrete candidate for a separate optimization
  experiment preserving rejection order and located errors. This change does not add
  indexes, caches, a validation plan, or configuration switches.
- Bounded integer validation reconstructs exact-number bounds and compares each value
  against them. The benchmark establishes the total cost for these cases, not the share
  attributable to each internal operation. Unbounded integers still require structural
  and integrality checks; they cannot inherit the guarantees of native `Int` from a
  general `Value`.
- AnySchema does not traverse the array because its contract imposes no element
  constraints. Typed and generated codecs retain their existing checks during encoding.
  The measurements do not justify a new witness-carrying encoder; callers already
  holding `ValidatedValue` can deliberately use `contract.value` followed by
  `value.to_string` when no enclosing codec is needed.
- The [runner](../scripts/contract_encoding_benchmark.py) creates a new evidence
  directory and refuses to reuse it. Run it from the repository root inside the Nix
  shell; it compiles both targets before timing and uses no live service.

```sh
nix develop --command python3 scripts/contract_encoding_benchmark.py \
  --output .ci-results/contract-encoding-local --trials 3
```

- The six raw VM logs are retained in each
  [before](benchmarks/contract-encoding-2026-10-08/before/) and
  [after](benchmarks/contract-encoding-2026-10-08/after/) directory. The summaries are
  computed from those logs; no timing threshold enters the test gate.
- To reconstruct baseline inputs, use an isolated checkout of commit
  `1003904cd9962ffd5eeb4f5b8ccabc60dd51d451`, copy the retained harness and runner into
  their current paths, and apply [the formatting-only runner
  patch](benchmarks/contract-encoding-2026-10-08/before/runner-formatting.patch). Its
  reconstructed SHA256 was checked against baseline provenance; unrelated dirty
  design/root-test files listed there were not benchmark inputs.
- The retained fixture tests check successful values against their contracts, preserve
  encoded values/text, compare native/generated output, and locate both invalid bounds.
  They ran on every benchmark VM before timing. Compiler/semantic evidence and local
  timing observations remain separate from broad JSON Schema conformance or performance
  guarantees.


## Timed calls recorded on 2026-09-20

The [original measurement report](https://github.com/lostbean/json_blueprint/blob/8f2d46c5a4174a3700e0f214e37e612b0c65316a/test/oracle/wave-4-report.md#3-measured-local-benchmark-baselines)
records Erlang/OTP 28 and Node.js 24.15.0 results. The
[retained harness](https://github.com/lostbean/json_blueprint/blob/8f2d46c5a4174a3700e0f214e37e612b0c65316a/test/bench_test.gleam)
runs 200 untimed warmup calls, then times 1,000 calls in one elapsed interval
with a monotonic nanosecond clock. Its reported mean is the integer quotient
of elapsed nanoseconds divided by 1,000. It records no independent-run
distribution, percentiles, or uncertainty interval.

| Workload                               | Unit                            | Erlang/OTP 28 mean | Node.js 24.15.0 mean |
| -------------------------------------- | ------------------------------- | ------------------ | -------------------- |
| `number_parse_canonical_7_token_batch` | ns per seven-token batch        | 2,247              | 17,712               |
| `parser_document_admission`            | ns per parsed document          | 9,847              | 41,057               |
| `runtime_contract_validation`          | ns per validated value          | 295                | 4,450                |
| `codec_encode_decode_roundtrip`        | ns per Value encode/decode pair | 346                | 6,581                |

The number batch parses and renders `0`, `1`, `1.2300e2`, `123.45`, `-0.5`,
`9007199254740992`, and `1e400`. Each timed call processes seven tokens, so
1,000 timed calls process 7,000 tokens. The harness permits 1,024 bytes per
number token, 100 significant digits, and exponent magnitude 1,000.

Document admission parses this complete JSON document with a 100,000-byte
limit and nesting limit of 32:

<!-- prettier-ignore -->
```json
{"title": "bench", "count": 42, "items": [1, 2, 3], "active": true, "note": null}
```

Runtime validation checks an already constructed value with name `Ada Lovelace`,
age `36` bounded from 0 through 120, and tags `computing` and `mathematician`.
Codec roundtrip uses a native record with the same name and age and tags
`computing` and `math`. It encodes to `Value` and decodes that value; JSON text
rendering and parsing are excluded. The contract and codec are constructed
before timing.

The report is dated 2026-09-20 and names starting HEAD
`cf378926647ed83dc0669f49d4bb8591b5e1381f`. Commit
`8f2d46c5a4174a3700e0f214e37e612b0c65316a` retains the report and harness; it
does not establish the exact working-tree revision that was measured. Hardware,
OS, compiler version for that run, scheduler settings, and raw timing output
are not recorded. Subsequent parser, codec, and API changes prevent treating
these numbers as current baselines.

## Run the current harness

From the repository root, enter `codegen/` before running the harness:

```sh
cd codegen
nix develop .. --command gleam run --target erlang -m bench_test
nix develop .. --command gleam run --target javascript -m bench_test
```

The [current harness](../codegen/test/bench_test.gleam) retains the four named
workloads and adds Order construction, runtime/generated codec, complete-text,
and native-parser cases. It prints 200 warmup calls, 1,000 timed calls, total
elapsed nanoseconds, mean ns/op, and ops/sec for each workload. Running it
measures the current checkout on the current machine; it does not reproduce
the historical implementation or machine above.

Complete-text cases include rendering or parsing. The generated native decoder
uses `gleam/json`; strict generated decoding uses Blueprint's parser and keeps
different number, duplicate-key, and resource guarantees. Construction cases
send their result to an observable sink. Parsing, construction, and Value-only
cases measure different work, so compare matching cases with the same parser
policy.

Weekly and manual runs of the `Benchmark observations` workflow execute this
current harness on both targets. `scripts/benchmark.sh` creates a fresh evidence
directory and retains both raw logs, the source revision and dirty status,
lockfile hashes, runtime versions, and OS/architecture. Timing remains an
observation without a speed ceiling or a published performance claim. The
ordinary CI gate retains the benchmark fixtures' semantic tests.

## Historical memory observations

The [retained README at commit `94438b9`](https://github.com/lostbean/json_blueprint/blob/94438b93b638a2ecf2e4443bd9c2c3cbf97b7713/README.md#defaults)
records the following `value.parse` observations on Erlang/OTP 28 and Node.js 24. The implementation change dates to 2026-10-02. It describes Erlang peak
process heap as the old and new heaps counted together at garbage-collection
events, and Node figures as heap growth. These are different measurements.

| Input at the defaults                          | Text    | Peak heap, OTP 28 | Parsed value, OTP 28 | Heap growth, Node.js 24 |
| ---------------------------------------------- | ------- | ----------------- | -------------------- | ----------------------- |
| `[1,1,...]`: 262,143 integers, the value limit | 512 KiB | 42 MB             | 16 MB                | about 120 MB            |
| `["a","a",...]`: 262,143 strings               | 1 MiB   | 40 MB             | 16 MB                | about 75 MB             |
| `[{"k":1},...]`: 87,001 objects                | 680 KiB | 32 MB             | 13 MB                | about 75 MB             |
| 61,001 fifteen-digit decimals                  | 1 MiB   | 16 MB             | 6 MB                 | about 80 MB             |

With the value limit raised, 1 MiB of `[1,1,...]` containing 524,288 integers
was recorded at an 80 MB Erlang heap peak by the same method.

The record provides no retained memory-measurement command, run date, sample
count, aggregation across runs, hardware, or raw allocation trace. The table
therefore supplies historical sizing observations only. The `MB` units retain
the original label; their decimal/binary convention was not recorded. Parser
byte and value limits are admission bounds, not heap quotas. The current
timing harness above does not reproduce these memory observations.
