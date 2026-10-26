# Generated specialization adoption — 2026-10-26

The adopted direct emitter retains the prototype's performance gains. Strict
generated decoding uses the shared parser's native tree; the generated Codec
also uses its specialized text encoder. No additional parser is introduced.

Baseline: `54ecf5cc7da806cd97fe481fde7c32382e36dc12`, with the existing benchmark
additions. Candidate: the adoption working tree, identified by source hashes in
[small.json](small.json) and [responses.json](responses.json). A later three-line
module-documentation edit does not change the measured implementation. The
benchmark snapshots are isolated from subsequent test and documentation edits.

## Small record

Three fresh processes per target and variant, 200 warmups and 1,000 operations;
median of process means in microseconds. Baseline ran before candidate; no CPU
pinning. Small differences are not reliable evidence of a speed change.

| Operation | Before E / JS | Adopted E / JS | Runtime E / JS |
| --- | ---: | ---: | ---: |
| Reused generated Codec strict decode | 3.162 / 18.614 | 2.507 / 9.382 | 2.848 / 10.756 |
| Reused generated Codec text encode | 2.911 / 8.983 | 1.514 / 7.039 | 3.230 / 9.386 |
| Generated schema accessor | 0.018 / 0.098 | 0.018 / 0.093 | 0.549 / 5.270 |
| Generated schema JSON rendering | 13.090 / 13.401 | 13.366 / 10.188 | 13.981 / 16.601 |

The final prototype measured 2.525 / 9.344 µs for generated strict decode and
1.520 / 7.198 µs for generated text encode. The durable emitter remains close
to those observations. Schema JSON is still rendered at runtime; specialization
does not precompute JSON text. All cases, ranges and construction observations
are retained in `small.json`.

## Repeated records and peak memory

144 fresh VMs: three per variant, target, shape, decoder and measurement mode,
alternating variant order. Timing uses one warmup batch and five timed batches;
reported values are medians of VM medians. Memory uses a separate VM with one
decode. Erlang uses `+S 1:1`. Payloads contain 50 records (6,051 bytes) and 5,000
records (605,001 bytes), below the default byte limit. An ordinary runtime list
wraps the generated record codec. Fixture acceptance and first-record contents
are checked before timing is reported.

| Decode workload | Before generated | Adopted generated | Runtime | Vanilla |
| --- | ---: | ---: | ---: | ---: |
| Erlang, 50 records | 238 µs | 176 µs | 194 µs | 166 µs |
| JavaScript, 50 records | 801 µs | 396 µs | 418 µs | 224 µs |
| Erlang, 5,000 records | 27.14 ms | 17.77 ms | 20.79 ms | 20.14 ms |
| JavaScript, 5,000 records | 86.31 ms | 42.08 ms | 46.24 ms | 25.90 ms |

Vanilla uses weaker admission guarantees. This representable fixture does not
measure the cost or semantics of exact decimal projection. The prototype's
generated 50-record results were 170 / 390 µs, and 5,000-record results were
17.85 / 40.83 ms. The adoption results are consistent with those observations;
they do not establish a statistically significant difference from the prototype.

| 5,000-record peak RSS | Before generated | Adopted generated | Runtime | Vanilla |
| --- | ---: | ---: | ---: | ---: |
| Erlang | 92.88 MiB | 88.92 MiB | 94.44 MiB | 88.89 MiB |
| JavaScript | 87.80 MiB | 80.12 MiB | 84.39 MiB | 78.00 MiB |

RSS includes the runtime, module loading, input and retained result. It is not
isolated heap usage or allocation volume. Prototype generated RSS was 88.33 /
79.80 MiB. Version metadata, every trial and ranges are in `responses.json`.

## Reproduction and limits

The retained `runner.py` and `prototype_bench.gleam` are the experiment harness,
formatted with repository tools. Copy the Gleam harness into `test/` in each isolated source snapshot,
then run the Python runner in the pinned Nix environment with `--baseline`,
`--candidate`, `--output` and `--build`. The normal small suite is
`gleam run --target erlang|javascript -m bench_test`.

Source emission now selects decoder types and helpers directly instead of
rewriting emitted source. It adds 268 authored lines including documentation
across the codec, generator and helpers. Generated Order output grows from 914
to 1,126 lines. Explicit Value and standard-native APIs remain supported.
Ordinary outer composition uses Value encoding; full-definition generation
specializes the complete encoder. Timing is never a correctness gate. See
[ORACLE.md](../../ORACLE.md) for the independent correctness evidence and its
limits, and [MIGRATION.md](../../MIGRATION.md) for behavioral boundaries.

Final adoption validation passed: 382 Erlang and 387 JavaScript root tests,
24 example tests and 10 generated consumer tests per target, fresh generation
and isolated production compilation, and all schema, numeric, parser and
source-text oracles in `scripts/gate.sh`. Formatting, README snippet freshness
and the rendered design gate also passed. No release was cut.
