# Codec practice

This guide says when to generate a codec, when to write one with combinators,
and how to write combinator codecs that stay cheap to send between BEAM
processes. It is for application authors and for agents that write codecs.
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
  the export job codec has a flat size of 952 B when generated and 19.3 kB when
  built with combinators from the same definition.
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
it.

## Write combinator codecs that copy cheaply

`use x <- codec.field(...)` turns the rest of the record definition into a
continuation, a function the record codec calls with the decoded field. A
record codec keeps that continuation in several callbacks (encoding, decoding,
schema discovery). Every value that the continuation refers to from outside it
is captured: inside one process the capture is shared, but a process copy
duplicates it once per callback that holds the continuation.

### 1. Build each child codec where it is used

Build a child codec in the field's codec argument, directly or by calling a
top-level function there. Never bind a child codec with `let` before a
`use … <- codec.field` chain and use it in a later field. The same holds for any
large value, such as a parsed schema or a configuration record.

Wrong: `contact` is captured by every continuation after the first field.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/src/examples/child_codecs.gleam#let-bound -->
```gleam
/// Avoid: `contact` is bound before the chain and used by later fields, so
/// every continuation after the first field captures it.
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

Measured flat sizes:

| Codec | `let`-bound children | Children built in their fields |
| --- | ---: | ---: |
| [`child_codecs`](../examples/src/examples/child_codecs.gleam) answer codec | 19.7 kB | 1.6 kB |
| Codegen consumer submission envelope (`order_app.submission_codec`) | 1.26 MB | 1.7 kB |
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
/// Avoid: the enum codec is built once before the chain, so every later
/// continuation captures the whole codec rather than its label strings.
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

With offered ids of the form `doc-N`, the right form copies in 7.0 kB for 5 ids
and 54.5 kB for 50, against 27.9 kB and 239.6 kB for the prebuilt form. The
captured labels are still copied once per callback, so capture only the strings
the enum needs. In a
[consumer application](BENCHMARKS.md#generated-and-combinator-codecs-in-a-consumer-2026-11-19),
enums prebuilt for 20 ids encoded 15.7 times faster and were 10.9 times bigger
to copy; rebuilding costs microseconds per conversion.

### 3. Send inputs to other processes, not built codecs

Do not hand a built codec, or a value that holds one (an agent, a tool
definition, a server's state), to another process for each operation. Build
the codec in the process that uses it, from a small builder function, and send
the builder's inputs instead: a list of labels, an identifier, a configuration
record. A generated codec is the exception, because its parts are literals and
function references.

### 4. Test the copy size

Guard every term that holds a codec or other closures and crosses a process
boundary with a test that bounds its flat size. `erts_debug:flat_size/1`
returns words; multiply by the word size for bytes. The check runs only on
Erlang, because JavaScript has no process copy.

<!-- prettier-ignore-start -->

<!-- snips: ../examples/test/copy_cost_ffi.erl -->
```erlang
-module(copy_cost_ffi).
-export([flat_size_bytes/1]).

%% Bytes a copy of Term to another process takes: a message, a spawn
%% argument or a child specification copies the term without sharing.
flat_size_bytes(Term) ->
    erts_debug:flat_size(Term) * erlang:system_info(wordsize).

```

<!-- snips: ../examples/test/copy_cost_ffi.mjs -->
```javascript
// JavaScript has no process copy; the copy-cost checks skip there.
export function flat_size_bytes(_term) {
  return -1;
}

```

<!-- snips: ../examples/test/copy_cost_test.gleam#copy-size-test -->
```gleam
@external(erlang, "copy_cost_ffi", "flat_size_bytes")
@external(javascript, "./copy_cost_ffi.mjs", "flat_size_bytes")
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

Measure the term that is actually sent: the message, the spawn argument or the
child specification, not only the codec inside it. Set the bound from a
measurement of the correct form, with headroom, so that a captured child codec
fails the test. The [examples copy-cost test](../examples/test/copy_cost_test.gleam)
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
chain, the form that rule 1 forbids. Its order codec copies in 105 kB, and
1.0 kB with the children built in their fields. The tracker issue
[`issues/codec-copy-cost/issues/01-schema-generator-captures-child-codecs.md`](../issues/codec-copy-cost/issues/01-schema-generator-captures-child-codecs.md)
records the fix.

Even when every rule is followed, a record codec holds each continuation in
about twelve callbacks, so a copied record codec costs several times its
in-heap size. The tracker issue
[`issues/record-copy-cost/issues/01-hold-a-record-continuation-once.md`](../issues/record-copy-cost/issues/01-hold-a-record-continuation-once.md)
records that structural limit.

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
