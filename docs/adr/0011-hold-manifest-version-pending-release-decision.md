# Hold the manifest version at 1.7.1 until the owner decides a release

<a id="adr-0011"></a>

- **Decision.** The package manifest stays at 1.7.1 while the codec API, runtime contracts and development generator are unreleased. The 1.x root and schema modules stay frozen. A version change requires an explicit release decision by the owner.
- **Rationale.** The published 1.7.1 surface is the only compatibility promise outside this repository. Raising the manifest would claim a migration contract whose compatibility evidence is partial ([ADR-0007](0007-freeze-legacy-source-and-wire-contracts.md#adr-0007)). Intermediate facades are not published and carry no migration obligation.
- **Alternatives.** Declaring 2.0 now would promise a stable codec surface before the owner accepts it. Bumping a minor version would mix additive and breaking changes under one number.
- **Consequences.** Applications depend on the codec API by path until a release is decided. The README states the installed 1.7.1 surface separately from the checkout surface. Source and wire consequences for 1.x callers are recorded in ADR-0007 and the legacy section of the design.
- **Evidence.** The manifest declares 1.7.1 and the latest release tag is `v1.7.1`; no tag exists for the codec API. The development generator package declares 0.1.0 and is not published.
