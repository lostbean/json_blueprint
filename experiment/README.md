# Parser experiment evidence

These files retain historical experiments and measurements. Production behavior is documented in ../docs/NATIVE-DECODING-ADOPTION.md; adoption-report.md and adoption-results.json describe the measured production integration.

Disposable Gleam and FFI modules live under prototypes/ and are excluded from ordinary compilation and gates. To reproduce an older experiment, copy its modules into a disposable package with the corresponding source snapshot; older bounded prototypes use APIs intentionally removed by adoption. Earlier reports describe the state at their capture date, not the current implementation.

adoption_run.py records its original prepared workspaces and does not overwrite evidence. Restore the archived runner modules into a disposable benchmark package before rerunning it. Never overwrite captured JSON to disguise a later run.
