# Agent instructions

- JSON Blueprint owns schema-aware values, codecs, schema projection and finite runtime contracts. Protocol admission, business policy and execution belong to consumers.
- Read the local design, glossary, coverage and relevant ADRs before changing behavior. Keep intended extensions visible without claiming they are implemented.
- Preserve the frozen root/schema 1.x surface and the separate dev-only package in `codegen/`. Package version changes require a release decision.
- README Gleam snippets, module documentation, legacy examples and codegen examples have executable checks. Keep prose and checked examples aligned.
- Use the repository Nix shell for `sh scripts/gate.sh`. Strict Value parsing and standard JSON/native paths have different precision, duplicate-key and resource guarantees.
- A passing documentation gate does not establish general JSON Schema conformance, complete legacy compatibility, or every numeric projection law.

<!-- agent-skills:begin -->
<!-- framework-commit: cab7c0590036edaa66d8430cc5016399a9fd2c71 origin: git@github.com:lostbean/skills.git -->

(machine-owned; do not edit inside this fence — re-run setup to refresh)

## Agent skills

**Design layer** — `docs/design/design.typ` describes the design,
`docs/design/CONTEXT.typ` defines its vocabulary, and `docs/adr/` records
decision rationale. The rendered document is `docs/design/design-layer.pdf`.
`docs/COVERAGE.md` maps repository parts to their design owners.

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
