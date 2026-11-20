# A copied record codec duplicates its continuation about twelve times

Status: needs-triage
Category: enhancement

AI-assisted contribution.

## Parent

[A copied record codec costs about its in-heap size](../PRD.md)

## Problem

Each `field` and `optional_field` keeps its continuation in five field
operations and a placeholder, and the record wraps those operations in its own
callbacks. Inside one process these closures share the continuation. A process
copy duplicates the continuation's environment once per closure that holds it,
about twelve times.

The [codec practice guide](../../../docs/CODEC-PRACTICE.md) removes most of the
cost by building child codecs inside their fields, but a consumer cannot always
do so. Evidence, all on Erlang/OTP 29 with `json_blueprint` 2.1.1:

- The decisions library's `view.codec(output)` must capture the caller's output
  codec in a later field. Its flat size is about 1.9 kB plus twelve times the
  1,664-byte output codec, 21.9 kB in total, measured in the review of
  gleam-dream/decisions PR 5.
- In an application built on JSON Blueprint, the same view codec
  around a 1.5 kB wire codec copied in 22.5 kB against 1.8 kB in-heap, and
  values holding record codecs copied at 9 to 45 times their in-heap size
  (an agent: 250.8 kB against 18.6 kB; a curator agent: 476.7 kB against
  10.7 kB). The [benchmark record](../../../docs/BENCHMARKS.md#generated-and-combinator-codecs-in-a-consumer-2026-11-19)
  holds the method and environment.

## Behavior to build

A record codec holds each field's continuation once, so a copy of the codec
costs close to its in-heap size and a value captured by a continuation is
copied once. Two representations are candidates; choosing one is the first
step:

- field operations take the field record as a parameter instead of closing
  over the continuation separately in each operation;
- record codecs are represented as data that one interpreter walks.

## Interfaces

- `json/blueprint/codec`: `field`, `optional_field`, `success` and the opaque
  `Codec(a)` representation. Public signatures do not change.

## Acceptance criteria

- A record codec whose later field captures a codec of in-heap size S copies
  in at most a small constant multiple of S plus the record's own size, on
  Erlang, enforced by a test.
- Conversion results, errors, paths, optional states, schemas, placeholders
  and definition errors are unchanged; the existing root, examples and consumer
  suites pass on both targets.
- The additive-growth tests in `test/codec_copy_cost_test.gleam` still pass.
- Conversion and construction times are captured before and after in
  `docs/BENCHMARKS.md`, per ADR 0010.

## Out of scope

- The schema-driven generator's emitted form
  ([codec-copy-cost issue 01](../../codec-copy-cost/issues/01-schema-generator-captures-child-codecs.md)).
- Generated typed-definition codecs, which capture no child codec.

## Blocked by

None.

## Gate

- `nix develop --command sh scripts/gate.sh`
- `nix run .#design-gate-check -- docs/design .`
- `nix flake check`

## Stop and ask

- If either representation changes a public signature, record decoding order,
  or the placeholder-driven schema discovery that ADR 0004 records.
