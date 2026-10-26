# THROWAWAY: JavaScript hybrid correctness review

Question: can native JavaScript parsing and direct typed decoding preserve the strict admission guarantees already adopted for Erlang?

Reviewed prototype based on `2c6df6148c9357b03041be2c95a3a46a6694120d`, on Node 24.21.0. This is finite experimental evidence, not a production approval or proof of parser correctness. No source tests were weakened; diagnostic differences were classified in a disposable harness. Production source changes belong to the implementation agent.

## Outcome and design adherence

No unresolved correctness blocker was found after three prototype defects were corrected. The checked byte bound, decoded-name duplicate rejection, strict Unicode, exact numeric tokens before typed projection, closed records, optional-field semantics, and syntax validation before user callbacks remain intact. Valid input beyond runtime capacity returns a capacity refusal; user callback exceptions remain visible. Native parsing builds a full host tree, so this is direct typed projection, not streaming typed parsing.

JavaScript still has explicit safe-integer and exact-number exponent/magnitude representation restrictions. It does not gain Erlang's arbitrary integer domain. The numeric admission guard matches the existing JavaScript Number kernel in the generated boundary cases, including zero with enormous written exponents.

## Evidence

| Check | Result |
| --- | --- |
| Public adversarial assertions | 8,327 passed |
| Independent BigInt numeric boundary cases | 5,904; 4,344 accepted, 1,560 refused; no value failures or kernel disagreements |
| JSONTestSuite plus generated corpus | 318 + 1,179 = 1,497; no acceptance or value failures |
| Corpus rejection diagnostics | 26 deliberate unicode-escape to native-syntax classifications |
| Unchanged root suite with native support | 313 passed, 11 classified failures |
| Unchanged root suite with context.source removed | 324 passed, no failures |

Public probes include every raw UTF-16 surrogate code unit in keys and values; escaped pairs and isolated surrogates; malformed text in unknown fields; escaped equivalent duplicate names; sibling object scopes; `__proto__` and `constructor`; numeric values close to one and JavaScript integer boundaries; overflow, underflow and zero; byte-limit precedence; closed records; deep valid and malformed inputs; callback ordering, exact custom fallback values, and propagated callback RangeError. A padded 10,000-digit written exponent checks that projection exhaustion is never mislabeled invalid numeric syntax.

The independent decimal oracle canonicalizes coefficient and exponent with BigInt. It varies signs, leading and trailing zeros, written and normalized exponents, and comparison magnitude around MAX_SAFE_INTEGER. The existing kernel is a second comparison, not the independent oracle.

## Defects found and corrected during review

1. On runtimes without reviver context.source, direct internal native.parse attempted token access and threw TypeError. An early UnsupportedRuntime return now protects the entry point; the public portable fallback passes all 324 original tests.
2. TextDecoder removed a leading UTF-8 BOM on parse_bits, causing strict admission to accept a corpus input that Erlang rejects. Native byte parsing now rejects that prefix after byte-limit and UTF-8 validation.
3. Exact projection stack exhaustion was converted to Unrepresentable and then InvalidNumber(InvalidSyntax). A distinct ProjectionCapacity now propagates RuntimeCapacityExceeded through Value and built-in codec paths. Pure conversion guards exclude user callbacks.

## Exact unchanged-suite differences

Nine failures concern native diagnostic categories or unavailable byte/line/column locations:

- bounded_parsing_test.error_columns_count_graphemes_test
- host_string_test.raw_surrogate_locations_count_utf8_bytes_and_graphemes_test
- host_string_test.raw_surrogates_reject_before_utf8_conversion_test
- public_codec_convenience_test.public_decode_error_renderer_handles_paths_and_private_values_test
- value_parse_test.duplicate_object_key_rejected_test
- value_parse_test.hostile_syntax_errors_test
- value_parse_test.standalone_cr_whitespace_and_error_location_test
- value_parse_test.string_runs_preserve_values_and_failure_locations_test
- value_parse_test.wide_object_resource_and_duplicate_boundary_test

One test assumes JavaScript has no native implementation: native_number_test.unsafe_exponent_remains_a_javascript_representation_failure_test. Its failing assertion is native.supported() == False, not an admitted unsafe number.

One concerns malformed deep-input precedence: value_parse_test.portable_parser_reports_host_stack_capacity_test. Native JSON.parse rejects 20,000 unclosed array delimiters as syntax before the portable parser would exhaust its stack. Valid deep input still returns a value or a capacity refusal without an uncaught parser exception in the probes.

These are real observable migrations, not evidence of an all-green unchanged gate. Adoption must update the documented contract and corresponding expectations deliberately. The corpus adapter only separates the known rejection reason differences; it continues to reject acceptance or numeric-value mismatches.

## Standards, compatibility, and complexity caveats

JSONTestSuite contains implementation-defined inputs; this run applies the repository's existing strict classifications. It does not claim acceptance of every string that plain JSON.parse accepts. Escaped isolated surrogates and duplicate names intentionally reject. Byte input remains strict UTF-8.

Native Object.keys puts integer-like keys before other keys. Public Value serialization can therefore reorder source keys; error traversal may likewise differ. Object ordering was observed as {"1":1,"2":2,"x":3} for a differently ordered source. Native syntax validation also precedes the duplicate scanner, so multiply-invalid input may choose another error. Exact locations are unavailable on the native path. These changes resemble Erlang's native boundary but do not promise identical object ordering across backends.

The scanner preserves evidence JSON.parse would erase and validates escaped Unicode in every value, including fields the codec never requests. It runs after native parsing, and uses a Set for each currently open object. Native number source support is detected once; unsupported runtimes keep the portable parser. That preserves compatibility but retains both implementations and their test burden. Fallback was simulated on Node, not certified across browser engines.

The review did not find a reason to broaden exception handling around callbacks. Keep pure materialization and exact-number guards separate from user code. Performance and memory decisions belong to the accompanying controlled benchmark; no timing was used as a correctness gate.

## Reproduction and artifacts

From the prototype root, after compiling JavaScript with the repository toolchain:

```sh
node experiment/js-hybrid-review.mjs .
node experiment/js-hybrid-review-numbers.mjs .
python3 experiment/js-hybrid-review-corpus.py
node experiment/js-hybrid-review-fallback.mjs .
node --input-type=module -e 'import {main} from "./build/dev/javascript/json_blueprint/json_blueprint_test.mjs"; main();'
```

Use the Nix shell to reproduce Node 24.21.0. The native root command deliberately exits unsuccessfully for the 11 classified differences above. The corpus script reuses the repository corpus and expected classifications. Final JSON evidence and both root-suite logs are adjacent under `js-hybrid-review-*-final.*`; probe results include production module hashes. No release, integration, or commit was performed by this review.
