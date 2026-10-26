# Adopt JavaScript native parsing with strict evidence retention

<a id="adr-0015"></a>

- **Decision.** Adopt native `JSON.parse` with reviver source text, a scan for decoded duplicate names and malformed escaped surrogates, and direct built-in typed decoding. Custom callbacks materialize their Value subtree. Keep byte-only admission, scalar-valid host strings and exact numeric evidence until projection.
- **Supersedes.** ADR 0014's decision to retain the portable JavaScript parser pending an equivalent strict native path. The frozen legacy surface and version 2.0.0 remain unchanged.
- **Compatibility.** The owner selected modern runtimes and removal of the portable parser fallback on 2026-10-25. Require reviver source-text support and return explicit UnsupportedRuntime when unavailable. Feature introduction versions are Chrome 114, Firefox 135, Safari 18.4 and Node 21; executed engine versions and limits are recorded in `docs/BROWSER-SUPPORT.md`. The legacy API is unchanged.
- **Rationale.** The prototype materially reduced ordinary typed-decoding time and transient allocation. Native grammar ownership avoids maintaining another JSON grammar; a narrow scanner retains evidence native parsing otherwise discards.
- **Consequences.** Native syntax and raw Unicode diagnostics have unavailable locations. Malformed escaped surrogates report NativeSyntax. Multiply-invalid error precedence and integer-like object member order change. JavaScript retains its numeric representation limits. Native parsing allocates a complete tree before duplicate rejection; public Value parsing and custom callbacks still allocate Value nodes. The byte bound is not a heap quota.
- **Evidence.** The JavaScript hybrid capture and independent review in `experiment/js-hybrid-report.md` distinguish typed-codec gains from whole-Value behavior. Timings are observations, not release guarantees. Browser execution and final adoption measurements are recorded separately from the prototype.
