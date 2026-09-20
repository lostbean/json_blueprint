# Wave 3 Capability Report: JSON Blueprint

## 1. Baseline and Environment

- **Repository:** `/code/gleam-dream/json_blueprint`
- **Branch:** `implementation/schema-aware-core`
- **Starting Baseline Commit:** `fc8dae8d1c4eabf97d7ae8d4fa201cdc24f6b289`
- **Status:** Clean working tree
- **Target Mode:** Evolving repository on dedicated branch; oversight repository is read-only reference.

## 2. Oversight Files Read

- `/code/gleam-dream/oversight/docs/implementation/sinal-blueprint/wave-3-work-order.md`
- `/code/gleam-dream/oversight/docs/implementation/sinal-blueprint/review-2.md`
- `/code/gleam-dream/oversight/blueprint-design.md`
- `/code/gleam-dream/oversight/PUBLIC-API.md`
- `/code/gleam-dream/oversight/playground/interface_lab/SCHEMA-ORACLE.md`
- `/code/gleam-dream/oversight/playground/interface_lab/SCHEMA-ADMISSION.md`
- `/code/gleam-dream/oversight/playground/interface_lab/src/lab/blueprint.gleam`
- `/code/gleam-dream/oversight/playground/interface_lab/src/lab/blueprint_document.gleam`
- `/code/gleam-dream/oversight/playground/interface_lab/src/lab/blueprint_runtime.gleam`
- `/code/gleam-dream/oversight/playground/interface_lab/src/lab/blueprint_requirements.gleam`
- `/code/gleam-dream/oversight/playground/interface_lab/src/lab/value.gleam`
- `/code/gleam-dream/oversight/playground/interface_lab/src/consumers/schema_corpus.gleam`
- `/code/gleam-dream/oversight/playground/interface_lab/schema_check.py`

### Key Constraints Identified:
1. **Closed `Value` Algebra with Exact `Number` Leaf:** `Value` represents JSON null, boolean, string, number (`Number`), array, and object. Object values must retain duplicate key entries until checked rejection at the boundary.
2. **Complete Finite Facade End-to-End:** Implement bidirectional `Codec`, Draft 2020-12 schema emission, `RuntimeContract` normalization, `ValidatedValue`, structural validation, retained-codec native decoding, and strict document loading from parsed `Value`.
3. **Draft 2020-12 Schema Agreement:** Codec decoders, runtime validators, and Draft 2020-12 emitted schemas must agree on all instances in the independent 61-case oracle corpus.
4. **Preserve Legacy Behavior:** Retain 1.7.1 API and all 21 JavaScript legacy tests without degradation.

## 3. Tool Discovery and Verified Probes

### 1. Gleam Language Intelligence / LSP Bridge
- **Binary:** `/etc/profiles/per-user/edgar/bin/agent-lsp`
- **Transport:** Launched directly without shell wrappers (`nix develop --command` startup emits non-JSON banner `Gleam magic\n` which corrupts stdio MCP framing).
- **LSP Server:** `gleam:/nix/store/slbz68sp7dbmvhdl1gaxxrr12a898r7y-gleam-1.17.0/bin/gleam,lsp`
- **Workspace Initialization:** `start_lsp` with `root_dir: "/code/gleam-dream/json_blueprint"`, `language_id: "gleam"`.
- **Live Source Probe:** `inspect_symbol` on `/code/gleam-dream/json_blueprint/src/json/blueprint/number.gleam` at line 20, column 5.
- **Probe Result:** Succeeded; returned `InvalidSyntax` definition with symbol documentation.
- **Compiler Gate:** Local Gleam 1.17.0 toolchain (`gleam check --target erlang`, `gleam check --target javascript`, `gleam test`, `gleam format`) provides deterministic build, type-check, and test execution.

### 2. Web Search Capability
- **Tool:** `search_web`
- **Query:** `"JSON Schema Draft 2020-12 validation specification"`
- **Result:** Succeeded; returned current specification summary and official citations.

### 3. URL Fetch / Browser Capability
- **Tool:** `read_url_content`
- **URL:** `https://json-schema.org/draft/2020-12/json-schema-validation.html`
- **Result:** Succeeded; fetched live specification document.
