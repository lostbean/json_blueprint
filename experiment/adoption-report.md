# Native codec adoption measurements

The production Erlang codec decoder is faster than the freshly rebuilt optimized strict-parser baseline on all six measured typed workloads. The largest gains occur when decoding native floats and large integer arrays. JavaScript still uses the portable parser and shows no general improvement; the small-record median was about 7% slower in this capture.

Both paths call `codec.decode_json` through the same benchmark runner. The baseline source was copied unchanged from the `strict-parser-optimization` worktree into `/tmp/blueprint-adoption-baseline`. Production uses the `native-direct-decoding` worktree after the source-retention and exponent-parsing repairs. Source hashes were checked before and after measurement.

| Target | Workload | Baseline µs | Production µs | Baseline / production |
|---|---|---:|---:|---:|
| erlang | small_record | 2.071 | 1.254 | 1.65× |
| erlang | response_50 | 99.127 | 55.881 | 1.77× |
| erlang | ints_10000 | 2,226.652 | 1,162.092 | 1.92× |
| erlang | ints_limit | 235,952.834 | 41,344.458 | 5.71× |
| erlang | decimals_1000 | 3,475.361 | 269.134 | 12.91× |
| erlang | exact_numbers_1000 | 962.263 | 773.055 | 1.24× |
| javascript | small_record | 10.545 | 11.280 | 0.93× |
| javascript | response_50 | 383.207 | 387.253 | 0.99× |
| javascript | ints_10000 | 10,196.231 | 10,018.699 | 1.02× |

The 524,287-byte input containing 262,143 zero integers took 236 ms on the optimized baseline and 41.3 ms in production. Median total-process peak RSS fell from 178.94 MiB to 127.88 MiB. Retained Erlang process memory after garbage collection was effectively unchanged at 6.36 MiB: both decoders return the same typed list. The reduced peak concerns intermediate parsing work, not a smaller returned value.

For JavaScript, the response and 10,000-integer timing ranges overlap. The small-record VM medians were 10.062–10.563 µs for the baseline and 11.167–12.338 µs in production. This capture supports reporting a small-record regression, not claiming JavaScript parity or attributing its cause to a particular change.

Each result is the median of three fresh-VM medians; every VM performs warmup followed by five timed batches. Memory uses separate fresh VMs, retains the observable decoded result, then forces garbage collection for the retained-memory snapshot. Peak RSS comes from per-child `wait4` and includes the runtime, input, intermediates and result; it is not allocated bytes or a heap quota. Baseline runs preceded production runs. Other repository checks were paused, but CPU frequency and host isolation were not controlled.

Environment: macOS-27.0.1-arm64-arm-64bit-Mach-O; gleam 1.19.2; OTP 29 ERTS 17.1.1; Node v24.21.0; Python 3.14.7. Erlang used `+S 1:1`. No timing threshold is a gate.

Erlang fixtures verify typed results against the experimental lossless path before timing. JavaScript timing invokes successful production decoding but does not invoke the Erlang-only lossless comparator; codec regression tests provide its separate behavioral evidence. These are application-level typed decoding measurements, not ordinary `JSON.parse` comparisons or evidence for browser performance, concurrent capacity, arbitrary adversarial inputs or full schema conformance.

Raw trials, source and fixture hashes, timing ranges, retained-memory snapshots and toolchain versions are in [adoption-results.json](adoption-results.json). The capture harness is [adoption_run.py](adoption_run.py); it expects the named prepared baseline and refuses to overwrite the results file.
