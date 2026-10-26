#import "../.render/designlib.typ": *
#let title = [Source generation]
#let accent = "violet"
#let body = [
  #section(title: "Foundation", lead: [Development tools return reviewable Gleam source for native types and codecs. The application build owns writing, formatting and compiling that source.], body: [
    #goal(title: "Generate reviewable native source")[A caller-authored typed definition or an admitted closed-object schema produces Gleam source that compiles to a codec with the behavior of the public combinators.]
    #invariant(title: "Generation never discards a supported constraint", enforcement: "partial")[Descriptions, exact bounds, requiredness, and wire names survive lowering. A shape the generator cannot lower returns a located failure instead of a weaker codec.]
    #invariant(title: "A failed generation returns no module", enforcement: "mechanism")[Invalid names, name collisions, and unsupported shapes return a typed failure. No partial source is returned, and generation performs no file effect.]
    #principle(title: "Keep generation out of application runtime")[Generated applications depend on the contracts runtime and their compiled source. The build compiler, not schema text at runtime, supplies each native type.]
    #points(
      [The generators share the json_blueprint package and release version; their placement is recorded in #adr(8). Contracts supplies the codec, schema, and runtime helpers that generated source uses, as declared in #lnk("../../CONTEXT-MAP.md")[the context map].],
    )
  ])

  #pagebreak(weak: true)
  #pending-ledger(
    pending-entry(title: "Broader runtime-schema generation is not designed", kind: "build", since: "2026-10-08", adr: [#adr(8)])[Selected naming overrides, shared named definitions, string and numeric enums, tagged and broader unions, aliases, recursive forms, and a general command-line workflow are outside generation. The build compiler creates each native type, so parsing a schema at application runtime cannot supply a typed codec. Formatter integration and upgrade fixtures remain tooling work beyond the focused consumer integration tests; committed-output freshness is reviewed manually.],
  )

  #pagebreak(weak: true)
  #section(title: "System at a glance", lead: [Three generators lower definitions and schemas to source; each returns a module and starts no process.], body: [
    #diagram(altitude: "L3", viewpoint: "dataflow", title: "Generators and output", caption: [Generators run at build time. Generated source uses specialized typed functions or public codec combinators, with shared contracts-runtime admission and conversion helpers.], flow: "top-to-bottom", nodes: (
      (id: "typed", label: "Typed-definition generator", kind: "component", tint: "violet"),
      (id: "schema", label: "Schema-driven generator", kind: "component", tint: "violet"),
      (id: "materializer", label: "Schema materializer", kind: "component", tint: "violet"),
      (id: "output", label: "Generated module", kind: "value-object", tint: "violet"),
      (id: "runtime", label: "Contracts runtime", kind: "bounded-context", tint: "teal"),
    ), edges: (
      (from: "typed", to: "runtime", relation: "dependency", label: "codec check, internal helpers"),
      (from: "schema", to: "runtime", relation: "dependency", label: "schema model, codec names"),
      (from: "materializer", to: "runtime", relation: "dependency", label: "schema tree helpers"),
      (from: "typed", to: "output", relation: "dataflow", label: "returns source"),
      (from: "schema", to: "output", relation: "dataflow", label: "returns source"),
      (from: "materializer", to: "output", relation: "dataflow", label: "returns source"),
    ))
  ])

  #section(title: "Source generation", lead: [Development tools return reviewable source. Runtime document loading never constructs a new native type.], body: [
    #subsection(title: "Typed-definition generator")[
      #answers(title: "Codegen definition boundary", responsibility: [Lower a typed definition to a standalone Gleam module with matching runtime behavior.], interface: [json/blueprint/codegen: Definition, named_mapping, enum_variant, runtime, compile.], interactions: [The runtime codec is checked before lowering. Generated source uses runtime internal/generated helpers under the versioned compatibility contract.], invariants: [Names/references are explicit. Runtime conversion does not invoke generation.], failure: [CompileError preserves invalid names/references/imports, invalid definitions, unavailable schemas, unsupported constructors, and native-number restrictions.])
      #entity(id: "generation-definition", title: "Definition(a)", description: [Immutable source-lowering definition whose native type belongs to the compiled caller.], kind: "value-object", owner: "Source generation", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
        #attribute(name: "Runtime and source model", type: "Codec(a) × native type expression × lowering function", provenance: "derived")[Definition constructors compose a runtime codec and source instructions. Source names remain explicit input where functions cannot be inspected.]
        #relates(cardinality: "1 : 1")[Definition retains exactly one runtime codec. Its properties and mappings may retain multiple child definitions.]
      ]
      #md-table(3, (
        [Build value], [Owned data], [Invariant and failure],
        [Properties(r, a)], [Record builder, type expression, names, property lowering], [Duplicate names fail definition checking; object closes the accumulated fields],
        [Mapping(a, b)], [Two runtime functions and two source references], [Source forms validate; callback/reference behavioral equality remains caller-owned],
        [EnumVariant(a)], [Wire label, native value, source constructor reference], [Reference syntax checks before admission; enum definition checks label/value uniqueness],
        [GeneratedModule], [Relative path, content, optional codec fingerprint], [No file is written automatically; compile and materialization return distinct result records],
      ))
      #points(
        [#term("term-codegen-definition") carries a Codec(a), a native type expression, and lowering instructions. Properties combines typed required/optional fields for a closed object. Mapping joins runtime functions with explicit qualified references because Gleam cannot recover source names from closures.],
        [Supported definitions are string, int, number, bool, integer ranges, pair, list, nullable, finite string enum, required/optional properties, object, imap with named_mapping, and descriptions. A definition can exist at runtime while its native generated path is unsupported; compile refuses exact-number forms lacking supported native lowering with NativeNumberUnsupported.],
        [compile validates module path and accessor name, parses native type references, calls codec.check, lowers the definition, checks native support and import agreement, then returns a #term("term-generated-module"). The result contains relative .gleam path, content, and SHA-1 content fingerprint.],
        [Generated schema helpers trust generator-checked trees. Direct caller construction through internal tree helpers bypasses ordinary schema admission and owns the resulting invariants.],
        [Qualified callback/constructor names and type/import references are validated as source forms. Compilation checks referenced function types; same-typed callbacks paired with different source references remain a caller trust boundary. Parity tests must compare interpreted and generated behavior.],
        [A generated module exports Value encode/decode, strict text encode/decode, the explicitly distinct standard-native JSON decoder, a schema accessor, and a codec accessor. The codec accessor registers specialized text encoding and typed decoding of the shared strict parser's native tree. Strict admission retains duplicate-key rejection, Unicode validation, exact numeric evidence and the configurable byte bound before invoking typed callbacks. The explicit standard-native decoder uses gleam/json after a 1 MiB byte check and does not inherit strict duplicate or number guarantees. #adr(16)],
        [The typed generator emits specialized functions directly from its lowering model. It neither rewrites emitted source nor introduces another parser. Generated schema structure avoids rediscovering the definition; schema JSON is still rendered when requested. Codec accessors construct immutable wrappers without a global cache.],
        [Ordinary codec.encode_json and codec.decode_json use the registered fast paths. Enclosing an existing generated codec in an ordinary map or container preserves behavior and direct child decoding, but text encoding uses the ordinary Value path. Generate the complete definition to specialize its whole text encoder. A generated object codec can be a field or collection element, but cannot finish a record continuation: it has no record-builder capability. Extending a record requires an ordinary runtime record builder.],
        [Generated conversion follows runtime results, field paths and conversion callback order for supported definitions with faithful named mappings. Mappings must be pure: generated schema and known-field metadata do not replay runtime placeholder introspection, so introspection callback counts are not equivalent. Value decoding checks declared fields before unused or repeated members; strict text parsing rejects duplicates before typed callbacks. Placeholder mappings run on demand rather than during codec accessor construction. Explicit standard-native decoding remains a separate contract.],
        [Generation returns source only. The caller owns file writing, formatting, compiling, reviewing, committing generated output, and drift checks. Package internal/generated helper names/signatures consumed by checked-in output remain stable within a major version; internal marking alone does not eliminate that compatibility obligation.],
        [Sources: #lnk("../../../src/json/blueprint/codegen.gleam")[generator], #lnk("../../../src/json/blueprint/internal/generated.gleam")[runtime helper contract], #lnk("../../../test/compiled_codec_test.gleam")[compiled source fixtures], and #lnk("../../../README.md")[build workflow]. #adr(8) records ownership.],
      )
    ]
    #subsection(title: "Schema materialization")[
      #points(
        [The internal materializer exports functions that implement #term("term-schema-materialization"): they reconstruct checked schema structure without constructing codec callbacks. It validates module/accessor names, rejects duplicate accessor names, sorts exports by accessor name, and escapes labels as data.],
        [Materialized schema functions may allocate a schema tree on each call. They generate neither native record types nor native codecs, and they establish no constant-evaluation or constant-time lookup guarantee.],
        [Lowering emits supported tree constructors and preserves descriptions, child schemas, property requiredness, and variant payload presence. Unknown or unsupported structure returns a located MaterializationError rather than dropping constraints.],
        [Sources: #lnk("../../../src/json/blueprint/codegen/internal/schema_materialize.gleam")[materializer] and #lnk("../../../test/schema_materialization_test.gleam")[schema materialization evidence].],
      )
    ]
    #subsection(title: "Schema-driven native generator")[
      #answers(title: "Schema generation boundary", responsibility: [Generate native record types and a typed codec from an admitted closed-object schema.], interface: [json/blueprint/codegen/schema.compile(module_path: String, name: String, schema: codec.Schema) returns Result(codegen.GeneratedModule, schema.CompileError).], interactions: [The build compiler creates native types from returned source. Generated codec expressions use public codec combinators.], invariants: [No supported constraint is discarded. Native fields retain their original wire names through their codecs.], failure: [Typed generation failures distinguish invalid names, conflicting names, and unsupported shapes with logical schema paths. No partial module is returned.])
      #points(
        [The #term("term-schema-driven-generator") accepts only a closed-object root. The explicit name is a validated lowercase accessor stem: order selects public Order and `order_codec()`. The module path follows the existing generator's source-path validation.],
        [Generated root and nested record types are public so consumers can construct native values. Only the root codec accessor is public; nested codec functions are private. Generated applications depend on JSON Blueprint and their compiled source; generation runs only when explicitly invoked.],
        [The generated module uses ordinary public codec constructors and record continuations. It does not emit a second Value validator or route through the typed-definition generator's specialized emitter. Caller mappings from generated records to business types remain application-owned.],
        [Calling the root accessor constructs its codec and prebinds child codec definitions before field continuations. Exact bounds are reconstructed during that construction; retaining the returned codec reuses those child definitions and bounds across conversions. Each accessor call constructs a new codec without a global cache.],
      )
      #md-table(3, (
        [Admitted schema shape], [Native type], [Preserved behavior],
        [Closed object], [Public named record], [Requiredness, original wire names, and closed-object decoding],
        [String / boolean], [String / Bool], [Primitive conversion],
        [Integer / inclusive integer range], [Int], [Target-specific native projection and inclusive bounds],
        [Number / inclusive number range], [Number], [Exact mathematical values and exact inclusive bounds],
        [List / pair], [List(a) / `#(a, b)`], [Item conversion and exact pair length],
        [Nullable], [Option(a)], [Existing nullable codec semantics],
        [Optional object property], [Option(a)], [None omits the property; Some encodes through its child codec],
      ))
      #points(
        [Optional nullable properties use Option(Option(a)). None means missing, Some(None) means explicit null, and Some(Some(value)) means present non-null data. Repeated nullable wrappers retain the existing codec's encoding rules.],
        [Schema descriptions and exact numeric bounds survive generation. Object properties are sorted by Unicode codepoint order of their original wire names before traversal and source emission, so input property order does not select names, layout, or the fingerprint.],
        [Native Int bounds retain the ordinary codec's target-specific limits. A bound admitted on Erlang may exceed JavaScript's safe-integer range; generated source must be checked on each intended target, where warnings-as-errors compilation and codec definition validation refuse unsafe integer bounds. Exact Number bounds remain independent of native Int and Float representation.],
        [String enums, tagged unions, AnySchema, future OtherSchema, and every unsupported root produce located generation failures. Admitting a schema for runtime validation does not imply admitting it for native generation.],
      )
      #subsection(title: "Generated names and failures")[
        #points(
          [Native field names retain lowercase ASCII letters and digits. Each uppercase ASCII letter becomes lowercase and starts an underscore-separated word; runs of non-ASCII or nonalphanumeric delimiters collapse to one underscore. Leading and trailing underscores are removed, digit-leading results receive `field_`, Gleam keywords receive a trailing underscore, and an empty result is rejected.],
          [A nested object stem joins its parent stem and normalized field name with an underscore. List children append `_item`; pair children append `_first` or `_second`; nullable wrappers keep the stem. Pascal-case conversion supplies record type and constructor names.],
          [Native field collisions are rejected within one record. Generated type collisions are rejected across the module, including conflicts with builtin or used imported type names. Failures retain both origins as schema locations or reserved-name markers; the generator never assigns ordinal suffixes to hide a collision.],
          [CompileError distinguishes invalid module paths, invalid root or field names, name collisions, and unsupported shapes. Locations use codec.PathSegment in the logical canonical rendered schema, including properties and collection positions; they are not byte offsets in the original document.],
          [Module source and its content fingerprint are returned as a #term("term-generated-module"). The caller owns writing, formatting, compiling, reviewing, and drift checking the source. Generation starts no process, stores no global state, and adds no runtime cache.],
        )
      ]
      #behavior(title: "A supported schema supplies compilable native records", level: "boundary", area: "Schema generation")[
        #given[An admitted closed-object schema uses supported child forms and nonconflicting names.]
        #given[Its integer bounds fit the intended target's native Int.]
        #when[The caller generates the supported schema module.]
        #then[The returned source compiles into public root and nested native records with a public root codec accessor.]
        #then[The codec preserves the schema's supported constraints, descriptions, and wire names.]
      ]
      #behavior(title: "Native outbound values retain numeric constraints", level: "boundary", area: "Schema generation")[
        #given[A generated native record contains a value outside a declared inclusive numeric bound.]
        #when[The application encodes the record through its generated codec.]
        #then[Encoding fails with the ordinary codec's located bound failure.]
      ]
      #behavior(title: "Optional nullable fields preserve three states", level: "boundary", area: "Schema generation")[
        #given[A generated record has an optional nullable property.]
        #when[The application converts a value through the generated codec.]
        #then[Missing, explicit null, and present non-null values remain distinct native and wire states.]
      ]
      #behavior(title: "Unrepresentable source fails before a module is returned", level: "boundary", area: "Schema generation")[
        #given[A schema has an unsupported shape or an invalid or conflicting generated name.]
        #when[The caller generates its module.]
        #then[Generation returns the typed failure and its applicable logical schema locations.]
        #then[No partial source module is returned and no constraint is silently removed.]
      ]
      #behavior(title: "Equivalent property order regenerates identical source", level: "boundary", area: "Schema generation")[
        #given[Two supported schemas differ only in object property order and use the same selected module path and root name.]
        #when[The caller generates both modules.]
        #then[Their source and content fingerprints are identical.]
      ]
      #points(
        [The #lnk("../../../examples/codegen/README.md")[separate consumer] loads an order schema, compiles generated records, adds an application-owned envelope and dispatch policy, and tests failure recovery. Its separate generation task owns file effects and works before the generated application module exists. The #lnk("../../../scripts/check-schema-consumer.sh")[consumer check] regenerates source into a disposable consumer, runs the consumer tests on both targets, and compiles a production copy without development dependencies.],
        [The consumer's two-target corpus uses portable native bounds. Acceptance comparison distinguishes exact wire acceptance from native Int projection failures; it does not claim full-profile parity or general JSON Schema conformance. CPU, construction, generation, and allocation measurements are separate evidence and impose no timing assertion on semantic tests. #adr(8) records the implementation choice.],
      )
    ]
    #subsection(title: "Generated parity and verification")[
      #behavior(title: "A specialized codec preserves runtime conversion", level: "boundary", area: "Typed generation")[
        #given[A supported typed definition has pure named callbacks that agree with their runtime functions.]
        #when[An application replaces its runtime codec with the compiled generated codec for value, text or schema operations.]
        #then[Value and strict JSON conversion preserve accepted values, failures and paths, optionality, and conversion callback order.]
        #then[Strict JSON admission rejects duplicate names, malformed JSON and invalid Unicode before typed callbacks under the same byte policy; numeric projection uses the same exact evidence.]
        #then[Schema queries preserve the definition's supported structure and constraints.]
      ]
      #points(
        [Generated fixture tests format and compare regenerated source, compile retained modules, compare schema bytes and behavior, and run both targets. Named mapping references need parity evidence beyond source type checking.],
        [A separate consumer regenerates its module, compares it with committed output, runs its tests on both targets, and builds an isolated production copy without development dependencies. The same consumer owns the acceptance corpus and the comparison harness for cost measurements.],
        [Benchmarks of generation, codec construction, and conversion are observations rather than semantic limits. #adr(10) records the method and the accepted findings.],
      )
    ]
  ])
  #pagebreak(weak: true)
]
