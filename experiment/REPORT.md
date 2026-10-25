# Native parsing with direct typed decoding

THROWAWAY experiment — 2026-10-25. Question: does native parsing plus direct typed decoding improve ordinary workloads and memory enough to justify explicitly different parser guarantees?

**Answer: the performance opportunity is real, including ordinary records.** Native decoding is roughly 2× faster for the Erlang record fixtures and 3–4.6× faster for JavaScript records. Memory savings for small inputs are modest or negligible; large arrays show substantial peak-RSS reduction. This is evidence for an explicitly separate native entry point, not for silently replacing strict parsing.

The requested separate worktree is `native-direct-decoding`. Production source hashes match the optimized strict baseline pinned in `baseline.json`. No release/API/design change was made. Dirty production files inherited from earlier work are not changes from this experiment.

## Implemented scope and comparison

The candidate uses the resolved `gleam/json` dependency: `json:decode/1` from Erlang/OTP and JavaScript `JSON.parse`, then decodes the resulting native tree directly. It does not construct the strict Value/exact-Number tree. This is **native tree → typed result**, not streaming JSON text into types. JavaScript array decoding holds the native array, a temporary output array and the final Gleam list during conversion.

Implemented decoders: Int, Float, String, Bool, lists/nested lists, closed three-field record `(id,name,active)`, a response object wrapping records, and an optional nullable `note` field. The prototype includes narrow FFI for object access, numeric conversion and array traversal. It preserves a 1MiB pre-parse byte bound and rejects raw JavaScript lone-surrogate host strings before parsing.

The candidate does not integrate with the opaque Codec API, encoding/schema generation, arbitrary dependent records, enums, unions, exact `number()` or custom Value callbacks. Supported fixture decoders are hand-written. The measurements combine a parser change with a direct decoding implementation; they do not isolate parser speed alone and do not establish that every existing codec gets the same gains. A production implementation would need internal native decode support throughout combinators and a conversion fallback for custom Value codecs, without requiring consumers to define the same contract twice.

All timed fixtures first verify exact equality of the resulting typed values outside the timing/memory processes. Decimal fixtures decode to Float on **both** paths; they do not compare an exact Number result against a rounded native float. Existing strict float decoding deliberately rounds, but exact parsing and conversion cost still occurs first.

## Normal workloads and memory

| Backend | Fixture | Strict µs | Native µs | Speedup | Strict peak MiB | Native peak MiB |
|---|---|---:|---:|---:|---:|---:|
| erlang | small_record | 2.03 | 1.00 | 2.02× | 67.84 | 67.80 |
| erlang | records_50 | 95.76 | 44.79 | 2.14× | 67.91 | 68.03 |
| erlang | response_50 | 97.22 | 43.45 | 2.24× | 67.67 | 67.48 |
| erlang | ints_10000 | 2200.22 | 853.65 | 2.58× | 70.36 | 68.41 |
| erlang | ints_limit | 211394.17 | 24835.50 | 8.51× | 167.16 | 101.69 |
| erlang | nested_100x100 | 2159.83 | 836.79 | 2.58× | 69.83 | 67.95 |
| erlang | decimals_1000 | 3396.92 | 215.56 | 15.76× | 68.03 | 67.70 |
| erlang | text_records_50 | 1381.00 | 917.00 | 1.51× | 67.94 | 67.89 |
| erlang | optional_51 | 27.82 | 15.08 | 1.85× | 67.84 | 67.81 |
| erlang | unicode_strings | 241.59 | 276.66 | 0.87× | 67.80 | 67.53 |
| erlang | escaped_strings | 409.95 | 272.84 | 1.50× | 67.80 | 67.95 |
| javascript | small_record | 10.69 | 3.53 | 3.03× | 52.80 | 52.61 |
| javascript | records_50 | 379.36 | 86.01 | 4.41× | 53.59 | 52.89 |
| javascript | response_50 | 380.36 | 83.38 | 4.56× | 53.86 | 53.11 |
| javascript | ints_10000 | 10229.80 | 1034.92 | 9.88× | 63.33 | 55.28 |
| javascript | ints_limit | 320813.58 | 36634.67 | 8.76× | 263.12 | 83.89 |
| javascript | nested_100x100 | 9373.53 | 1207.71 | 7.76× | 62.64 | 55.34 |
| javascript | decimals_1000 | 5321.17 | 176.39 | 30.17× | 62.47 | 53.59 |
| javascript | text_records_50 | 6418.17 | 684.62 | 9.37× | 56.30 | 53.48 |
| javascript | optional_51 | 106.68 | 50.97 | 2.09× | 53.08 | 52.66 |
| javascript | unicode_strings | 1006.36 | 80.79 | 12.46× | 55.92 | 52.83 |
| javascript | escaped_strings | 2260.99 | 116.81 | 19.36× | 56.52 | 52.73 |

The small record has three fields. The response wraps 50 such records. Text-heavy records carry long ordinary strings; separate fixtures exercise escaped and Unicode strings. Optional fixtures include absence, explicit null and strings. These are representative shapes, not a sampled production distribution or an exhaustive workload mix. The Erlang Unicode-string fixture is about 15% slower natively, so native is not universally faster.

The largest array has 262,143 integers in 524,287 bytes. It is an edge workload, not the basis for the normal-workload recommendation. Its time falls from211ms to25ms on Erlang and321ms to37ms on JavaScript. Whole-process peak RSS falls167→102MiB and263→84MiB respectively. Final typed outputs remain the same; this mainly reduces transient tree and numeric representation work. For small records, the VM/runtime footprint dominates and sub-MiB changes are not meaningful memory wins.

Method: three fresh timing VMs for each target/fixture/path, one warmup batch and five timed batches per VM, median of15 samples. Iterations are size-adjusted. Three independent fresh processes decode once, retain the output, explicitly GC and report runtime memory; OS wait4 supplies whole-process peak RSS. That high-water mark includes VM, modules, input, transient allocations and post-decode measurement overhead. It is not the size of the result. Both paths load the same harness/modules. Full raw samples and post-GC fields are in `results.json`. Compiler Gleam1.19.2; OTP29/ERTS17.1.1 JIT with one scheduler; Node24.21.0 with exposed GC. The optimized baseline is rerun here; older experiments are not paired measurements.

## Guarantee changes

| Guarantee | Optimized strict path | This native prototype |
|---|---|---|
| Input byte admission | Configurable, default1MiB | Same default bound checked before parsing; prototype does not expose configurable limits |
| Syntax validation before typed callbacks | Yes | Yes; complete native parse precedes decoder invocation |
| Depth/value allocation bounds | Depth64 and262,144 values by default, checked during parse | Absent; depth65 and262,145-value examples accepted. Byte limit remains but is not equivalent |
| Numeric token/significand/exponent limits |1024 bytes,800 digits, exponent magnitude1200 | Absent;1026-byte fractional-zero token and1e-1201 accepted |
| Exact numbers | Exact decimal Number retained before projection | No exact-number decoder; decimals become binary64 before typing |
| Mathematical integer acceptance | Checks original exact value | Checks native value;1.00000000000000001 rounds to1 and is accepted as Int on both targets |
| Native integer range |24-digit cap; JavaScript safe-integer restriction | Explicitly retained;1.0/1e0 accepted as integral values, unsafe JS integers refused |
| Duplicate names | Rejected, including equivalent escaped names | Collapsed: pinned Erlang parser FIRST occurrence wins, JavaScript LAST wins; decoder cannot recover evidence |
| Raw host-string scalar validation | Rejects invalid scalars | Explicit precheck retained, byte-limit precedence retained |
| Escaped lone surrogates | Rejected | Erlang rejects; JavaScript accepts `"\ud800"` as a string containing a lone surrogate |
| Unknown fields | Rejected after known fields decode | Rejected for supported records, but first reported unknown can change with native key enumeration |
| Missing versus null | Distinguished | Preserved by presence lookup and nullable decoding |
| Known-field error order and paths | Codec definition order | Preserved in tested concrete records/lists |
| Syntax/number error vocabulary and locations | Structured strict ParseError and Location | NativeSyntax or Typed errors; same location/reason contract is not retained |
| Enum/union wire contracts, custom codecs, schema behavior | Existing codec implementation | Not implemented in this candidate; do not infer full compatibility from record tests |

Concrete observed differences:

- Duplicate `{"note":1,"note":2}` produces1 on Erlang and2 on JavaScript; strict rejects it.
- `1.00000000000000001` decodes to Int1 natively; the strict Int codec rejects the exact fractional value. Safe-integer checks cannot fix information already rounded away.
- `9007199254740993` is accepted as an Int on Erlang and refused by the explicit JS safe-integer guard. That restriction itself matches the intended native Int range; it does not restore exact decimals.
- `1e400` is native syntax rejection on Erlang and typed FloatOutOfRange on JavaScript. Strict can parse the exact number within its exponent bound before rejecting Float projection.
- For valid known record fields followed by unknown `z` then `a`, strict reports `z`; native Erlang reports `a`, JavaScript reports `z` in this case. JavaScript integer-like keys can also reorder source keys.
- Depth65 and the value-limit-plus-one examples are admitted natively. These tests deliberately use a trivial decoder after parsing to isolate admission from requested typed shape.

## What can be mitigated simply

Keep byte admission, field-presence handling, closed records, native range checks and decoding after successful parse. Validate decoded strings/keys if scalar-only output is required, though that adds work and still occurs after allocation. Post-parse depth/value checks can reject oversized structures but cannot restore pre-allocation protection.

Lossless numbers and duplicate rejection are not solved by this prototype. OTP's lower-level `json:decode/3` hooks offer more control; ordinary gleam/json uses decode/1. Modern JavaScript source-aware revivers can recover numeric text, but duplicate evidence is already lost and full native allocation already happened. A pre-scan can recover more guarantees at the cost of another syntax-aware pass. None of those variations is included in these performance numbers.

## Verification and recommendation

An implementation subagent built the adapter and behavioral probes. A separate review subagent inspected actual resolved parser sources and identified duplicate winner, Unicode, unknown-order and callback-integration limitations. Targeted assertions pin the intentionally different behaviors. Supported typed-error cases compare full Results against the original codec, and every timed fixture compares exact typed output equality. Native behavior is **not** asserted equivalent across the1,219 strict corpus cases: the strict parser's existing corpus/oracles are exercised by the repository gate separately.

The full repository gate and final native behavior/typed-error checks passed on both backends. Production hashes still match the optimized baseline; see `validation.log`.

The data supports pursuing an **explicit native decoding option** for consumers who accept native number semantics and byte-only parse admission. Keep strict decoding for exact values, duplicate rejection, bounded parsing and its diagnostic contract. Do not auto-switch based on input shape/size or silently change the existing strict entry point. The unresolved work is integration simplicity and complete codec coverage, not whether a native fast path can help ordinary records. No production implementation or release cut is proposed by this throwaway prototype.

## Reproduce

From this worktree:

```sh
XDG_CACHE_HOME=/tmp/json-blueprint-review-nix-cache nix develop --command sh -c 'gleam build --target erlang --warnings-as-errors && gleam build --target javascript --warnings-as-errors && python3 experiment/run.py'
```

`python3 experiment/run.py --check-only` runs native behavior and typed-error checks. Full repository gate: `nix develop --command sh scripts/gate.sh`. Baseline source hashes are in `baseline.json`.
