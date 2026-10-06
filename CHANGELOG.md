# Changelog

## Unreleased — intended 2.0

- Schema-aware `Codec(a)` combines typed conversion with schema publication, including records, unions, refinements and explicit custom mappings.
- Strict JSON values retain exact numbers, duplicate-key evidence and independently configurable admission limits.
- Finite runtime contracts provide validation and retained witnesses independently of application-native types. The development-only generator remains a separate capability with explicit scope limits.
- The published 1.x root API remains frozen. The [1.x to 2.0 guide](docs/migration-2.0.md) records the supported migration; the manifest stays at 1.7.1 pending a release decision.

The [design layer](docs/design/design.typ) records current contracts and retained intended scope. [ADRs](docs/adr/0001-schema-aware-ownership-and-finite-support.md) record the pre-release decisions, including acceptance corrections and compatibility limits. Superseded intermediate facades are not a published migration contract.
