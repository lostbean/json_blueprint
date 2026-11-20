# Generated codec consumer

[![CI](https://github.com/lostbean/json_blueprint/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/lostbean/json_blueprint/actions/workflows/test.yml)
[![json_blueprint on Hex](https://img.shields.io/hexpm/v/json_blueprint?label=Hex%3A%20json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Gleam](https://img.shields.io/badge/Gleam-FFAFF3?logo=gleam&logoColor=000000)](https://gleam.run/)

A separate consumer package that loads `schema/order.json` through `contract.parse`, generates the `commerce/order` module with `json/blueprint/codegen/schema.compile`, and composes the generated codec into an application-owned envelope. Generation runs in the separate `generate/` task, while generation and production both depend on `json_blueprint`.

The consumer also generates the codec of a fixed queue payload, `jobs/export_job`, from a typed definition with `json/blueprint/codegen.compile`. This is the path the [codec practice guide](../../docs/CODEC-PRACTICE.md#choose-generated-codecs-or-combinators) recommends for a fixed shape whose codec is hot or held by other processes, such as every worker that decodes the job: the generated codec refers to module functions and literals and captures no child codec. The definition and its runner are development modules under `test/`, because the definition refers to the application's native types; the generated module imports `gleam/json`, so the consumer depends on `gleam_json` directly. `test/export_job_test.gleam` checks the generated codec against its runtime definition and compares their copy sizes on Erlang.

## Run

From this directory in `nix develop ../..`:

```sh
(cd generate && gleam run -m generate_order)
gleam format src/commerce/order.gleam src/projection/numbers.gleam
gleam run -m generate_export_job
gleam format src/jobs/export_job_codec.gleam
gleam test --target erlang
gleam test --target javascript
```

From the repository root in the same shell, `sh scripts/check-schema-consumer.sh` regenerates to a temporary directory, uses that fresh source in a disposable consumer, regenerates the export job codec there and compares it with the committed module, tests both targets, and builds production output without development dependencies. `SCHEMA_OUTPUT` selects the output directory of the generation task.

`python3 scripts/schema_generation_benchmark.py --output /tmp/schema-generation-results` captures CPU and allocation for 1, 25, and 100 items across three fresh VMs per target; the method and retained results are in [docs/BENCHMARKS.md](../../docs/BENCHMARKS.md#schema-driven-generation-2026-10-08).

## Reference

The [generation design](../../docs/design/design-layer.pdf) states the contract this consumer exercises. [ADR 0008](../../docs/adr/0008-development-time-source-generation.md) records the decision and [ADR 0010](../../docs/adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md) the measurement policy. The usage examples for the codec API are in [`examples/`](../../examples/README.md).
