# Changelog

## Unreleased — intended 2.0

- Lower the strict parser's default limits from 10 MiB and depth 128 to 1 MiB and depth 64. 10 MiB of `[1,1,...]` had produced a 503 MB value and over 900 MB of process heap on OTP 28. Raise the limits with `parser_limits.with_max_bytes` and `with_max_depth`.
- Reject text above 1 MiB in the 1.x `blueprint.decode`, in `codec.decode_json_native` and in generated `decode_<name>_json_native` functions before `gleam/json` parses it. `blueprint.decode` returns `json.UnableToDecode` with one error that names the limit; the codec paths return `BlueprintByteLimitExceeded`. Add `blueprint.decode_with_max_bytes` and `codec.decode_json_native_with_max_bytes` to accept larger text. Regenerate checked-in generated modules: their native decoders now go through the codec's check.
- Parse JSON text from its UTF-8 bytes instead of a list of graphemes, and store integers of up to 15 digits as native integers and other numbers' digits as a string. For 1 MiB of `[1,1,...]` on OTP 28 the heap peak falls from 106 MB to 69 MB and the value from 50 MB to 34 MB; for 1 MiB of 15-digit decimals the peak falls from 106 MB to 16 MB. Error locations are unchanged: columns still count graphemes. A string whose first character is a combining mark (the raw character, not a `\u` escape) is now accepted; the grapheme-based parser rejected it because the mark joined the opening quote.
- Document the 24-digit limit of `codec.int()` decoding and add a defaults table to the README.
- Add a module doc to each of the 12 public modules, with an example for `json/blueprint`, `codec`, `codegen`, `parser` and `runtime` that a test compiles and runs. Remove the README's reference to a `PUBLIC-API.md` that does not exist.
- Add `codec.describe` and `codegen.describe` for Draft 2020-12 descriptions at any codec schema node. Descriptions survive document loading and runtime contracts but do not affect validation or schema matching. The new public `DescribedSchema` variant requires exhaustive `Schema` matches to be updated.
- Add `codec.render_json_decode_error` for readable, located JSON decode feedback. It omits input values and application-supplied custom reason text; callers still decide whether to expose a diagnostic.
- Add an exact JSON value and decimal number model, bounded strict JSON parser, bidirectional `Codec(a)` definitions, finite Draft 2020-12 schema documents, and runtime contract validation.
- Add typed `codegen.Definition(a)` for runtime and generated codecs. Ordinary generated JSON decoding uses the strict parser; native `gleam/json` admission remains an explicit option.
- Retain the published `json/blueprint.Decoder(a)` and legacy schema module for recursive decoding and existing `$ref`/`$defs` output. The legacy renderer labels output Draft-07; strict dialect interoperability is not promised.
- When moving a 1.x decoder to `Codec`, review extra object fields, absent versus `null` values, union envelopes, duplicate keys, and exact number handling. See the [migration guide](docs/migration-2.0.md).
- Remove the implementation-branch-only `json/blueprint/migration` adapter before release; it was never part of published 1.7.1.

The finite codec schema does not cover recursive references, arbitrary untagged unions, or pattern/regex validation. Erlang/OTP 28 and JavaScript on Node.js 24 are exercised in CI; browser JavaScript is unverified. Native integers on JavaScript are limited to the safe integer range. The manifest version remains 1.7.1 until a release decision.
