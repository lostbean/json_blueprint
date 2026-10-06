# JSON schema and numeric evidence

Run the schema comparison from the repository root in its Nix shell:

```sh
nix develop --command python3 test/schema_check.py
```

The checker obtains the package's emitted corpus and compares codec decoding and runtime-contract validation with the independent Draft 2020-12 validator. The [frozen manifest](../schema_manifest.json) owns case identities and expected outcomes. The [checker](../schema_check.py) rejects missing, extra, repeated and replaced cases; it also checks emitted and normalized schemas.

The corpus establishes agreement for its finite profile. It does not establish general JSON Schema conformance, native numeric projection laws, complete published-version compatibility or all hostile-input bounds. Number, parser, hostile-input, legacy and code-generation tests exercise separate contracts.

`nix develop --command sh scripts/gate.sh` is the broader package gate: formatting, compilation and runtime tests on Erlang and JavaScript, the separate development generator and the schema oracle. Use the focused check when only schema agreement is at issue.

The [design](../../docs/design/design.typ) states the supported contract. [ADR 0002](../../docs/adr/0002-exact-numbers-and-native-projection.md) records numerical choices and historical source attribution; [ADR 0007](../../docs/adr/0007-freeze-legacy-source-and-wire-contracts.md) records compatibility decisions. Dependency versions belong to the pinned development environment.
