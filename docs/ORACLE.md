# Oracle

The references this package is compared against, what is compared, and how far
the comparison reaches. [Benchmarks](BENCHMARKS.md) are the companion document
for timing; neither document gates a claim the other makes. The
[design](design/contracts/design.typ#oracle-and-behavioral-evidence) states the
supported contract, and [AGENTS.md](../AGENTS.md#references) points here.

## References

| Reference | Upstream | Pin | Used for |
| --- | --- | --- | --- |
| `jsonschema` `Draft202012Validator` | <https://github.com/python-jsonschema/jsonschema> | 4.26.0, fixed by `flake.lock` through the repository Nix shell; `scripts/benchmark.sh` records the version it ran | Independent judgment of emitted and normalized schemas against instances |
| JSON Schema Draft 2020-12 meta-schema | <https://json-schema.org/draft/2020-12/schema> | the copy bundled with the pinned `jsonschema` | `Draft202012Validator.check_schema` over the finite-profile diagnostic fixtures |
| Frozen manifest [`test/schema_manifest.json`](../test/schema_manifest.json) | this repository | checked in; the checker fixes its 16 families and 85 cases | Case identities, instances, schemas and expected outcomes |
| Diagnostic fixtures [`test/contract_profile_cases.json`](../test/contract_profile_cases.json) | this repository | checked in; 50 fixtures | Valid, unsupported and malformed schema documents with their diagnostic paths |
| Source baseline 1.7.1 | this repository, commit `0e379c6491d34aca49795f716e87b9003df0130e` (MIT) | commit | The frozen 1.x source and wire contracts |
| Oversight interface-laboratory probes | sibling workspace, commit `bd0b83743533313eb9b4eee2bf7f99ed68a26750` | commit | Origin of the initial exact-number and finite-schema cases; the source ledger declared no license, so no third-party grant is claimed |

## What is compared

1. **Finite schema agreement** ([`test/schema_check.py`](../test/schema_check.py)).
   The checker obtains the package's emitted corpus and compares three
   outcomes per case with the validator: the codec decoder (`accepted`), the
   runtime contract loaded from the emitted document (`runtime_accepted`), and
   the validator's own verdict on both the emitted and the normalized schema.
   All must agree with the manifest.
2. **Profile diagnostics** ([`test/schema_profile_check.py`](../test/schema_profile_check.py)).
   Each fixture's schema is checked with `check_schema`: every fixture that is
   not `malformed` must be a valid Draft 2020-12 schema. This establishes schema
   validity only; Gleam tests consume the same documents and check the
   diagnostic paths.
3. **Runtime cases** ([`test/schema_oracle_test.gleam`](../test/schema_oracle_test.gleam))
   replay the manifest through the Gleam package on both targets.

## Outcome classes

| Class | Meaning | Result |
| --- | --- | --- |
| Agreement | Codec, contract and validator accept or reject the instance alike | pass |
| Disagreement | Any of the three differs from the manifest or from each other | fail |
| Missing, extra, repeated or replaced case | The corpus no longer matches the frozen manifest or the family counts | fail, closed |
| Native projection refusal | A mathematically valid number that a native `Int` or `Float` cannot hold | outside this corpus; covered by the number tests |

## Exclusions and deliberate differences

- The corpus is a finite profile. It does not establish general JSON Schema
  conformance, native numeric projection laws, complete published-version
  compatibility or all hostile-input bounds. Number, parser, hostile-input,
  legacy and code-generation tests exercise those contracts separately.
- Mathematical acceptance and native projection differ on purpose: Erlang
  bignums, JavaScript safe integers and binary64 rounding have different native
  contracts even when exact JSON values compare equal.
- The frozen 1.x renderer labels its schema Draft-07 although some keywords come
  from later drafts, so it is not compared against the Draft 2020-12 validator
  ([ADR 0007](adr/0007-freeze-legacy-source-and-wire-contracts.md)).
- An earlier implementation snapshot used a 61-case, 13-family corpus and
  intermediate API names; its all-green status is historical execution
  evidence and cannot certify current coverage. The
  [original attribution table](https://github.com/lostbean/json_blueprint/blob/4ed1d2efac5166a1feffde891285852926445dc1/test/oracle/schema-aware-core.md)
  keeps the exact test identities, input families and source revisions.

## Run it

```sh
nix develop --command python3 test/schema_check.py
nix develop --command python3 test/schema_profile_check.py
nix develop --command sh scripts/gate.sh   # the broader gate, which runs both
```

Use the focused checks when only schema agreement is at issue.

## Where the decisions are recorded

[ADR 0002](adr/0002-exact-numbers-and-native-projection.md) records the
numerical choices and the source attribution,
[ADR 0007](adr/0007-freeze-legacy-source-and-wire-contracts.md) the
compatibility decisions, and [ADR 0010](adr/0010-retain-benchmark-observations-as-non-asserting-evidence.md)
why timing evidence stays separate from this corpus.
