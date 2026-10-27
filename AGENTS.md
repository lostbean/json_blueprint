# Agent instructions

- JSON Blueprint owns schema-aware values, codecs, schema projection and finite runtime contracts. Protocol admission, business policy and execution belong to consumers.
- Read the design (`docs/design/`), glossary, coverage and the relevant ADRs before changing behavior. Keep unbuilt intent in the pending ledgers and out of the present-tense design.
- Preserve the frozen root/schema 1.x surface. Source generators belong to this package and run through explicit build tasks. Version 2.0.0 is the published baseline (ADR 0013); further version changes require an explicit release decision.
- Strict Value parsing and standard JSON/native paths have different precision, duplicate-key and resource guarantees.

## Commands

- When updating dependency pins, reconcile affected `manifest.toml` files in examples, consumers and nested packages through Gleam, then run the full repository gate; updating the root lock alone is insufficient.

- Application checks, in the Nix shell: `nix develop --command sh scripts/gate.sh` (native compilation, both-target tests for the runtime and generators in the root package, schema consumer, Python oracles).
- Focused checks: `sh scripts/check-schema-consumer.sh`, `python3 test/schema_check.py`, `python3 test/schema_profile_check.py`, `python3 test/number_check.py` (independent Erlang arithmetic oracle).
- Format named authored files with `nix fmt -- PATH...`. Benchmarks (`sh scripts/benchmark.sh`) are observations and never gate.
- Usage lives as compiled, executed code in `examples/` (codec topics in `examples/src/examples/`, the frozen 1.x API and the migration in `examples/test/`), run by the gate on both targets. Compiled module examples and the codegen consumer run as behavioral tests; README and module-documentation text is reviewed manually.
- Run the examples alone with `cd examples && gleam run` and `gleam test --target erlang|javascript` in the Nix shell.

## References

- [`docs/ORACLE.md`](docs/ORACLE.md) pins the independent Draft 2020-12 validator (`jsonschema` 4.26.0 through `flake.lock`), the frozen 85-case manifest and the profile fixtures this package is compared against, with the limits of that claim.
- [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md) holds the benchmark method, provenance and dated local observations. Timing never gates a change, and the two documents cross-link.
- [`examples/README.md`](examples/README.md) lists the compiled usage examples.

<!-- agent-skills:begin -->
<!-- framework-commit: cab7c0590036edaa66d8430cc5016399a9fd2c71 origin: git@github.com:lostbean/skills.git -->

(machine-owned; do not edit inside this fence — re-run setup to refresh)

## Agent skills

**Design layer** — `docs/design/design.typ` is the root design document, and
`docs/CONTEXT-MAP.md` indexes the contexts (`contracts` and `generation`), each
with its own `design.typ` and `CONTEXT.typ` under `docs/design/<context>/`.
`docs/adr/` records decision rationale. The layer renders to one document,
`docs/design/design-layer.pdf`. `docs/COVERAGE.md` maps repository parts to
their design owners.

**Tracker** — local markdown under `issues/`: one directory per feature
(`issues/<feature-slug>/`), the PRD at `issues/<feature-slug>/PRD.md`, issue
files at `issues/<feature-slug>/issues/<NN>-<slug>.md` numbered from 01. Each
issue file carries two header lines near the top — `Status: <state>`,
`Category: <category>`. Conversation appends to the bottom
of the file under a `## Comments` heading. Labels (canonical strings, adopted
verbatim): states `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `in-progress`, `done`, `wontfix`; categories `bug`,
`enhancement`.

**AI disclaimer** — AI-authored tracker comments start with
`AI-assisted contribution.`

**Design tools** — `nix run .#design-gate-render -- docs/design docs/design/design-layer.pdf`
renders the design. `nix run .#design-gate-context -- docs/design --estimate`
estimates context. CI calls the shared validator directly with
`nix run .#design-gate-check -- docs/design .`. Run `nix flake check` separately
for repository formatting. Local test scripts own application compilation and behavior.

<!-- agent-skills:end -->

## README snippets

Keep README Gleam examples in compiled example or consumer source. Use named
`snips-start` / `snips-end` regions (or include a whole example module), and retain
Prettier ignore ranges around generated README blocks. Format the source first,
then run `nix run .#snips -- --commands deny README.md`. CI runs
`nix run .#snips -- --check --commands deny README.md` using the shared pinned
package. Snips checks synchronization; existing example tests check behavior.

## Commit messages

Use a concise subject and an optional explanatory body. Do not add any commit
footers or trailers, including `Co-authored-by`, `Signed-off-by`, `Reviewed-by`,
`Acked-by`, or tool/AI attribution. Do not use `git commit --signoff` or let an
automated tool append a footer. Tracker-comment attribution rules apply only to
tracker comments, never to commit messages.
