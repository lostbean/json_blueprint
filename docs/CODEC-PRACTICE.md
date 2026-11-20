# Codec practice

This guide says when to generate a codec, when to write one with combinators,
and how to write combinator codecs that stay cheap to send between BEAM
processes. It is for application authors and for agents that write codecs.

The copy rules depend on the lowest json_blueprint version your package
declares, because that is the oldest version a build may resolve:

| Declared minimum | Copy rules |
| --- | --- |
| 2.2.0 or later | Each combinator holds its inputs once. [Rules 1–3](#write-combinator-codecs-that-copy-cheaply) are no longer needed and code that follows them needs no change. Keep [rule 4](#4-test-the-copy-size). |
| 2.1.1 to 2.1.x | Follow rules 1–4. |
| 2.1.0 or earlier | Raise the minimum: copies multiply per nesting layer. |

An application decides by its lock file as well: with a minimum of 2.2.0 in
`gleam.toml`, a build cannot resolve an older version.
Every Gleam, Erlang and JavaScript block below is synchronised from a compiled
example that the repository's gate runs on Erlang and JavaScript.

The [JSON contracts design](design/contracts/design.typ#typed-codecs) owns the
copy-cost behaviour of combinators, and the
[source generation design](design/generation/design.typ#typed-definition-generator)
owns that of generated codecs.

## Require 2.1.1 or later

Depend on `json_blueprint >= 2.1.1`:

```toml
json_blueprint = ">= 2.1.1 and < 3.0.0"
```

A BEAM process copy (a message, a spawn argument, a supervisor child
specification) does not preserve sharing. A term costs its flat size to send:
every part reachable from it, counted once per path that reaches it.

Up to 2.1.0, each callback that a combinator built retained the whole child
codec. Every nesting layer therefore multiplied the copy size. A record layer
multiplied it by 20 to 26. An agent input codec (a record of a list of records
of a twelve-field record) took 14.0 MB to copy while it occupied about 2 kB in
the heap that built it. In 2.1.1 the same codec copies in 5.9 kB, and each
layer adds about a fixed number of bytes. The
[benchmark record](BENCHMARKS.md#codec-copy-cost-2026-11-19) holds the before
and after measurements and the one exception: a record whose first field is a
required record adds 36 words (288 bytes) more per enclosing record. An
application that sends codecs, or values that hold codecs, to other processes
can run out of memory on 2.1.0 or earlier.

From 2.2.0 each combinator holds each of its inputs once
([ADR 0018](adr/0018-hold-each-codec-input-once.md)), so a codec copies at
about its in-heap size: the agent input codec above copies in 688 B, a
consumer's model-answer codec in 1.0 kB instead of 88.6 kB, and a run-time enum
label costs its own data once instead of about 1 kB. Prefer
`json_blueprint >= 2.2.0` for new code. Two union cases changed in 2.2.0: a
value tagged by another union's tagging function panics when encoded, and a
union payload is encoded after `match` returns; the documentation of
`codec.union` describes both.

## Choose generated codecs or combinators

Copy cost depends on what crosses a process boundary. Sending decoded data,
such as a job payload, costs the same whichever codec decoded it. The choice
matters when the codec itself, or a value that holds it, is sent to or held by
other processes: an agent or a tool definition that carries its codecs, a
worker's start argument, a supervisor child specification.

| Use | When |
| --- | --- |
| Typed-definition generator ([ADR 0016](adr/0016-specialize-generated-codecs-with-runtime-semantics.md)) | The JSON shape is fixed at build time, and the codec is hot, long-lived, or sent to or held by other processes, directly or inside another value. Stored payloads, queue payloads and API bodies usually qualify. |
| Combinators (`json/blueprint/codec`) | The shape depends on run-time values, such as enum labels known only for one run; the shape needs tagged unions, shared definitions or recursion; the codec uses `codec.custom`, `codec.value` or an arbitrary `try_map`; or the codec is used once. |

A fixed shape that is neither hot nor sent between processes can use either.
Default to combinators there, and generate the codec when it becomes hot or
starts to travel.

Reasons for generated codecs:

- A generated codec refers to module functions and literals and captures no
  child codec. In this repository's [codegen consumer](../examples/codegen/README.md),
  the export job codec has a flat size of 920 B when generated, against 1.3 kB
  built with combinators from the same definition on 2.2.0 and 19.3 kB on
  2.1.1.
- On Erlang/OTP 29, literals are not copied between processes: a receiver of a
  4,200-byte literal grew by 0 B.
- Generated codecs convert faster. This repository retains a 50-record decode
  at 238 → 176 µs on Erlang and 801 → 396 µs on JavaScript
  ([ADR 0016](adr/0016-specialize-generated-codecs-with-runtime-semantics.md)).
  In a [consumer application](BENCHMARKS.md#generated-and-combinator-codecs-in-a-consumer-2026-11-19),
  comparable shapes encoded 3.7 to 5 times and decoded 1.25 to 1.6 times
  faster.

Reasons for combinators:

- The typed-definition generator cannot express run-time values, unions,
  shared definitions or recursion today; see [generator gaps](#generator-gaps).
- A combinator codec costs microseconds per conversion. Next to a model call or
  a database round trip, that cost is negligible.

These timings are dated observations, not guarantees.
[ADR 0010](adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md)
records the measurement policy.

The schema-driven generator (`json/blueprint/codegen/schema`) is a third path:
it turns a closed-object JSON Schema into native records and an ordinary
combinator codec. Its output is combinator code, so the rules below apply to
it on 2.1.x.

## Write combinator codecs that copy cheaply

With a minimum of 2.2.0, skip rules 1–3: a record codec holds its continuation
once, so a value the continuation captures is copied once, whichever field
uses it. Code written to these rules stays correct and small. Do not move a
child codec or a run-time enum out of its field while your package still
allows 2.1.x; move it only in the change that raises the minimum to 2.2.0.

On 2.1.x, `use x <- codec.field(...)` turns the rest of the record definition
into a continuation, a function the record codec calls with the decoded field.
A record codec keeps that continuation in several callbacks (encoding,
decoding, schema discovery). Every value that the continuation refers to from
outside it is captured: inside one process the capture is shared, but a
process copy duplicates it once per callback that holds the continuation.

### 1. Build each child codec where it is used

Build a child codec in the field's codec argument, directly or by calling a
top-level function there. Never bind a child codec with `let` before a
`use … <- codec.field` chain and use it in a later field. The same holds for any
large value, such as a parsed schema or a configuration record.

Wrong: `contact` is captured by every continuation after the first field.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/src/examples/child_codecs.gleam#let-bound -->
```gleam
/// Avoid on 2.1.x: `contact` is bound before the chain and used by later
/// fields, so every continuation after the first field captures it. From
/// 2.2.0 it is copied once.
pub fn captured_answer_codec() -> Codec(Answer) {
  let contact = contact_codec()
  use summary <- codec.field("summary", codec.string(), get: fn(a) { a.summary })
  use primary <- codec.field("primary", contact, get: fn(a) { a.primary })
  use backup <- codec.optional_field("backup", contact, get: fn(a) { a.backup })
  codec.success(Answer(summary:, primary:, backup:))
}

```

<!-- prettier-ignore-end -->

Right: each field calls the function that builds its child codec.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/src/examples/child_codecs.gleam#built-in-fields -->
```gleam
/// Each field builds its child codec by calling `contact_codec`.
pub fn answer_codec() -> Codec(Answer) {
  use summary <- codec.field("summary", codec.string(), get: fn(a) { a.summary })
  use primary <- codec.field("primary", contact_codec(), get: fn(a) {
    a.primary
  })
  use backup <- codec.optional_field("backup", contact_codec(), get: fn(a) {
    a.backup
  })
  codec.success(Answer(summary:, primary:, backup:))
}

```

<!-- prettier-ignore-end -->

A codec passed in as a function parameter and used by a later field is
captured in the same way, because the continuation refers to the parameter.
Use such a codec in the first field when the wire order allows: the first
field keeps only the operations its callbacks call, so no continuation
captures the codec. Reordering
changes the order of the encoded members and of the schema's properties, while
decoding accepts members in any order. When the order is fixed, for instance by
a stored format, the record continuation limit below owns the cost.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/src/examples/child_codecs.gleam#parameter -->
```gleam
/// Avoid on 2.1.x when the codec is sent: the `answer` parameter is used by a
/// later field, so every continuation after the first field captures it, as a
/// `let`-bound child codec would be. From 2.2.0 it is copied once.
pub fn captured_reply_codec(answer: Codec(a)) -> Codec(Reply(a)) {
  use id <- codec.field("id", codec.string(), get: fn(r) { r.id })
  use answer <- codec.field("answer", answer, get: fn(r) { r.answer })
  codec.success(Reply(id:, answer:))
}

/// On 2.1.x the first field keeps only the operations its callbacks call, so
/// no continuation captures the parameter; from 2.2.0 either order copies the
/// parameter once. This changes the order of the encoded members and of the
/// schema's properties; decoding accepts members in any order.
pub fn reply_codec(answer: Codec(a)) -> Codec(Reply(a)) {
  use answer <- codec.field("answer", answer, get: fn(r) { r.answer })
  use id <- codec.field("id", codec.string(), get: fn(r) { r.id })
  codec.success(Reply(id:, answer:))
}

```

<!-- prettier-ignore-end -->

Measured flat sizes on 2.1.1 (on 2.2.0 the answer codec copies in 440 B and
168 B, and the reply codec in 440 B and 392 B):

| Codec | `let`-bound children | Children built in their fields |
| --- | ---: | ---: |
| [`child_codecs`](../examples/src/examples/child_codecs.gleam) answer codec | 19.7 kB | 1.6 kB |
| Codegen consumer submission envelope (`order_app.submission_codec`) | 1.26 MB | 1.7 kB |
| [`child_codecs`](../examples/src/examples/child_codecs.gleam) reply codec, contact codec as a parameter | 19.7 kB (later field) | 3.0 kB (first field) |
| A consumer's model-answer codec ([observation](BENCHMARKS.md#generated-and-combinator-codecs-in-a-consumer-2026-11-19)) | 88.6 kB | 1.9 kB |

Both forms convert the same JSON and describe the same schema. A child built
in a later field is constructed when the continuation runs, which costs
microseconds per conversion.

### 2. Build run-time enums inside the field

When enum labels are known only at run time, capture the small data (the label
pairs, converted once) and call `codec.string_enum` inside the field that uses
it. Check the codec once where the labels arrive, because labels from data can
repeat: `codec.check` returns the problem instead of a later panic.

Wrong: the prebuilt enum codec is captured by every later continuation.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/test/copy_cost_test.gleam#prebuilt-enum -->
```gleam
/// The enum codec built once before the chain: from 2.2.0 it is copied once
/// and not rebuilt per conversion. On 2.1.x every later continuation
/// captured the whole codec, so avoid this form there.
fn prebuilt_citation_codec(offered: List(String)) -> Codec(Citation) {
  let sources = codec.string_enum(list.map(offered, fn(id) { #(id, id) }))
  use claim <- codec.field("claim", codec.string(), get: fn(c: Citation) {
    c.claim
  })
  use source_ids <- codec.field("source_ids", codec.list(sources), get: fn(c) {
    c.source_ids
  })
  use note <- codec.optional_field("note", codec.string(), get: fn(c) { c.note })
  codec.success(Citation(claim:, source_ids:, note:))
}
```

<!-- prettier-ignore-end -->

Right: the continuation captures only the label pairs.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/src/examples/runtime_enum.gleam#citation-codec -->
```gleam
/// The citation codec for one run, which may cite only `offered` sources.
pub fn citation_codec(offered: List(String)) -> Codec(Citation) {
  // Small data: one label pair per offered id, converted once.
  let labels = list.map(offered, fn(id) { #(id, id) })
  use claim <- codec.field("claim", codec.string(), get: fn(c) { c.claim })
  use source_ids <- codec.field(
    "source_ids",
    // The enum codec is built here, where the field uses it.
    codec.list(codec.string_enum(labels)),
    get: fn(c) { c.source_ids },
  )
  use note <- codec.optional_field("note", codec.string(), get: fn(c) { c.note })
  codec.success(Citation(claim:, source_ids:, note:))
}

```

<!-- prettier-ignore-end -->

With offered ids of the form `doc-N`, on 2.1.1 the right form copies in
7.0 kB for 5 ids and 54.5 kB for 50, against 27.9 kB and 239.6 kB for the
prebuilt form. The captured labels are still copied once per callback, so
capture only the strings the enum needs. On 2.2.0 both forms copy once (616 B
and 4.6 kB for the right form), and the prebuilt form also skips rebuilding and
re-checking the enum on every conversion; switch to it only with a minimum of
2.2.0. In a
[consumer application](BENCHMARKS.md#generated-and-combinator-codecs-in-a-consumer-2026-11-19),
enums prebuilt for 20 ids encoded 15.7 times faster and were 10.9 times bigger
to copy; rebuilding costs microseconds per conversion.

### 3. Send inputs to other processes, not built codecs

On 2.1.x, do not hand a built codec, or a value that holds one (an agent, a
tool definition, a server's state), to another process for each operation. Build
the codec in the process that uses it, from a small builder function, and send
the builder's inputs instead: a list of labels, an identifier, a configuration
record. A generated codec is the exception, because its parts are literals and
function references. On 2.2.0 a codec copies at about its own size, so this
rule matters only when the value holding it is large for other reasons.

### 4. Test the copy size

Guard every term that holds a codec or other closures and crosses a process
boundary with a test that bounds its flat size. `erts_debug:flat_size/1`
returns words; multiply by the word size for bytes. The check runs only on
Erlang, because JavaScript has no process copy.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/test/examples_copy_cost_ffi.erl -->
```erlang
-module(examples_copy_cost_ffi).
-export([flat_size_bytes/1]).

%% Bytes a copy of Term to another process takes: a message, a spawn
%% argument or a child specification copies the term without sharing.
flat_size_bytes(Term) ->
    erts_debug:flat_size(Term) * erlang:system_info(wordsize).

```

<!-- snips: ../examples/test/examples_copy_cost_ffi.mjs -->
```javascript
// JavaScript has no process copy; the copy-cost checks skip there.
export function flat_size_bytes(_term) {
  return -1;
}

```

<!-- snips: ../examples/test/copy_cost_test.gleam#copy-size-test -->
```gleam
@external(erlang, "examples_copy_cost_ffi", "flat_size_bytes")
@external(javascript, "./examples_copy_cost_ffi.mjs", "flat_size_bytes")
fn flat_size_bytes(term: a) -> Int

/// Copy size is a BEAM measure; on JavaScript the check is skipped.
fn copy_size(term: a, check: fn(Int) -> Nil) -> Nil {
  case flat_size_bytes(term) {
    -1 -> Nil
    bytes -> check(bytes)
  }
}

pub fn child_codecs_built_in_their_fields_stay_small_test() {
  use bytes <- copy_size(child_codecs.answer_codec())
  { bytes < 4096 } |> should.be_true
}

```

<!-- prettier-ignore-end -->

Give the FFI module a name that no other package in the build uses: a package
that depends on another by path also builds that package's test modules, and
two Erlang modules with one name shadow each other depending on code-path
order.

Measure the term that is actually sent: the message, the spawn argument or the
child specification, not only the codec inside it. Set the bound from a
measurement of the correct form, with headroom, so that a captured child codec
fails the test. When a package raises its minimum to 2.2.0 and drops a rule 1–3
form, give the affected value a bound that 2.1.x fails, so that resolving an
older version fails the test rather than a production copy. A relation holds
across releases better than a byte count: the flat size at most a small
multiple of `erts_debug:size/1`, or a fixed step per nesting layer or label.
The [examples copy-cost test](../examples/test/copy_cost_test.gleam)
applies this check to the examples above.

## Generator gaps

The typed-definition generator (`json/blueprint/codegen`) compiles strings,
native integers and integer ranges, booleans, pairs, lists, nullable values,
string enums, closed objects, `imap` with a `named_mapping`, and descriptions. It does not yet cover the following. Use
combinators for these shapes, following the rules above.

- `Float` fields: there is no generated `float`.
- Exact `Number` fields: a `number` definition works through `runtime`, but
  `compile` returns `NativeNumberUnsupported`, and there is no generated
  `number_between`.
- Run-time enums: each `enum_variant` names a constructor at build time.
- Tagged unions, shared definitions, recursive definitions and type aliases.
- `codec.custom`, `codec.value` and arbitrary `try_map`: `imap` accepts only a
  pure `named_mapping`.
- String-valued enums: `enum_variant` needs a constructor reference, so a
  `String` field with a closed set of labels needs a custom type and `imap`.
- Record extension: a generated object codec can be a field or a collection
  element, but cannot finish a `codec.field` or `codec.optional_field`
  continuation.

Generated modules have these costs:

- They are large: the export job module, for a five-field record, is about 930
  lines.
- They import `gleam/json` and `gleam/dynamic`, so the consuming package must
  depend on `gleam_json` directly. Without that dependency the build emits a
  transitive-dependency warning.
- Up to 2.1.1, an enum definition that names every constructor of its type
  produces `Unreachable pattern` warnings in the generated encoders, which
  fails a build with `--warnings-as-errors`. The generator on `main` compares
  enum values by equality and emits no warning; regenerate the module once a
  release includes that change. Until then, build the package that holds the
  generated module without `--warnings-as-errors`, or accept the two warnings
  per enum.

The schema-driven generator binds each child codec with `let` before its field
chain, the form that rule 1 forbids on 2.1.x. There its order codec copies in
105 kB; on 2.2.0 the same generated source copies in 1.7 kB. The tracker issue
[`issues/codec-copy-cost/issues/01-schema-generator-captures-child-codecs.md`](../issues/codec-copy-cost/issues/01-schema-generator-captures-child-codecs.md)
records it.

On 2.1.x, even when every rule is followed, a record codec holds each
continuation in about twelve callbacks, so a copied record codec costs several
times its in-heap size. 2.2.0 holds each continuation once; the tracker issue
[`issues/record-copy-cost/issues/01-hold-a-record-continuation-once.md`](../issues/record-copy-cost/issues/01-hold-a-record-continuation-once.md)
records the change.

## Examples

- [`examples/src/examples/child_codecs.gleam`](../examples/src/examples/child_codecs.gleam):
  rule 1, both forms, with their equal conversions.
- [`examples/src/examples/runtime_enum.gleam`](../examples/src/examples/runtime_enum.gleam):
  rule 2, with `codec.check` for labels from data.
- [`examples/test/copy_cost_test.gleam`](../examples/test/copy_cost_test.gleam):
  rule 4, the copy-size bounds of those examples on Erlang, and the prebuilt
  enum form that rule 2 forbids.
- [`examples/codegen`](../examples/codegen/README.md): a fixed job payload
  generated from a typed definition, its regeneration check, and its copy size
  next to the combinator codec of the same definition.
