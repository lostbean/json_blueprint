# Benchmarks

The measurements below are retained local results from earlier implementations.
They were not rerun for this documentation change and do not describe a
published 2.0 release or guarantee current performance.

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
