# json_blueprint_codegen

Generate reviewable Gleam source through two development-time paths:

- A caller-authored typed `Definition(a)` generates specialized encoder, decoder, and schema functions for an existing native type.
- An [admitted closed-object schema](#generate-native-records-from-a-schema) generates native record types and an ordinary typed codec.

Your build task writes, formats, and compiles the returned source. Both paths use
[JSON Blueprint](../README.md) at runtime.

This package and the codec API are unpublished. For an application beside this
checkout, use the runtime package by path and keep the generator in development
dependencies:

```toml
[dependencies]
json_blueprint = { path = "../json_blueprint" }

[dev-dependencies]
json_blueprint_codegen = { path = "../json_blueprint/codegen" }
```

<!-- prettier-ignore-start -->

<!-- snips: test/module_docs/codegen_example_test.gleam#codegen-example -->
```gleam
import json/blueprint/codec
import json/blueprint/codegen

pub fn names_definition() -> codegen.Definition(List(String)) {
  codegen.list(codegen.string())
}

pub fn example() {
  let assert Ok(["a", "b"]) =
    codec.decode_json(codegen.runtime(names_definition()), "[\"a\",\"b\"]")
  // In a build task: write `content` to "src/" <> path.
  let assert Ok(codegen.GeneratedModule(path:, content:, fingerprint: _)) =
    codegen.compile("generated/names_codec", "names", names_definition())
  #(path, content)
}

```

<!-- prettier-ignore-end -->

- A `Definition(a)` mirrors the codec shapes: `string`, `int`, `number`,
  `bool`, `integer_between`, `pair`, `list`, `nullable`, `string_enum`,
  `required` and `optional` properties joined with `combine` and closed with
  `object`, and `imap` with a `named_mapping`.
- `runtime(definition)` returns its codec for interpreted use. Applications
  using only generated functions need the runtime package and generated source.
- `compile(module_path, name, definition)` returns the module source. Write
  it under `src/`, run `gleam format` on it, and add a test that compiles it
  again and compares, as the [compiled fixture test](test/compiled_codec_test.gleam)
  does here. Generation does not write files or start a process.
- A generated module exports `encode_<name>`, `decode_<name>`,
  `encode_<name>_json`, `decode_<name>_json` (strict parser),
  `decode_<name>_json_native` (`gleam/json`, 1 MiB pre-check),
  `<name>_schema()` and `<name>_codec()`.

From `codegen/` in the repository Nix shell, regenerate its fixtures with:

```sh
gleam run -m compiled_codec_runner && gleam format test/generated
```

From the repository root, `nix develop --command sh scripts/benchmark.sh` runs the timing harness on both targets and writes a fresh evidence directory. [ADR 0008](../docs/adr/0008-development-time-source-generation.md) records generation ownership and the remaining scope, and [ADR 0010](../docs/adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md) records the measurement policy; method, provenance and retained results are in [docs/BENCHMARKS.md](../docs/BENCHMARKS.md).

## Generate native records from a schema

- The separate `json/blueprint/codegen/schema` module accepts an admitted closed-object `codec.Schema` and explicit module and root names. Its `compile` function returns the same `GeneratedModule` source record as the typed-definition generator.
- A generated schema module exports native root and nested record types plus one root codec accessor. Applications use ordinary `codec.encode`, `codec.decode`, and their strict text counterparts with that codec.
- Supported children include closed records, strings, booleans, native integers and integer ranges, exact numbers and number ranges, lists, pairs, nullable values, and optional properties. Constraints and descriptions survive generation; supported structure is checked by Gleam on outbound native values while ordinary codecs check value constraints.
- Wire names are preserved. Native names are deterministic; invalid names, name collisions, and unsupported shapes return typed failures with logical schema locations instead of partial source.
- Enums, tagged unions, unconstrained values, shared or recursive definitions, and non-object roots are outside this generation slice. Runtime-schema admission does not imply generation support.
- The [separate order consumer](consumer/README.md) demonstrates the complete workflow, including a schema file, development-only generation task, committed output, application-owned policy, recovery, both runtime targets, and freshly generated-code integration tests. Its production package depends only on the runtime package and compiled source.
- Generated codecs use public runtime combinators and add no second contract-validation pass. Codec accessors construct values on each call; retain a codec for repeated use. [ADR 0010](../docs/adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md) records the separate construction, conversion, and build-time generation costs.
