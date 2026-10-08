# Runtime object validation, 2026-10-08

- Runtime contracts use private string-specific searches for small objects and a temporary dictionary above 40 input members. A direct check of the first 32 members rejects early name failures before dictionary construction.
- The dictionary checks names in input order and values in normalized schema order. It distinguishes an absent property from a present null and returns the original immutable value after validation.
- The implementation changes no public signature, schema profile, setup operation, cache, or lifecycle. The cutoff is an internal CPU/allocation compromise rather than an admission limit.

## Production before and after

- The baseline is `b3d894000c9bb814cc4b95932fc2fb7e61f1964e`. Both captures use the unchanged [consumer benchmark](../../../codegen/test/contract_encoding_bench_test.gleam) and [runner](../../../scripts/contract_encoding_benchmark.py). Their provenance files retain exact source fingerprints, toolchains, and working-tree state.
- Each capture runs three fresh VMs per target with seven batches after warmup. The table reports microseconds per operation as the median of each VM's batch median; contract loading, adapter construction, and fixture creation are outside timing.
- All baseline trials precede all implementation trials. The host was not isolated or frequency-controlled; unchanged controls also shifted between captures, especially on Node. These timings are observations rather than isolated causal estimates for small changes.
- The after-change execution session ended after two Erlang trials. The [resume receipt](after/resume.json) records completion of only the missing trials with unchanged source fingerprints; the recovery script remains in `oversight/.artifacts/object-validation-implementation-20261008/resume_benchmark.py`.

| Public task | Erlang before → after, µs | Node before → after, µs |
| --- | ---: | ---: |
| Six-field native record | 1.45 → 1.36 | 11.47 → 6.37 |
| 10-field object | 3.42 → 3.21 | 24.61 → 9.87 |
| 100-field object | 280.41 → 69.55 | 1,909.65 → 210.28 |
| 500-field object | 6,763.64 → 369.66 | 53,468.94 → 1,099.52 |
| 500-field object with JSON rendering | 7,333.90 → 685.88 | 48,526.41 → 1,473.39 |
| 1,000 native records | 1,583.33 → 1,262.46 | 13,323.03 → 7,279.01 |
| Typed order control | 1.32 → 1.31 | 35.56 → 28.39 |
| Generated order control | 0.82 → 0.84 | 19.25 → 15.75 |

- [Before summaries](before/summary.json) and [after summaries](after/summary.json) retain trial ranges and all scalar, array, nesting, failure, rendering, typed, and generated controls. Raw logs and provenance are adjacent to each summary.
- The [audit](AUDIT.txt) reconstructs both summaries from every raw sample and checks source fingerprints. The [package gate receipt](checks/gate.log) and public replay logs remain in `checks/`.

## Allocation and limits

- The production algorithm matches the approved `recursive40` prototype apart from comments and formatting. The earlier allocation and concurrency experiment remains at `oversight/.artifacts/search-validation-experiment-20261008/REPORT.md` in the sibling workspace; those measurements were not repeated during this implementation.
- Removing the copied prefix saved 1 KiB of Erlang process-heap allocation per indexed object compared with the earlier indexing prototype. String-specific searches reduced small-object allocation on both targets; the 40-member cutoff avoided dictionary allocation for 33–40 input members.
- Indexing allocates more than the improved linear search for wide valid objects on both targets. It constructs a new dictionary on each validation; callers retain their existing contract and adapter, and no validation index is retained with the result.
- The earlier mixed workload observed aggregate worker-memory peaks of about 6.6 MiB for the previous index and 10.0 MiB for the approved prototype with 16 BEAM workers. Lower allocation per call therefore does not establish lower peak memory; the observed memory was sampled worker process memory rather than whole-VM RSS.
- The threshold is not optimal for every workload. The prior cutoff comparison traded roughly 10–13% BEAM CPU at 39–40 fields for lower allocation, and some failures after the early-name prefix still pay dictionary setup. Validation retains no independent time, depth, width, or allocation quota.

## Correctness and design conformance

- Six public regression functions were added before the refactor. The unchanged validator passed 244 Erlang tests and 243 Node tests, including competing failures near the prefix/cutoff, normalized property order, optional absence versus null, Unicode and JavaScript-sensitive names, and nested paths.
- The implementation is reviewed against Runtime contracts / Validation and native conversion in the [design](../../design/design.typ) and [ADR 0006](../../adr/0006-structural-witnesses-and-uncertified-callbacks.md). It preserves acceptance, exact numbers, first-error ordering, original values, synchronous execution, and caller-owned admission limits; no design contract changed.
- A separate consumer replay compared 58,936 inputs per runtime with the baseline, including exact validation, encoding, decoding, and rendered-JSON outcomes. The replay retained an exact production source snapshot under `oversight/.artifacts/object-validation-implementation-20261008/` and ran the three application-consumer scenarios on both targets.
- The package gate passed after the change: formatting, native checks, warning-free compilation, 244 Erlang and 243 Node root tests, 76 codegen/consumer tests per runtime, 85 finite schema cases across 16 frozen families, and 50 schema-profile fixtures. No ecosystem-wide gate, live service, browser, new concurrency measurement, or general JSON Schema conformance test was run.

## Reproduction

- Run from the package root with a new output directory; the runner refuses to overwrite an existing capture.

```sh
nix develop --command python3 scripts/contract_encoding_benchmark.py \
  --output docs/benchmarks/object-validation-rerun
nix develop --command sh scripts/gate.sh
```
