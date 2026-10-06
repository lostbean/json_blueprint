# Keep schema-aware conversion in Blueprint and expose finite support

<a id="adr-0001"></a>

- **Decision.** Blueprint owns exact JSON values, typed schema-aware codecs, schema discovery, and runtime contracts. Consumers own protocol/provider admission and execution. Ordinary serialization does not require Blueprint.
- **Rationale.** A retained codec supplies conversion and discoverable shape without making transport, tool registration, or workflow execution its responsibility. Separating schema-aware paths keeps ordinary JSON consumers independent.
- **Alternatives.** A shared mandatory codec layer would add a schema dependency to ordinary serialization. Consumer-local schema copies would permit publication and conversion to drift. A general-schema support claim would exceed the implemented finite interpreter.
- **Scope.** Full intended scope retains string/numeric/collection constraints, wider objects and alternatives, numeric enums, aliases, references, recursive codecs, raw unsupported schema data, schema evolution, and native source generation. Finite initial support does not cancel those families. Concrete limits and semantics remain unresolved where the design names them.
- **Evidence.** [Finite schema implementation](https://github.com/lostbean/json_blueprint/commit/cf378926647ed83dc0669f49d4bb8591b5e1381f) is dated 2026-09-20 in local Git. Scope and consumer ownership are retained from oversight's `blueprint-design.md`, `PUBLIC-API-GUIDELINES.md`, and release API report/plan. The initial historical discussion date and complete rationale for every retained family are unknown; this record captures the evidenced boundary without inventing approval.
- **Contract gap.** Current [loader](../../src/json/blueprint/contract.gleam) requires explicit closed-object members. A valid default-open schema can receive a malformed-profile error. Changing its classification or broadening external MCP support requires a separate decision; this migration does neither.
