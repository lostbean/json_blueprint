# Prepared llm_wire integration patch

Validated 2026-10-25 against llm_wire 7baa807c618872ae96fffc0de3a5b74707b4bd71 in /tmp/llm-wire-byte-admission, using the native-direct-decoding Blueprint worktree as a temporary path dependency. The actual sibling checkout remains unchanged.

The patch updates classification admission tests and documentation for byte-only Blueprint parsing. Depth 65, 262,145 array elements within a raised byte budget, and a large exact numeric exponent reach classification decoding. Invalid syntax still fails before custom callbacks in live and stored-receipt flows. Two schema assertions now compare recursively sorted object members because JSON object order is not semantic. Existing separately implemented provider/transcription depth guards remain unchanged; no replacement classification structural policy was added.

Validation: `sh dev/gate fast` passes (403 Gleam tests, 3 Python tests, warnings-as-errors and native compilation). Design render and design gate pass; the gate retains the existing uncited ADR-0014 advisory. `gleam run` in examples/consumer passes against the temporary dependency. `git apply --check` passes against the unchanged sibling checkout.

Both root and nested example dependency manifests were reconciled through Gleam in the temporary copy. The patch intentionally excludes dependency overrides, manifests and the generated design PDF. Applying it requires a separately coordinated Blueprint dependency update, reconciliation of both manifests, design rendering and the full consumer gate. No live provider requests were made. Logs include intentional local TLS/reducer-failure test output.
