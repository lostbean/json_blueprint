# Wave 2 Capability Report

## Baseline and Environment
- Repository: `/code/gleam-dream/json_blueprint`
- Branch: `implementation/schema-aware-core`
- Starting Baseline Commit: `25d554b0bdde421bd2037f68253315ebc0ab3090`
- Status: Clean working tree

## Oversight Files Read
- `/code/gleam-dream/oversight/docs/implementation/sinal-blueprint/wave-2-work-order.md`
- `/code/gleam-dream/oversight/docs/implementation/sinal-blueprint/review-1.md`
- `/code/gleam-dream/oversight/blueprint-design.md`
- `/code/gleam-dream/oversight/PUBLIC-API.md`
- `/code/gleam-dream/oversight/research/blueprint-number-policy.md`
- `/code/gleam-dream/oversight/playground/interface_lab/EXACT-NUMBERS.md`
- `/code/gleam-dream/oversight/playground/interface_lab/number_check.py`
- `/code/gleam-dream/oversight/playground/interface_lab/src/consumers/json_numbers.gleam`

Key Constraint Identified:
One canonical exact `Number` is the only JSON numeric leaf in `Value`. Conversions between `Number` and native types (`Int`, binary64 `Float`) are explicit checked projections. Parsing, canonical formatting, mathematical integrality, and comparison must never convert through machine `Float` or legacy `Dynamic`.

## Tool Discovery and Probes

### 1. Gleam Language Intelligence / LSP
- Bridge Location: `/etc/profiles/per-user/edgar/bin/agent-lsp`
- Initial Discovery Note: `which agent-lsp` failed inside the default dev shell PATH, but the bridge binary is installed at `/etc/profiles/per-user/edgar/bin/agent-lsp`.
- Real Source Probe: Launched `agent-lsp` with the project Gleam LSP server (`gleam:/nix/store/slbz68sp7dbmvhdl1gaxxrr12a898r7y-gleam-1.17.0/bin/gleam,lsp`), initialized workspace at `/code/gleam-dream/json_blueprint` via `start_lsp`, and invoked `inspect_symbol` on `/code/gleam-dream/json_blueprint/src/json/blueprint/number.gleam` line 20, column 5.
- Result: Succeeded. `inspect_symbol` returned the exact symbol type `InvalidSyntax`.
- Complementary Deterministic Gate: Local Gleam 1.17.0 compiler (`gleam check --target erlang` and `gleam check --target javascript`) used for deterministic full-project type checking.

### 2. Web Search Capability
- Probe: Invoked `search_web` for `"JSON Schema Draft 2020-12 core"`.
- Result: Available and functional; returned current summary and source citations for Draft 2020-12 specifications.

### 3. URL Fetch / Browser Capability
- Probe: Invoked `read_url_content` on the official Blueprint oracle URL:
  `https://json-schema.org/draft/2020-12/json-schema-core.html`.
- Result: Successfully fetched live HTML content into local step storage; confirmed accessibility of Draft 2020-12 core specification.
