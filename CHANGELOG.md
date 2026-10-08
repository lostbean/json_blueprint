# Changelog

## Unreleased — intended 2.0

- The development-only schema generator lowers admitted closed-object schemas to public native records and a root typed codec. Supported child forms preserve constraints, descriptions, exact numbers, and wire names; unsupported shapes and naming conflicts return located failures. A separate order consumer compiles and checks deterministic generated output on Erlang and JavaScript without a production generator dependency.

- Runtime contract validation uses string-specific searches for small objects and a temporary index above 40 input members. Accepted values, member order, and first-error paths remain unchanged. The index trades temporary allocation for faster wide-object validation; it adds no cache or public configuration.
- `contract.value_codec` now validates encoding as well as decoding. Invalid dynamic values return `EncodeError` with the first validation path and reason; valid values retain member order and exact numbers. This corrects the former encoding passthrough without changing signatures or adding validation passes to typed or generated codecs.
- Runtime-schema refusals distinguish finite-profile restrictions from malformed keyword values. Valid omitted/default-open object members, one-sided bounds and other unsupported forms remain refused with `UnsupportedDocument`; the accepted profile is unchanged.
- Schema-aware `Codec(a)` combines typed conversion with schema publication, including records, unions, refinements and explicit custom mappings.
- Strict JSON values retain exact numbers, duplicate-key evidence and independently configurable admission limits.
- Finite runtime contracts provide validation and retained witnesses independently of application-native types. The development-only generator remains a separate capability with explicit scope limits.
- The published 1.x root API remains frozen. The [1.x to 2.0 guide](docs/migration-2.0.md) records the supported migration; the manifest stays at 1.7.1 pending a release decision.

The [design layer](docs/design/design.typ) records current contracts and retained intended scope. [ADRs](docs/adr/0001-schema-aware-ownership-and-finite-support.md) record the pre-release decisions, including acceptance corrections and compatibility limits. Superseded intermediate facades are not a published migration contract.
