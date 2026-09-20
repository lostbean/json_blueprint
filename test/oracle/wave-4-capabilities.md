# Wave 4 Capability Report: JSON Blueprint

## 1. Baseline and Environment

- **Repository:** `/code/gleam-dream/json_blueprint`
- **Branch:** `implementation/schema-aware-core`
- **Starting Baseline Commit:** `cf378926647ed83dc0669f49d4bb8591b5e1381f`
- **Status:** Clean working tree
- **Target Mode:** Full release-completion wave on dedicated branch; oversight repository is read-only reference.

## 2. Review-3 Findings to Resolve First

1. **Tagged Non-String Discriminator Error:**
   - Problem: `codec.gleam` maps any non-successful tag pattern to `DecodeMissingTag`, causing wire objects with a present non-string (e.g. numeric or boolean) tag to be reported as missing tag rather than wrong type.
   - Solution: Return a structured wrong-type error at the `tag` field (`DecodeAtField("tag", CannotDecode(DecodeExpectedString))`) distinguishing present non-string tag from missing tag and missing payload.
2. **Deterministic 61-Case Manifest:**
   - Problem: `schema_check.py` previously accepted any nonempty list with true and false outcomes.
   - Solution: Enforce an exact 61-case manifest with frozen 13-family case counts and unique case identities, rejecting missing, duplicate, or extra cases.
3. **Cross-Target JavaScript Facade Tests:**
   - Problem: Facade tests were previously marked `@target(erlang)`.
   - Solution: Implement full JavaScript exact-number parity so the full facade and number tests execute on both Erlang and JavaScript targets.

## 3. Tool Discovery and Verified Probes

### 1. Gleam Language Intelligence / LSP Bridge
- **Binary:** `/etc/profiles/per-user/edgar/bin/agent-lsp`
- **Transport:** Direct process execution via `stdio` MCP JSON-RPC protocol, avoiding shell wrappers that emit startup banners (`Gleam magic\n`) on stdout.
- **Server:** `gleam:/nix/store/slbz68sp7dbmvhdl1gaxxrr12a898r7y-gleam-1.17.0/bin/gleam,lsp`
- **Workspace Initialization:** `start_lsp` with `root_dir: "/code/gleam-dream/json_blueprint"`, `language_id: "gleam"`.
- **Live Source Probe:** `inspect_symbol` on `/code/gleam-dream/json_blueprint/src/json/blueprint/codec.gleam` at line 18, column 10 (`CannotEncode`).
- **Probe Result:** Succeeded; returned `CannotEncode(reason: EncodeReason)` definition and documentation.
- **Deterministic Gates:** Nix dev shell provides local Gleam 1.17.0 compiler, Erlang/OTP 28, and treefmt formatting tools.

### 2. Verified Oracle Tools
- `search_web` and `read_url_content` were proven in Wave 3 (`https://json-schema.org/draft/2020-12/json-schema-validation.html`).
- Oversight design documents and test oracles (`blueprint-design.md`, `PUBLIC-API.md`, `schema_corpus.gleam`, `schema_check.py`, `number_check.py`) are directly verified from read-only `/code/gleam-dream/oversight`.
