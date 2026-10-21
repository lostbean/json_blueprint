#import ".render/designlib.typ": *
#let title = [JSON Blueprint]
#let index_only = true
#let body = [
  #section(title: "Foundation", lead: [Two contexts divide the package: #ctx("contracts") owns runtime values, codecs, schemas and validation, and #ctx("generation") owns development-time source generation. Each context states its own goals, invariants and principles.], body: [
    #no-goal(title: "Execute or authorize application operations")[Tool registration, provider admission, transport, job execution, workflow execution, and application policy belong to consumers. Ordinary JSON serialization can use standard Gleam JSON without this package.]
    #no-goal(title: "Claim general JSON Schema conformance")[The #term("term-finite-profile") has bounded independent evidence. A Draft 2020-12 dialect label does not imply support for every keyword or an arbitrary remote schema.]
    #invariant(title: "Application runtime never depends on the generator", enforcement: "mechanism")[The generator is a separate development-only package. A production build contains the runtime package and generated source, and the consumer check compiles an isolated production copy without the generator dependency.]
    #points(
      [Ownership and finite support are recorded in #adr(1). Generation placement is recorded in #adr(8). The release posture of the codec API is recorded in #adr(11).],
    )
  ])

  #pagebreak(weak: true)
  #pending-ledger(
    pending-entry(title: "Release version of the codec API", kind: "ruling", since: "2026-10-08")[The manifest declares 1.7.1 while the codec API, runtime contracts and generator are unreleased. The owner decides when and under which version number they are released; #adr(11) records the hold.],
  )

  #pagebreak(weak: true)
  #section(title: "System at a glance", lead: [One package supplies pure values, schemas, codecs and contracts at runtime, and a separate development package supplies source generation.], body: [
    #diagram(altitude: "L1", viewpoint: "context-ownership", title: "Application-owned composition", caption: [Arrows declare dependency direction. Consumers select their own protocol and provider admission policy.], nodes: (
      (id: "app", label: "Application", kind: "actor", tint: "slate"),
      (id: "json", label: "JSON Blueprint", sub: "json_blueprint", kind: "bounded-context", tint: "teal"),
      (id: "consumers", label: "Relay / Fabric / LLM", sub: "consumer policies", kind: "external-system", tint: "slate"),
      (id: "ordinary", label: "Standard Gleam JSON", kind: "external-system", tint: "slate"),
    ), edges: (
      (from: "app", to: "json", relation: "dependency", label: "schema-aware conversion"),
      (from: "consumers", to: "json", relation: "dependency", label: "schema and typed boundaries"),
      (from: "app", to: "ordinary", relation: "dependency", label: "ordinary serialization"),
      (from: "json", to: "ordinary", relation: "dependency", label: "explicit bridges and legacy parsing"),
    ))
    #diagram(altitude: "L2", viewpoint: "context-ownership", title: "Contexts", caption: [The generation context depends on the contracts context and never the reverse. Generated source depends on the contracts runtime only.], nodes: (
      (id: "contracts", label: "Contracts", sub: "values, codecs, schemas, validation", kind: "bounded-context", tint: "teal"),
      (id: "generation", label: "Generation", sub: "development-time source", kind: "bounded-context", tint: "violet"),
      (id: "output", label: "Generated source", sub: "checked into the application", kind: "external-system", tint: "slate"),
    ), edges: (
      (from: "generation", to: "contracts", relation: "dependency", label: "codec, schema, runtime helpers"),
      (from: "generation", to: "output", relation: "dataflow", label: "returns source"),
      (from: "output", to: "contracts", relation: "dependency", label: "public codec combinators"),
    ))
    #points(
      [The package exports pure values and synchronous conversion operations. It starts no process, owns no connection, and stores no mutable runtime state.],
      [#ctx("contracts") holds Wire values, Typed codecs, Runtime contracts and Legacy compatibility. #ctx("generation") holds the typed-definition generator, schema materialization and the schema-driven native generator. #lnk("../CONTEXT-MAP.md")[The context map] declares their relationship.],
      [Relay owns protocol declarations and revision-specific generation. Fabric owns tool and model execution. LLM adapters own provider lowering and admission. These consumers inspect opaque schema children; they never acquire authority from a dialect label alone.],
      [No operation supplies authorization, identifiers for business entities, correlation, idempotency keys, retries, cancellation, or a wall-clock deadline. Applications own those capabilities where their operation requires them.],
    )
  ])

  #section(title: "Repository verification", lead: [Verification distinguishes finite acceptance, native projection, legacy behavior, generated parity, executable documentation and measurement.], body: [
    #subsection(title: "Gate and continuous integration")[
      #md-table(2, (
        [Check], [Scope],
        [Formatting], [A Nix check formats a copied source tree; frozen oracle bytes, generated fixtures, rendered design evidence and build output are excluded],
        [Native compilation], [Authored Erlang FFI compiles independently with warnings as errors],
        [Package tests], [Compilation with warnings as errors and the test suite on Erlang and JavaScript for the root package and for the codegen package],
        [Usage examples], [The examples package builds with warnings as errors, runs its tests on Erlang and JavaScript, and runs once; every usage topic and the legacy and migration forms are compiled code],
        [Schema consumer], [Fresh generation in disposable packages, tests on both targets, and an isolated production build without the generator],
        [Independent oracles], [A Python checker compares emitted schemas, decoders and contracts with a Draft 2020-12 validator; a second checker covers retained profile diagnostics. #lnk("../ORACLE.md")[The oracle document] pins the references and states the limits of the comparison],
      ))
      #points(
        [The package gate removes each package's build output first, so an obsolete compiled module cannot hide a missing source module. Runtime logs are evidence and never substitute for compiler diagnostics.],
        [Continuous integration runs the gate on Erlang/OTP and Node.js with formatting and compilation as the required checks. Nix pins the compiler, the runtimes and the Python oracle environment. Browser JavaScript is not tested.],
        [CI invokes the shared treefmt and design-layer validators directly. Local scripts own application behavior; no local formatter or design-check wrappers are maintained. #adr(12) #lnk("../../scripts/gate.sh")[The package gate] and #lnk("../../flake.nix")[the development environment] define operational verification.],
      )
    ]
    #subsection(title: "Executable documentation")[
      #points(
        [Usage is compiled code. Each topic is a module of the #lnk("../../examples/README.md")[examples package], which the gate builds and runs on both targets. The shared pinned Snips tool synchronizes README snippets from marked regions of compiled, tested examples. Local bespoke snippet-equality checkers remain removed. The legacy 1.x forms and the move to a codec are compiled tests under #lnk("../../examples/test/legacy/union_type_test.gleam")[examples/test]. Public module examples and the codegen consumer remain executable behavioral tests.],
        [Prose and checked examples stay aligned. Documentation that states a limit or default names the design section that owns it.],
      )
    ]
    #subsection(title: "Measurement")[
      #points(
        [Benchmarks are observations of a named checkout. No timing threshold enters a gate, and the ordinary gate keeps the semantic tests of the benchmark fixtures. #adr(10) records the policy and the accepted findings.],
        [Each capture starts three fresh VMs per target, runs an untimed warmup, and reports the median of the VM medians with the range of those medians. A capture records its source fingerprints, lockfile hashes, toolchain versions and host. Comparisons run the baseline before the changed code in fixed order.],
        [Complete-text, Value-only and construction cases measure different work. A comparison matches cases with the same parser policy: generated native decoding uses the standard JSON parser and strict decoding uses the package parser, with different number, duplicate-key and resource guarantees.],
        [The weekly benchmark workflow runs the harness on both targets. #lnk("../../scripts/benchmark.sh")[The benchmark script] writes a fresh evidence directory and refuses to reuse one. #lnk("../BENCHMARKS.md")[The benchmark document] retains the method, environment and dated observations.],
      )
    ]
  ])
  #pagebreak(weak: true)
]
