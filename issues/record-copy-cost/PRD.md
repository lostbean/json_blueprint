# A copied record codec costs about its in-heap size

Status: ready-for-human
Category: enhancement

AI-assisted contribution.

## Problem

A BEAM process copy does not preserve sharing. A record codec built with
`field`, `optional_field` and `success` holds each field's continuation in
about twelve callbacks: the five operations of a field (encode, decode,
native decode, names, properties), its placeholder, and the record callbacks
that each retain those operations. Whatever a continuation captures is
therefore copied about twelve times, and a copied record codec costs many times
its in-heap size even when its author follows every rule of the
[codec practice guide](../../docs/CODEC-PRACTICE.md).

## User stories

- As an application author, I send a value that holds a record codec (an
  agent, a tool definition, a decision point) to another process, and the copy
  costs close to the codec's in-heap size.
- As a library author whose record codec must capture a value, such as a
  caller-supplied output codec in a later field, I do not pay for that value
  once per callback.

## Decisions

- Copy size is measured as `erts_debug:flat_size/1` on Erlang and compared with
  `erts_debug:size/1`, the in-heap size. JavaScript has no process copy.
- The public record-builder API (`field`, `optional_field`, `success` and
  getters passed with `get:`) stays source-compatible within 2.x.

## Testing decisions

- Copy-size tests bound a record codec whose continuation captures a large
  value to a small multiple of its in-heap size on Erlang, beside the existing
  additive-growth tests in `test/codec_copy_cost_test.gleam`.

## Out of scope

- Application code that sends codecs; consumers own their process design.
- The schema-driven generator's own capture, recorded in
  [`codec-copy-cost`](../codec-copy-cost/PRD.md).
