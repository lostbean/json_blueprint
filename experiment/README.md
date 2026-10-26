# Parser experiment evidence

These files retain historical experiments and measurements. Current behavior is documented in [the migration guide](../docs/MIGRATION.md), [browser support](../docs/BROWSER-SUPPORT.md) and ADRs 0014–0015. adoption-report.md and adoption-results.json describe the earlier Erlang integration.

Disposable Gleam and FFI modules live under prototypes/ and are excluded from ordinary compilation and gates. To reproduce an older experiment, copy its modules into a disposable package with the corresponding source snapshot; older bounded prototypes use APIs intentionally removed by adoption. Earlier reports describe the state at their capture date, not the current implementation.

adoption_run.py records its original prepared workspaces and does not overwrite evidence. Restore the archived runner modules into a disposable benchmark package before rerunning it. Never overwrite captured JSON to disguise a later run.

## JavaScript hybrid evidence

The js-hybrid-report.md, js-hybrid-benchmark-report.md and js-hybrid-review-report.md
files describe the initial prototype, including its then-retained portable fallback
and diagnostic test differences. Their captured results and logs are historical.
The fallback was subsequently removed and the documented native diagnostics were
adopted; the current full gate passes.

Final native-only timings and memory are recorded in
[the benchmark document](../docs/BENCHMARKS.md) and its source-hashed captures.
js-hybrid-browser-results.json records the final three-engine run. The final
independent checks are retained in js-hybrid-review-native-only-public.json and
js-hybrid-review-native-only-numbers.json (8,327 public checks and 5,904 numeric
cases, no failures). The ordinary gate also tests explicit unsupported-runtime
refusal, callback suppression and unchanged legacy decoding.

js-hybrid-benchmark.py remains a reproducible current-versus-baseline harness.
The older fallback review runner must be used with its historical source snapshot;
it does not describe the native-only implementation.
