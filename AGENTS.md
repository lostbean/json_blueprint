# Agent instructions

- JSON Blueprint owns schema-aware values, codecs, schema projection and finite runtime contracts. Protocol admission, business policy and execution belong to consumers.
- Read the design (`docs/design/`), glossary, coverage and the relevant ADRs before changing behavior. Keep unbuilt intent in the pending ledgers and out of the present-tense design.
- Preserve the frozen root/schema 1.x surface and the separate dev-only package in `codegen/`. Package version changes require a release decision (ADR 0011).
- Strict Value parsing and standard JSON/native paths have different precision, duplicate-key and resource guarantees.

## Commands

- Full gate, in the Nix shell: `nix develop --command sh scripts/gate.sh` (formatting, tooling lint, native compilation, both-target tests for the root and `codegen/` packages, schema consumer, Python oracles).
- Focused checks: `sh scripts/check-schema-consumer.sh`, `python3 test/schema_check.py`, `python3 test/schema_profile_check.py`, `python3 -B -m unittest discover -s scripts -p 'test_*.py'`.
- Format named authored files with `nix fmt -- PATH...`. Benchmarks (`sh scripts/benchmark.sh`) are observations and never gate.
- Usage lives as compiled, executed code in `examples/` (codec topics in `examples/src/examples/`, the frozen 1.x API and the migration in `examples/test/`), run by the gate on both targets. Every README Gleam snippet must appear verbatim in an example module; `test/readme_example_test.gleam` fails when one drifts. Module documentation and the codegen consumer have their own executable checks.
- Run the examples alone with `cd examples && gleam run` and `gleam test --target erlang|javascript` in the Nix shell.
- After editing `docs/`, run the design-gate commands below sequentially (render, check, context estimate).

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

**Tracker** — GitHub issues in `lostbean/json_blueprint`, accessed with
`gh issue list --repo lostbean/json_blueprint` and `gh issue view NUMBER --repo lostbean/json_blueprint`.
Labels bind roles as follows: `needs-triage` → `needs-triage`,
`needs-info` → `question`, `ready-for-agent` → `ready-for-agent`,
`ready-for-human` → `ready-for-human`, `in-progress` → `in-progress`,
`done` → `done`, `wontfix` → `wontfix`, `bug` → `bug`,
and `enhancement` → `enhancement`.

**AI disclaimer** — AI-authored tracker comments start with
`AI-assisted contribution.`

**Design gate** — `nix run .#design-gate-check -- docs/design .` checks render freshness,
vocabulary references and layer integrity (exit 0 clean, 1 violation, 2 error).
The gate is supplied by the pinned `design-layer` flake input.
`nix run .#design-gate-render -- docs/design docs/design/design-layer.pdf`
rebuilds the rendered document. `nix run .#design-gate-context -- docs/design --estimate`
estimates agent context; the same command without `--estimate` emits ephemeral
Markdown. `--manifest`, `--preview`, and `--section PATH --expect-digest DIGEST`
support loading selected sections. A bare Typst compilation does not run the gate.

**Context verification** — use native semantic blocks for lists, tables,
models and behavior. After authoring, verify context estimation and a selected
section export as well as rendering and the design gate.
Run these commands sequentially for each layer; they share its generated
`.render` workspace.

**Staleness** — source changes since the design last changed require a
conformance review before the layer is treated as current.

<!-- agent-skills:end -->
