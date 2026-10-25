# Generate reviewable source with a separate development dependency

<a id="adr-0008"></a>

- **Decision.** The typed-definition generator is a dev-only package. Runtime applications use generated source and stable major-version runtime helpers. Schema materialization remains a distinct internal experiment. Full schema-driven native generation remains intended capability.
- **Rationale.** Generation needs explicit source references and a compiler to establish native types. Keeping it outside application dependencies avoids a runtime type-generation fiction and unnecessary generator machinery in the ordinary facade.
- **Alternatives.** A runtime schema cannot supply a compiled native type parameter. Emitting opaque callbacks without source references cannot reconstruct their code. Publishing every lowering helper as ordinary API adds compatibility obligations without ordinary consumer capability.
- **Consequences.** Named mappings pair functions with qualified references and need parity tests beyond compiler checks. Generated output is formatted, compiled, and drift-checked by the build owner. Schema-only materialization may allocate structure and does not establish constant evaluation. Stable names, wider/recursive shapes, CLI workflow, and schema-driven native generation remain incomplete obligations.
- **Evidence.** [Typed-definition generator](https://github.com/lostbean/json_blueprint/commit/d3f0708b61eddb4a4789c0476ab5384267814a51), dated 2026-09-20, and [dev-only split](https://github.com/lostbean/json_blueprint/commit/8f8b0dea4a41cfd19544463ac8a3d8beedb02ca2), dated 2026-10-02, establish current placement. [Generator](https://github.com/lostbean/json_blueprint/blob/ada6bb18e1b1f5ba3ecb7cfd86fa26e0560d9ac3/codegen/src/json/blueprint/codegen.gleam), [materializer](https://github.com/lostbean/json_blueprint/blob/ada6bb18e1b1f5ba3ecb7cfd86fa26e0560d9ac3/codegen/src/json/blueprint/codegen/internal/schema_materialize.gleam), and [compiled fixtures](https://github.com/lostbean/json_blueprint/blob/ada6bb18e1b1f5ba3ecb7cfd86fa26e0560d9ac3/codegen/test/compiled_codec_test.gleam) establish current scope. Oversight's `research/blueprint-generation-contract.md` and `blueprint-design.md` retain the broader scope; their original acceptance dates are unknown.

## Closed-object schema generation decision, 2026-10-08

- **Decision.** Add a pure development-time generator from an admitted closed-object Schema to public native record types and a root Codec accessor. The existing typed-definition generator remains available for caller-authored native types and named mappings.
- **Rationale.** Ordinary public codec combinators already own primitive conversion, record construction, optionality, exact numbers, and value constraints. Emitting those combinators avoids maintaining a second validator or a second specialized emitter while Gleam checks generated structural types.
- **Naming.** Explicit root naming and deterministic nested naming produce reviewable source. Invalid names and collisions fail with their logical schema locations; silent ordinal disambiguation would make unrelated schema edits rename public types. Naming overrides and shared definitions require a separate contract.
- **Tradeoff.** Native Int projection may refuse a mathematically valid wire integer, while exact Number retains mathematical values. Generated native types do not make bounded values intrinsically valid, so encoding continues to run the ordinary codec's value checks.
- **Alternatives.** Routing generated records through Value and contract validation would repeat structural work already enforced by the compiled type. Extending the specialized typed-definition emitter would duplicate lowering responsibilities before a compiled schema consumer demonstrates a need for that complexity.
- **Evidence boundary.** Separate consumer compilation, acceptance and recovery tests, deterministic regeneration, and target-specific native projection checks establish behavior. CPU and allocation benchmarks evaluate cost independently; neither favorable measurements nor a compiling fixture establish whole-profile parity.
- **Remaining scope.** Enums, unions, shared or recursive definitions, selected naming overrides, general CLI workflow, and broader evolution fixtures remain pending. This decision narrows the first implementation slice without retiring those obligations.

## Closed-object implementation acceptance, 2026-10-08

- **Portability.** Generated integer codecs preserve Erlang's supported native bounds instead of silently narrowing the schema to JavaScript's safe-integer range. Callers compile and check generated source for each intended target; the shared consumer corpus covers portable bounds, while exact Number keeps a separate representation contract.
- **Construction.** Generated accessors prebind child codecs and exact bounds before record continuations. Retaining one constructed codec avoids repeating that setup during field conversion without introducing a global cache or changing caller ownership.
- **Determinism.** Original wire names sort by Unicode codepoint order across runtimes. Normalization starts a new underscore-separated word for each uppercase ASCII letter, so acronym handling has one explicit rule instead of target-dependent segmentation.
- **Acceptance.** The [separate consumer](https://github.com/lostbean/json_blueprint/blob/ada6bb18e1b1f5ba3ecb7cfd86fa26e0560d9ac3/codegen/consumer/README.md), [regeneration and isolated-build check](../../scripts/check-schema-consumer.sh), and package gate established the closed-object slice on Erlang and Node. The consumer keeps generation effects outside the production dependency graph and exercises an application envelope, domain policy, located recovery, native projection, and missing/null/value distinctions.
- **Measurement.** The retained results under `docs/benchmarks/schema-generation-2026-10-08/` record generation, codec construction, CPU, and allocation separately, per trial and with source provenance; raw command output is not retained, and [BENCHMARKS.md](../BENCHMARKS.md#schema-driven-generation-2026-10-08) summarizes it; [ADR-0010](0010-retain-benchmark-observations-as-non-asserting-evidence.md#adr-0010) records its findings. Measurements support cost comparisons for those fixtures; broader generation and conformance obligations remain unresolved.

## Package consolidation, 2026-10-25

- **Decision.** Include the source generators in `json_blueprint`, preserving
  `json/blueprint/codegen` and `json/blueprint/codegen/schema` as their import
  paths. This supersedes the separate development-package placement above.
  Generation remains an explicit build or test operation: functions return source,
  and the caller writes, formats and compiles it.
- **Tradeoff.** One dependency and release version keep generator and runtime
  helpers aligned without adding external dependencies. All installations include
  generator source and compile its modules; the generator API shares the package's
  compatibility and release commitments.
- **Consumers.** Remove the separate `json_blueprint_codegen` dependency. The
  [generation example](../../examples/codegen/README.md) uses only JSON Blueprint
  in its generation task and production application. Production conversion does
  not invoke generation.
- **Evidence.** [Generator source](../../src/json/blueprint/codegen.gleam),
  [schema generator](../../src/json/blueprint/codegen/schema.gleam),
  [compiled parity fixtures](../../test/compiled_codec_test.gleam) and the
  [isolated consumer check](../../scripts/check-schema-consumer.sh) cover the
  consolidated boundary on both targets. The release-version hold in ADR 0011
  remains in force.
