# Codecs stay cheap to send between processes

Status: done
Category: enhancement

AI-assisted contribution.

## Problem

A BEAM process copy does not preserve sharing, so a codec, or a value that
holds one, costs its flat size to send. Version 2.1.1 made every combinator
retain only its child operations, so nesting adds to the copy size instead of
multiplying it. Codecs written or generated with a child codec bound before a
`use … <- codec.field` chain still copy that child once per callback that holds
the continuation. [`docs/CODEC-PRACTICE.md`](../../docs/CODEC-PRACTICE.md) states
the rules for application authors.

## User stories

- As an application author, I send a generated or hand-written codec to a worker
  process and its copy size stays close to the size of one copy of its parts.
- As an application author, I generate a codec from a schema and its output
  follows the same rules the guide asks of hand-written codecs.

## Decisions

- Copy size is measured as `erts_debug:flat_size/1` on Erlang. JavaScript has no
  process copy and skips the measure.
- Construction cost per conversion, in microseconds, is accepted in exchange for
  a small copy size.

## Testing decisions

- Copy-size checks bound the flat size of the codecs under test on Erlang and
  run in the ordinary gate.

## Out of scope

- Application code that sends codecs; consumers own their process design.
