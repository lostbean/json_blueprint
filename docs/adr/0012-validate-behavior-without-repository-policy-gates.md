<a id="adr-0012"></a>

# ADR-0012: Validate behavior without repository policy gates

Status: accepted
Date: 2026-10-20

## Decision

Required validation uses shared tools directly for formatting, compilation and
design-layer integrity, alongside local unit and integration tests. External consumers, independent schema or implementation
comparisons, and compiler rejection fixtures remain behavioral integration tests.

Remove documentation equality, source-layout and header rules, oracle-ledger
validation, gate self-tests, test-name inventories, and source-evidence acceptance
checks. Shared treefmt and design-layer validators remain required and CI invokes
them directly, without locally maintained wrappers or self-tests. Local scripts
own application behavior and the minimum setup needed to execute it. Benchmarks and endurance observations are optional;
they are not prerequisites for integration.

This supersedes the validation requirements in ADR-0010 and earlier decisions
where they require these removed checks; their behavioral contracts are unchanged.

## Consequences

Repository-specific conventions and duplicated evidence bookkeeping no longer
create local checker maintenance. Shared format and design contracts still apply.
Review owns application-specific prose consistency, architecture and provenance. Behavioral assertions, compiler failures and cleanup
still fail their commands normally. A passing suite proves its executed scenarios,
not completeness against a separately maintained inventory.
