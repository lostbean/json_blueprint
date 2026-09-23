# Changelog

## Unreleased — intended 2.0

- Add an exact JSON value and decimal number model, bounded strict JSON parser, bidirectional `Codec(a)` definitions, finite Draft 2020-12 schema documents, and runtime contract validation.
- Add typed `codegen.Definition(a)` for runtime and generated codecs. Ordinary generated JSON decoding uses the strict parser; native `gleam/json` admission remains an explicit option.
- Retain the published `json/blueprint.Decoder(a)` and legacy schema module for recursive decoding and existing `$ref`/`$defs` output. The legacy renderer labels output Draft-07; strict dialect interoperability is not promised.
- When moving a 1.x decoder to `Codec`, review extra object fields, absent versus `null` values, union envelopes, duplicate keys, and exact number handling. See the [migration guide](docs/migration-2.0.md).
- Remove the implementation-branch-only `json/blueprint/migration` adapter before release; it was never part of published 1.7.1.

The finite codec schema does not cover recursive references, arbitrary untagged unions, or pattern/regex validation. Erlang/OTP 28 and JavaScript on Node.js 24 are exercised in CI; browser JavaScript is unverified. Native integers on JavaScript are limited to the safe integer range. The manifest version remains 1.7.1 until a release decision.
