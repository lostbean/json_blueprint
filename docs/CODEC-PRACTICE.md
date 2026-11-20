# Codec practice

This guide says when to generate a codec, when to write one with combinators,
and how to write combinator codecs that stay cheap to send between BEAM
processes. It is for application authors and for agents that write codecs.
The examples it cites compile and run in this repository's gate.

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
layer adds a fixed number of bytes. An application that sends codecs, or
values that hold codecs, to other processes can run out of memory on 2.1.0 or
earlier. The [benchmark record](BENCHMARKS.md#codec-copy-cost-2026-11-19)
holds the before and after measurements.

## Choose generated codecs or combinators

| Use | When |
| --- | --- |
| Typed-definition generator ([ADR 0016](adr/0016-specialize-generated-codecs-with-runtime-semantics.md)) | The JSON shape is fixed at build time, and the codec is hot, long-lived, or crosses processes: stored payloads, job and queue payloads, API bodies, decision envelopes. |
| Combinators (`json/blueprint/codec`) | The shape depends on run-time values, such as enum labels known only for one run; the shape needs tagged unions, shared definitions or recursion; the codec uses `codec.custom`, `codec.value` or an arbitrary `try_map`; or the codec is used once. |

Reasons for generated codecs:

- A generated codec is module functions and literals. The BEAM does not copy
  literals or function references between processes. In a consumer study of
  an application's codecs, a process that received a generated codec grew by 0 B.
- In this repository's [codegen consumer](../examples/codegen/README.md), the
  export job codec measures 952 B of flat size when generated and 19.3 kB when
  built from the same definition with combinators.
- In the same study, generated codecs encoded 4 to 90 times faster and decoded
  1.3 to 30 times faster than the combinator codecs they replaced.

Reasons for combinators:

- The typed-definition generator cannot express run-time values, unions,
  shared definitions or recursion today; see [generator gaps](#generator-gaps).
- A combinator codec costs microseconds per conversion. Next to a model call or
  a database round trip, that cost is negligible.

The timing numbers are observations of one consumer on one machine, not
guarantees. [ADR 0010](adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md)
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

```gleam
pub fn answer_codec() -> Codec(Answer) {
  let contact = contact_codec()
  use summary <- codec.field("summary", codec.string(), get: fn(a) {
    a.summary
  })
  use primary <- codec.field("primary", contact, get: fn(a) { a.primary })
  use backup <- codec.optional_field("backup", contact, get: fn(a) {
    a.backup
  })
  codec.success(Answer(summary:, primary:, backup:))
}
```

Right: each field calls the function that builds its child codec.

```gleam
pub fn answer_codec() -> Codec(Answer) {
  use summary <- codec.field("summary", codec.string(), get: fn(a) {
    a.summary
  })
  use primary <- codec.field("primary", contact_codec(), get: fn(a) {
    a.primary
  })
  use backup <- codec.optional_field("backup", contact_codec(), get: fn(a) {
    a.backup
  })
  codec.success(Answer(summary:, primary:, backup:))
}
```

Measured flat sizes:

| Codec | `let`-bound children | Children built in their fields |
| --- | ---: | ---: |
| [`child_codecs`](../examples/src/examples/child_codecs.gleam) answer codec | 19.7 kB | 1.6 kB |
| Codegen consumer submission envelope (`order_app.submission_codec`) | 1.26 MB | 1.7 kB |
| Application curator answer codec | 88.6 kB | 1.9 kB |

Both forms convert the same JSON and describe the same schema. A child built
in a later field is constructed when the continuation runs, which costs
microseconds per conversion.

### 2. Build run-time enums inside the field

When enum labels are known only at run time, capture the small data (the label
pairs, converted once) and call `codec.string_enum` inside the field that uses
it. Check the codec once where the labels arrive, because labels from data can
repeat: `codec.check` returns the problem instead of a later panic.

Wrong: the prebuilt enum codec is captured by every later continuation.

```gleam
pub fn citation_codec(offered: List(String)) -> Codec(Citation) {
  let sources = codec.string_enum(list.map(offered, fn(id) { #(id, id) }))
  use claim <- codec.field("claim", codec.string(), get: fn(c) { c.claim })
  use source_ids <- codec.field("source_ids", codec.list(sources), get: fn(c) {
    c.source_ids
  })
  codec.success(Citation(claim:, source_ids:))
}
```

Right: the continuation captures only the label strings.

```gleam
pub fn citation_codec(offered: List(String)) -> Codec(Citation) {
  let labels = list.map(offered, fn(id) { #(id, id) })
  use claim <- codec.field("claim", codec.string(), get: fn(c) { c.claim })
  use source_ids <- codec.field(
    "source_ids",
    codec.list(codec.string_enum(labels)),
    get: fn(c) { c.source_ids },
  )
  codec.success(Citation(claim:, source_ids:))
}
```

In [`runtime_enum`](../examples/src/examples/runtime_enum.gleam), the right form
copies in 7.0 kB for 5 offered ids and 93 kB for 50, against 27.9 kB and
417 kB for the prebuilt form. The captured labels are still copied once per
callback, so keep them to the strings the enum needs. In the consumer study, a
prebuilt enum converted 17 times faster but was 11 times bigger to copy; the
conversion cost of rebuilding is microseconds.

### 3. Send inputs to other processes, not built codecs

Do not hand built codecs, or values that hold them (agents, tools, tool
servers, decision points), to another process for each operation. Build the
codec in the process that uses it, from a small builder function, and send the
builder's inputs instead: a list of labels, an identifier, a configuration
record. A generated codec is the exception, because its parts are literals and
function references.

### 4. Test the copy size

Guard every term that crosses a process boundary with a test that bounds its
flat size. `erts_debug:flat_size/1` returns words; multiply by the word size
for bytes. The check runs only on Erlang, because JavaScript has no process
copy.

```erlang
-module(copy_cost_ffi).
-export([flat_size_bytes/1]).

flat_size_bytes(Term) ->
    erts_debug:flat_size(Term) * erlang:system_info(wordsize).
```

```javascript
// copy_cost_ffi.mjs: JavaScript has no process copy.
export function flat_size_bytes(_term) {
  return -1;
}
```

```gleam
@external(erlang, "copy_cost_ffi", "flat_size_bytes")
@external(javascript, "./copy_cost_ffi.mjs", "flat_size_bytes")
fn flat_size_bytes(term: a) -> Int

pub fn worker_message_stays_small_test() {
  case flat_size_bytes(build_worker_message()) {
    -1 -> Nil
    bytes -> { bytes < 16_384 } |> should.be_true
  }
}
```

Measure the term that is actually sent: the message, the spawn argument or the
child specification, not only the codec inside it. Set the bound from a
measurement of the correct form, with headroom, so that a captured child
codec fails the test. The [examples copy-cost test](../examples/test/copy_cost_test.gleam)
applies this check to the examples above.

## Generator gaps

The typed-definition generator (`json/blueprint/codegen`) does not yet cover
the following. Use combinators for these shapes, following the rules above.

- Run-time enums: each `enum_variant` names a constructor at build time.
- Tagged unions, shared definitions, recursive definitions and type aliases.
- `codec.custom`, `codec.value` and arbitrary `try_map`: `imap` accepts only a
  pure `named_mapping`.
- String-valued enums: `enum_variant` needs a constructor reference, so a
  `String` field with a closed set of labels needs a custom type and `imap`.
- Exact `Number` fields: `compile` returns `NativeNumberUnsupported`.
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
  produced `Unreachable pattern` warnings in the generated encoders, which
  fails a build with `--warnings-as-errors`. The generator on `main` compares
  enum values by equality instead and emits no warning; regenerate the module
  once a release includes that change.

The schema-driven generator binds each child codec with `let` before its field
chain, the form that rule 1 forbids. Its order codec copies in 105 kB, and
1.0 kB with the children built in their fields. The tracker issue
[`issues/codec-copy-cost/issues/01-schema-generator-captures-child-codecs.md`](../issues/codec-copy-cost/issues/01-schema-generator-captures-child-codecs.md)
records the fix.

## Examples

- [`examples/src/examples/child_codecs.gleam`](../examples/src/examples/child_codecs.gleam):
  rule 1, both forms, with their equal conversions.
- [`examples/src/examples/runtime_enum.gleam`](../examples/src/examples/runtime_enum.gleam):
  rule 2, with `codec.check` for labels from data.
- [`examples/test/copy_cost_test.gleam`](../examples/test/copy_cost_test.gleam):
  rule 4, the copy-size bounds of those examples on Erlang.
- [`examples/codegen`](../examples/codegen/README.md): a fixed job payload
  generated from a typed definition, its regeneration check, and its copy size
  next to the combinator codec of the same definition.
