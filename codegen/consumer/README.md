# Schema-driven order consumer

## Boundary

- `schema/order.json` is the application wire contract. The development task loads it through `contract.parse` and passes its admitted `Schema` to `json/blueprint/codegen/schema.compile`.
- The selected module `commerce/order` exports `Order`, its nested record types, and `order_codec()`. The generated module uses the runtime package's public codec combinators.
- `src/order_app.gleam` composes the generated codec into an application-owned `Submission` envelope. Dispatch policy refuses inactive or empty orders after schema decoding.
- `generate/` is a separate development task because Gleam compiles an application's modules before running its entry point. Separating the task permits generation when the output module does not yet exist; production application dependencies contain no generator.

## Regenerate and verify

- Run these commands from this directory in `nix develop ../..`:

```sh
(cd generate && gleam run -m generate_order)
gleam format src/commerce/order.gleam src/projection/numbers.gleam
gleam test --target erlang
gleam test --target javascript
```

- From the repository root in the same shell, `sh scripts/check-schema-consumer.sh` generates to a temporary directory, formats and compares the source, tests both runtimes, and builds production output on both targets. A mismatch refuses stale output without rewriting the committed files.
- `generate/src/generate_order.gleam` owns file reads and writes. `SCHEMA_OUTPUT` selects the output directory; the library itself returns source without performing effects.

## Consumer behavior

- `test/order_consumer_test.gleam` compiles native record construction, strict text round trips, an application envelope, malformed-input recovery, located outbound bound errors, schema matching, and a finite acceptance corpus.
- Optional nullable `note` has three states: `None` omits it, `Some(None)` emits null, and `Some(Some(text))` emits text. Required nullable `reference` retains null separately from absence; optional `labels` retains absence separately from an empty list.
- Exact `Number` fields retain large and fractional mathematical values. Generated `Int` fields retain the ordinary codec's native projection limits, so a runtime contract may accept an integer that native decoding refuses.
- The handwritten benchmark codec uses the same generated record types and prebinds child codecs, as generated output does. Caller code should retain a constructed codec when reusing it; the accessor constructs a codec on each call and installs no cache.
- Generated records describe wire data. Applications retain ownership of domain types and policy; schema generation does not establish business validity.

## Measurement

- From the repository root in the Nix shell, `python3 scripts/schema_generation_benchmark.py --output /tmp/schema-generation-results` captures CPU and allocation separately for 1, 25, and 100 items across three fresh VMs per runtime.
- The [retained report](../../docs/benchmarks/schema-generation-2026-10-08/README.md) describes comparison boundaries and probe provenance. Benchmarks are observations rather than timing assertions.
