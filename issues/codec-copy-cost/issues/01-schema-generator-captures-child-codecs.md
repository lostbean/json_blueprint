# Schema-generated record codecs copy each child codec once per callback

Status: needs-triage
Category: bug

AI-assisted contribution.

## Parent

[Codecs stay cheap to send between processes](../PRD.md)

## Problem

The schema-driven generator (`json/blueprint/codegen/schema.compile`) emits each
record codec with its child codecs bound by `let` before the field chain, then
uses them in later fields. Every continuation after the first field captures
those child codecs, and a process copy duplicates them once per callback that
holds the continuation.

Observed on 2026-11-19 with the committed `examples/codegen` consumer on
Erlang/OTP 29, as flat size in bytes:

| Codec | As generated | Children built in their fields |
| --- | ---: | ---: |
| `commerce/order.order_codec()` | 105,112 | 1,008 |

The hand-edited variant passed the consumer's conversion tests. The
[codec practice guide](../../../docs/CODEC-PRACTICE.md#1-build-each-child-codec-where-it-is-used)
asks application authors not to write this form.

## Behavior to build

Generated record codecs build each child codec in the field that uses it, so
the copy size of a generated record no longer grows with the number of
callbacks that hold its continuation.

## Interfaces

- `json/blueprint/codegen/schema.compile`: the emitted source changes; the
  generated codec's conversions, errors, optional states and schema do not.

## Acceptance criteria

- Regenerated `examples/codegen` modules convert, refuse and describe exactly
  as before on both targets.
- A copy-size test on Erlang bounds the flat size of the generated order codec
  to the size of the form with children built in their fields, with headroom.
- Regenerated fixtures and the consumer's committed output match the new
  emitter, and their fingerprints change accordingly.

## Out of scope

- The typed-definition generator, whose output is module functions and
  literals.
- Construction cost per conversion; record it in the benchmark document if it
  is measured.

## Blocked by

None.

## Gate

- `nix develop --command sh scripts/gate.sh`
- `nix run .#design-gate-check -- docs/design .`
- `nix flake check`

## Stop and ask

- If a generated child codec must be built once for a reason the generation
  design states, such as placeholder discovery or construction cost.
