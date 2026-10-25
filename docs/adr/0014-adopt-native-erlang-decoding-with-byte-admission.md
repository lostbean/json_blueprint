# Adopt native Erlang decoding with byte admission

<a id="adr-0014"></a>

- **Decision.** Adopt OTP JSON parsing with duplicate-key detection, exact native integers and deferred decimal tokens. Built-in codecs decode this native tree directly; custom Value callbacks convert their subtree. Keep a configurable 1 MiB default byte limit. Remove global depth, value-count and numeric-token admission limits. Consumers own further structural policy. JavaScript retains its exact parser until a native path can preserve duplicate detection and precision.
- **Supersedes.** The independent admission bounds in ADR 0003. Explicit standalone `number.parse` limits and the checked native projections in ADR 0002 remain available. The frozen legacy API and release version remain unchanged.
- **Rationale.** Native parsing and avoiding the intermediate Value tree reduced runtime and peak memory in the local prototypes. Retaining global structural admission required another scan and recovered much of the overhead. The owner selected byte-only admission on 2026-10-25; consumers such as llm_wire may inspect decoded structure.
- **Consequences.** A byte bound is not a memory or recursion quota. Erlang object source order and detailed old parser locations are not retained. Complete syntax admission precedes typed callbacks; duplicate names reject before typed decoding. JavaScript exponents remain constrained by its exact native integer representation. Custom callbacks and Value parsing still allocate Value nodes.
- **Evidence.** `experiment/MITIGATION.md` and the dated benchmark artifacts record the prototypes. Production integration must be evaluated separately; prototype timings are not a release performance guarantee.
