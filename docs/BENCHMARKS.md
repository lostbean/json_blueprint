# Benchmarks

Local timing and allocation observations for the runtime contracts, the codec
paths and the schema-driven generator. They describe specific checkouts and
machines, give no guarantee for a published release or another workload, and
never gate a change. The [oracle](ORACLE.md) is the companion document for
correctness evidence. The [design](design/design.typ#repository-verification)
states the verification model, and [AGENTS.md](../AGENTS.md#references) points here.

## Maintained comparisons

| Runner | Comparison |
| --- | --- |
| `scripts/benchmark.sh` | Runtime and generated codecs versus vanilla native encoding/decoding; construction and schema operations |
| `scripts/parser_benchmark.py` | Current strict Value parsing versus native parsing, on both targets; fresh-process timing and peak RSS |
| `scripts/contract_encoding_benchmark.py` | Contract validation and encoding costs |
| `scripts/schema_generation_benchmark.py` | Generated, handwritten and dynamic schema-consumer operations |

Native parsing does not enforce the same duplicate-key, exact-number or schema
contracts. Compare equivalent successful values, and report these differences
alongside timing. Peak RSS includes the VM and is not an isolated allocation
measurement. Inputs are representative fixtures, not a production distribution.

Engine experiments, archives and adoption captures are no longer retained in the
checkout. Their design conclusions live in [ADR 0014](adr/0014-adopt-native-erlang-decoding-with-byte-admission.md),
[ADR 0015](adr/0015-adopt-javascript-native-hybrid.md) and
[ADR 0016](adr/0016-specialize-generated-codecs-with-runtime-semantics.md).
Use the maintained runners for fresh measurements; keep local output in
`.ci-results/` or a temporary directory. Correctness tests and independent oracle
fixtures remain maintained separately.

## Method of the retained 2026-10-08 captures

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

## Limits of these claims

- Three fresh VMs identify large differences and variation; they do not establish
  tail latency, capacity, browser behavior or concurrency.
- A timing observation is never an acceptance test. Behavior is judged by the
  [oracle](ORACLE.md) and the package gate.
- To reconstruct a baseline, use an isolated checkout of the baseline commit, copy
  the retained harness and runner into their current paths and apply
  [the formatting-only runner patch](benchmarks/contract-encoding-2026-10-08/before/runner-formatting.patch).
