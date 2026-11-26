# Accept and ignore annotation keywords

<a id="adr-0021"></a>

- **Decision.** Contract loading accepts and ignores the Draft 2020-12 annotation keywords, which never constrain an instance: the meta-data vocabulary (`title`, `description`, `default`, `examples`, `deprecated`, `readOnly`, `writeOnly`) and the core `$comment` and `$id`. `description` stays retained where the codec model holds one. Each annotation must still have its meta-schema type; a wrong type is malformed at its path.
- **Extends.** The finite profile of [ADR-0001](0001-schema-aware-ownership-and-finite-support.md#adr-0001), which refused every keyword outside the profile. The owner ruled on 2026-11-25 that annotations are accepted. The rest of ADR-0001 stands.
- **Problem.** Schemas emitted by Pydantic and Zod, and MCP tool schemas, carry annotations on almost every node. Refusing them refused schemas whose constraints fit the profile.
- **Scope.** Every keyword that constrains a value stays refused, including `format` and the content keywords (`contentEncoding`, `contentMediaType`, `contentSchema`). Draft 2020-12 treats them as annotations by default, but they state a constraint the author expects a validator to enforce, so ignoring them would discard that constraint without notice. `$ref`, `$defs` and `$anchor` stay refused; reference support is a separate decision.
- **Consequences.** Schemas with a dialect, closed objects and annotations now load when their constraints fit the profile. The rationale of ADR-0001 that no constraint is discarded without notice still holds, because an annotation is not a constraint.
- **Evidence.** `test/contract_annotation_test.gleam` loads Pydantic, Zod and MCP tool schemas, checks that each annotation is ignored for validation, that a wrong annotation type is malformed at its path, and that the constraining keywords above are refused.
