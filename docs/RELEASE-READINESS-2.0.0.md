# JSON Blueprint 2.0.0 release-readiness review

## Current assessment — 2026-10-26

The specialized generated-code adoption is locally validated and has no known
unresolved correctness blocker in the reviewed paths. This is a release
candidate with a successful local package preview. No release or tag has been cut.

- Full repository gate: 382 Erlang and 387 JavaScript root tests; 24 example
  tests and 10 generated-consumer tests per target; fresh generated compilation,
  isolated production compilation, and all independent oracles pass.
- Host formatting, README snippet synchronization and rendered design checks
  pass. Browser execution evidence for the JavaScript hybrid is retained in
  [BROWSER-SUPPORT.md](BROWSER-SUPPORT.md); the subsequent generated-code change
  has been executed on Erlang and Node, not rerun in browsers.
- Local `gleam export hex-tarball` and `gleam docs build` pass. The package
  contains runtime/generator source and both FFI targets, excludes tests and
  experiment evidence, and the generated documentation includes the migration
  page. A root MIT license now accompanies the existing MIT package declaration.
- Runtime/generated parity tests cover strict duplicate admission, numeric
  projection, Unicode, byte limits, located errors, optional fields and mapping
  conversions. Pure mappings are required: cached metadata skips placeholder
  introspection. Generated objects cannot finish record-builder continuations.
  These limits and migration details are in [MIGRATION.md](MIGRATION.md).
- [ADR 0016](adr/0016-specialize-generated-codecs-with-runtime-semantics.md)
  records the specialization decision. Maintained benchmarks compare current
  implementations with vanilla native paths.

Publication requires CI on the selected Blueprint commit and a passing llm_wire
full gate against that same dependency commit. Reconcile its root and nested
manifests through Gleam whenever the pin changes. The consumer's committed
dependency declarations and manifests identify the tested revision; historical
downstream gates do not certify a newer candidate.

Further parser rewrites, removal of the frozen legacy API, and removal of
explicit Value/standard-native generated APIs are not release prerequisites.
Engine experiment records are retained only as ADR conclusions in the checkout.
Installation text should switch from prerelease Git
instructions to Hex only after publication succeeds.
