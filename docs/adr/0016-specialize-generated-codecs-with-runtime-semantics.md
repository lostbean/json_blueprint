# Specialize generated codecs with runtime semantics

<a id="adr-0016"></a>

- **Decision.** The typed-definition generator emits specialized text encoders,
  strict native-tree decoders and schema structures. Its codec accessor registers
  the specialized functions so ordinary codec operations use them. Emit directly
  from the lowering model; do not transform previously emitted source text.
- **Semantics.** Generated codecs preserve runtime conversion results, located
  failures, optional states and conversion callback order for supported definitions
  and faithful pure named mappings. Generated schema and known-field metadata
  do not replay runtime placeholder introspection or promise identical callback
  counts during discovery. Strict admission remains the shared parser on both
  targets, including duplicate-key rejection, exact numeric evidence, Unicode
  validation and byte limits. No new parser or global cache is introduced.
- **Compatibility.** The shared generated Value decoder uses runtime field-first
  error precedence, including for existing generated modules. Regenerated
  accessors evaluate mapped placeholders on demand rather than at construction. The explicitly named standard-native decoder remains
  separate and weaker. Frozen legacy APIs and version 2.0.0 are unchanged.
- **Tradeoff.** Specialized output is larger than ordinary combinator output,
  but avoids interpretation and intermediate Value construction during strict
  decoding. Ordinary container and map composition retains behavior and direct
  child decoding while using Value encoding; generating the whole definition
  specializes its text encoder. Schema structures avoid rediscovery, while
  rendering schema JSON still performs runtime work.
- **Scope.** Named source references remain a caller trust boundary. Exact
  Number compilation, recursive definitions and broader schema-driven generation
  are not added. The schema-driven generator continues to emit ordinary codecs.
- **Evidence.** Compiled fixtures and runtime parity tests exercise both targets.
  The [benchmark record](../BENCHMARKS.md) separates measured workloads and
  memory observations from correctness guarantees. This decision extends the
  typed generator in [ADR 0008](0008-development-time-source-generation.md)
  without replacing its schema-driven generator.
