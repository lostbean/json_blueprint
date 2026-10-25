# Examples

Usage of the codec API as real code: each example compiles and runs against the
library in this checkout on Erlang and JavaScript, so it cannot drift from it. The
[README](../README.md) illustrates the record and union examples; documentation
consistency is maintained through review.

```sh
nix develop --command sh -c 'cd examples && gleam run'              # print each result
nix develop --command sh -c 'cd examples && gleam test --target erlang'
nix develop --command sh -c 'cd examples && gleam test --target javascript'
```

`sh scripts/gate.sh` builds the package with warnings as errors and runs both test
targets.

| Module in `src/examples/` | Shows                                                            |
| ------------------------- | ---------------------------------------------------------------- |
| `record`                  | encode, strict decode and schema from one record codec           |
| `optional_fields`         | absent, `null` and a value for optional and nullable fields      |
| `unions`                  | tagged union with a unit variant                                 |
| `custom_types`            | `try_map` conversions and a field checked against earlier fields |
| `errors`                  | paths, limit errors and a definition checked as data             |
| `gleam_json_bridge`       | the same codec through `gleam/json`                              |
| `larger_inputs`           | raising parser limits                                            |
| `runtime_schema`          | loading and validating against a schema that arrives at runtime  |
| `schema_inspection`       | reading a schema with `codec.view`                               |

The frozen 1.x API and the move to 2.0 are compiled tests under `test/`:
[`legacy/`](test/legacy/) holds the 1.x union, enum, tuple, optional, recursive and
schema-aware examples, and [`migration_test.gleam`](test/migration_test.gleam) moves
one record from a 1.x `Decoder` to a `Codec` and shows the wire differences that need
review. Schema-driven code generation is the separate
[`examples/codegen`](codegen/README.md).

Follow the [2.0 migration guide](../docs/MIGRATION.md) for the package upgrade
steps and the separate review of codec wire formats.
