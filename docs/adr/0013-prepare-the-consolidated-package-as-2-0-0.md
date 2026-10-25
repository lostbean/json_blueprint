# Prepare the consolidated package as 2.0.0

<a id="adr-0013"></a>

- **Decision, 2026-10-25.** Prepare `json_blueprint` version 2.0.0 with its legacy
  modules, codecs, exact values, runtime contracts, and source generators in one
  package. The owner selected this version and requested migration instructions.
  This supersedes the version hold in [ADR 0011](0011-hold-manifest-version-pending-release-decision.md#adr-0011).
- **Rationale.** Published 1.7.1 callers can encounter opaque decoder records,
  a removed dynamic module path, standard-library dynamic decode errors, and a
  new byte bound on legacy text decoding. A major version makes those changes
  explicit while retaining the legacy combinators and wire forms described in
  [ADR 0007](0007-freeze-legacy-source-and-wire-contracts.md#adr-0007).
- **Alternatives.** A 1.x minor release would hide breaking source and admission
  changes. Continuing the version hold would leave the accepted release decision
  unrecorded. A separate generator release would restore the package boundary
  superseded by [ADR 0008](0008-development-time-source-generation.md#adr-0008).
- **Consequences.** Generator and runtime APIs share the 2.x compatibility
  boundary. Applications can retain legacy wire formats while separately
  adopting codecs. The version decision does not claim complete legacy
  equivalence or expand the finite schema profile; existing verification and
  unsupported-feature entries remain open. Preparing this commit does not publish
  a Hex release or create a release tag.
- **Evidence.** The [migration guide](../MIGRATION.md),
  [compiled migration example](../../examples/test/migration_test.gleam), and
  [legacy examples](../../examples/test/legacy/) state and exercise the migration
  boundary. The [package gate](../../scripts/gate.sh) validates both targets,
  generated consumers, and the finite independent oracles.
