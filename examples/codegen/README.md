# Schema-driven order consumer

A separate consumer package that loads `schema/order.json` through `contract.parse`, generates the `commerce/order` module with `json/blueprint/codegen/schema.compile`, and composes the generated codec into an application-owned envelope. Generation runs in the separate `generate/` task, while generation and production both depend on `json_blueprint`.

## Run

From this directory in `nix develop ../..`:

```sh
(cd generate && gleam run -m generate_order)
gleam format src/commerce/order.gleam src/projection/numbers.gleam
gleam test --target erlang
gleam test --target javascript
```

From the repository root in the same shell, `sh scripts/check-schema-consumer.sh` regenerates to a temporary directory, uses that fresh source in a disposable consumer, tests both targets, and builds production output without development dependencies. `SCHEMA_OUTPUT` selects the output directory of the generation task.

`python3 scripts/schema_generation_benchmark.py --output /tmp/schema-generation-results` captures CPU and allocation for 1, 25, and 100 items across three fresh VMs per target; the method and retained results are in [docs/BENCHMARKS.md](../../docs/BENCHMARKS.md#schema-driven-generation-2026-10-08).

## Reference

The [generation design](../../docs/design/design-layer.pdf) states the contract this consumer exercises. [ADR 0008](../../docs/adr/0008-development-time-source-generation.md) records the decision and [ADR 0010](../../docs/adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md) the measurement policy. The usage examples for the codec API are in [`examples/`](../../examples/README.md).
