# Context map

- [Contracts](./design/contracts/CONTEXT.typ) — exact numbers, strict wire values, typed codecs, schemas, runtime contracts, and the frozen 1.x compatibility surface.
- [Generation](./design/generation/CONTEXT.typ) — development-time generators that return Gleam source for native types and codecs.

## Relationships

- **Generation is the customer of Contracts** (customer/supplier). Contracts supplies the codec, schema, and runtime helper surface that generated source calls, and changes to that surface are negotiated with the generation context because generated output pins its helper names within a major version.
- **Generated source is a conformist of Contracts.** Output checked into an application uses the public codec combinators as they are and imposes no change on them.
- **Consumers are outside both contexts.** Relay, Fabric, and LLM adapters read the public schema projection and own their own admission policy.
