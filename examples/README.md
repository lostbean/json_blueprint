# Examples

[![CI](https://github.com/gleam-dream/json_blueprint/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/gleam-dream/json_blueprint/actions/workflows/test.yml)
[![json_blueprint on Hex](https://img.shields.io/hexpm/v/json_blueprint?label=Hex%3A%20json_blueprint)](https://hex.pm/packages/json_blueprint)
[![Gleam](https://img.shields.io/badge/Gleam-FFAFF3?logo=gleam&logoColor=000000)](https://gleam.run/)

Each codec example compiles and runs against this checkout on Erlang and
JavaScript. The [README](../README.md) illustrates the record and union examples;
documentation consistency is reviewed manually.

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
| `schema_inspection`       | reading a schema with `codec.view` and mapping its enum labels   |
| `runtime_enum`            | an enum whose labels arrive at run time, built inside its field  |
| `child_codecs`            | child codecs built in their fields, and the `let` form to avoid  |

[`test/copy_cost_test.gleam`](test/copy_cost_test.gleam) bounds the size of a
process copy of the `runtime_enum` and `child_codecs` codecs on Erlang. The
[codec practice guide](../docs/CODEC-PRACTICE.md) explains when to generate a
codec and when to write it with combinators.

The frozen 1.x API and the move to 2.0 are compiled tests under `test/`:
[`legacy/`](test/legacy/) holds the 1.x union, enum, tuple, optional, recursive and
schema-aware examples, and [`migration_test.gleam`](test/migration_test.gleam) moves
one record from a 1.x `Decoder` to a `Codec` and shows the wire differences that need
review. Build-time code generation, from a schema and from a typed definition, is the
separate [`examples/codegen`](codegen/README.md).

Follow the [2.0 migration guide](../docs/MIGRATION.md) for the package upgrade
steps and the separate review of codec wire formats.
