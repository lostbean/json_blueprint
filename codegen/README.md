# json_blueprint_codegen

Generate Gleam encoder, decoder, and schema functions from a typed
[JSON Blueprint](../README.md) definition. Your build task writes and compiles
the returned source.

This package and the codec API are unpublished. For an application beside this
checkout, use the runtime package by path and keep the generator in development
dependencies:

```toml
[dependencies]
json_blueprint = { path = "../json_blueprint" }

[dev-dependencies]
json_blueprint_codegen = { path = "../json_blueprint/codegen" }
```

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

The [benchmark guide](../docs/benchmarks.md) explains the timing workloads,
retained results, and commands for both targets. [ADR 0008](../docs/adr/0008-development-time-source-generation.md)
records generation ownership and the remaining scope.
