# Bound strict admission by bytes, depth, values, and number tokens

<a id="adr-0003"></a>

- **Decision.** Strict parsing rejects duplicate names and malformed Unicode, retains exact numbers, and applies independent finite resource bounds. Defaults are 1 MiB, depth 64, 262,144 values, and Number's token limits.
- **Rationale.** Text length alone does not bound the number of allocated tree nodes. Repeated-name map construction destroys evidence before a decoder can reject it. Input size must be checked before building the tree.
- **Alternatives.** An unbounded parser makes pathological input cost the application's problem. A byte-only parser admits dense arrays with excessive tree allocation. Standard `gleam/json` bridges are useful but accept that parser's number and duplicate-key policy.
- **Consequences.** Raising one limit does not silently raise another. Values created directly by callers, rendering, schema discovery, and callbacks have no parse-derived bound. Default resource measurements are evidence for these choices, not guaranteed heap quotas.
- **Evidence.** [Bounded parser change](https://github.com/lostbean/json_blueprint/commit/84a5fe4a981a8485e3fe7279a01eac32d755667c), dated 2026-10-02, carries the implementation. Oversight release decision D5 records the prior 10 MiB memory problem and the finite-default rationale. [Bounded tests](../../test/bounded_parsing_test.gleam), [parser](../../src/json/blueprint/value.gleam), and [README defaults](../../README.md#defaults) retain concrete limits and measurements.
