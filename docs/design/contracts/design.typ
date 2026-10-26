#import "../.render/designlib.typ": *
#let title = [JSON contracts]
#let accent = "teal"
#let body = [
  #section(title: "Foundation", lead: [One definition supplies typed conversion and an inspectable JSON contract.], body: [
    #goal(title: "Describe schema-aware data once")[Applications retain one #term("term-codec") for JSON conversion, schema publication, and schema-aware composition. Runtime schema documents produce contracts for wire validation.]
    #goal(title: "Reject hostile input within explicit bounds")[Strict text admission retains exact numbers and duplicate-key evidence. A byte limit bounds admission; consumers own depth, value-count and numeric policies.]
    #goal(title: "Keep the published 1.x API available")[The frozen 1.x API remains available for its established wire formats and recursive types.]
    #invariant(title: "Number comparison preserves mathematical value", enforcement: "mechanism")[#term("term-exact-number") comparison and integrality never pass through Float. Native construction and projection check target representation limits.]
    #invariant(title: "A witness retains the value that was validated", enforcement: "mechanism")[A #term("term-validated-value") retains an immutable value and the accepting normalized schema. A replacement value requires another validation.]
    #invariant(title: "Unknown schema never becomes inferred schema", enforcement: "mechanism")[A custom codec without a schema reports UnknownSchema. Every enclosing schema query propagates that absence.]
    #invariant(title: "Record decoding rejects extra and repeated fields", enforcement: "mechanism")[Closed record decoding rejects unknown members and repeated members. Strict text admission rejects repeated keys before native decoding.]
    #principle(title: "Keep wire acceptance separate from native projection")[A schema may accept an exact value that a requested native type cannot represent. Callers distinguish schema rejection, parse rejection, and native conversion failure.]
    #principle(title: "Keep callback ownership explicit")[Caller mappings own their laws and application checks. A retained schema does not certify a callback's inverse, purity, or encoding behavior.]
    #points(
      [Ownership and finite support are recorded in #adr(1). Number policy is recorded in #adr(2). Byte-only native admission supersedes #adr(3) in #adr(14).],
    )
  ])

  #pagebreak(weak: true)
  #pending-ledger(
    pending-entry(title: "Broader schema families need concrete contracts", kind: "build", since: "2026-09-20", adr: [#adr(1)])[String constraints, broader numeric and collection constraints, arbitrary alternatives, numeric enums, aliases, and recursive references are outside the profile. Their limits, annotation policies, and validation rules are undefined; see Unsupported schema families.],
    pending-entry(title: "Consumer evolution policies need explicit contracts", kind: "ruling", since: "2026-10-25")[Prioritize optional unknown-field handling, dictionaries, basic string/list lengths, one-sided numeric bounds, configurable union envelopes and local recursive references. Before implementation, define accepted input versus emitted output, retention of extra fields, schema projection and reference identity. The current strict defaults and frozen legacy access remain in force; formal deprecation requires a supported migration for recursive data and established wire formats.],
    pending-entry(title: "Retain complete compatibility verification", kind: "verify", since: "2026-10-02", adr: [#adr(7)])[Published source, legacy wire, recursive references, error paths, numeric boundaries, and deliberate acceptance corrections need separate fixtures. Existing examples and frozen comparators do not prove complete 1.x compatibility.],
    pending-entry(title: "Keep numerical oracle scope separate from projection", kind: "verify", since: "2026-09-20", adr: [#adr(2)])[The finite schema manifest compares Boolean acceptance for its selected cases. Broader numerical evidence must compare exact schema acceptance separately from native overflow, safe-integer refusal, and intentional Float rounding.],
    pending-entry(title: "Check the legacy and error-path claims against code", kind: "verify", since: "2026-10-17")[The 1 MiB decode precheck, its configurable bound and the object-index cutoff match the source. The remaining provisions carried over from the retired 1.x guides are not yet checked against code: the Draft-07 label statements, error-path rendering, number-projection limits and the legacy wire envelopes. The migration examples and the schema oracle exercise part of them.],
  )

  #pagebreak(weak: true)
  #section(title: "System at a glance", lead: [One context owns values, schemas, typed codecs, contracts and legacy compatibility.], body: [
    #diagram(altitude: "L3", viewpoint: "runtime", title: "Runtime components", caption: [Arrows declare call and dependency direction. The legacy surface shares only a byte-admission helper with the strict parser.], flow: "top-to-bottom", nodes: (
      (id: "codec", label: "Typed codecs", kind: "component", tint: "teal"),
      (id: "contract", label: "Runtime contracts", kind: "component", tint: "teal"),
      (id: "value", label: "Value parser / renderer", kind: "component", tint: "teal"),
      (id: "number", label: "Exact number kernel", kind: "component", tint: "teal"),
      (id: "legacy", label: "Legacy decoder / schema", kind: "component", tint: "teal"),
    ), edges: (
      (from: "codec", to: "value", relation: "call", label: "strict text and bridges"),
      (from: "contract", to: "codec", relation: "dependency", label: "schema / error vocabulary"),
      (from: "contract", to: "value", relation: "call", label: "schema text admission"),
      (from: "value", to: "number", relation: "call", label: "exact tokens / projection"),
      (from: "codec", to: "number", relation: "call", label: "bounds / native conversion"),
      (from: "legacy", to: "value", relation: "dependency", label: "shared byte-admission helper only"),
    ))
    #points(
      [Work is bounded only at the declared admission surfaces. A manually constructed Value, a caller callback, schema discovery, rendering, and validation have no additional timer or allocation quota.],
    )
  ])


  #section(title: "Whole model", lead: [All package-owned domain values are immutable. Schema identity is structural; native types remain caller-owned.], body: [
    #diagram(altitude: "L3", viewpoint: "domain-model", title: "Values and acceptance evidence", caption: [The diagram shows ownership and data relationships. Validation creates another immutable value; it does not mutate the input or register a global identity.], flow: "top-to-bottom", nodes: (
      (id: "number", label: "Number", kind: "value-object", tint: "teal"),
      (id: "value", label: "Value", kind: "value-object", tint: "teal"),
      (id: "codec", label: "Codec(a)", kind: "value-object", tint: "teal"),
      (id: "schema", label: "Schema", kind: "value-object", tint: "teal"),
      (id: "contract", label: "Contract", kind: "value-object", tint: "teal"),
      (id: "witness", label: "ValidatedValue", kind: "value-object", tint: "teal"),
    ), edges: (
      (from: "value", to: "number", relation: "dependency", label: "0..n numeric nodes"),
      (from: "codec", to: "value", relation: "dataflow", label: "encode / decode"),
      (from: "codec", to: "schema", relation: "dataflow", label: "0..1 available schema"),
      (from: "contract", to: "schema", relation: "dependency", label: "1 normalized schema"),
      (from: "witness", to: "value", relation: "dependency", label: "1 immutable value"),
      (from: "witness", to: "schema", relation: "dependency", label: "1 accepting schema"),
    ))
    #entity(id: "number", title: "Number", description: [Target-independent mathematical numeric value.], kind: "value-object", owner: "Wire values", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
      #attribute(name: "Normalized value", type: "SmallInteger | Decimal", provenance: "derived")[Small integers have at most 15 decimal digits. Other values carry sign, nonzero coefficient digits without leading or trailing zeros, and a decimal exponent; zero has one positive representation.]
      #relates(cardinality: "1 : 0..n")[Number may appear in Values and exact numeric schema bounds.]
    ]
    #entity(id: "value", title: "Value", description: [Ordered JSON tree that can retain duplicate-key evidence.], kind: "value-object", owner: "Wire values", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
      #attribute(name: "Kind and content", type: "Null | Bool | String | Number | Array | Object", provenance: "derived")[Parsing derives the content from admitted text. Public constructors also allow callers to supply content; those constructed values have no parse-admission proof.]
      #relates(cardinality: "1 : 0..n")[Arrays own ordered Values. Objects own ordered name/Value pairs; the raw Object constructor permits repeated names.]
    ]
    #entity(id: "schema", title: "Schema", description: [Checked finite structure with optional descriptions.], kind: "value-object", owner: "Typed codecs", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
      #attribute(name: "Checked structure", type: "Opaque Tree", provenance: "derived")[Codec discovery or document loading derives structure after checking definition invariants. The public projection never exposes a constructor for unchecked structure.]
      #relates(cardinality: "1 : 0..n")[Property and variant records retain opaque child Schemas with exact name/requiredness and tag/payload associations.]
    ]
    #entity(id: "codec", title: "Codec(a)", description: [Compiled native conversion and discoverable schema capability.], kind: "value-object", owner: "Typed codecs", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
      #attribute(name: "Native directions", type: "a -> Result(Value, EncodeError); Value -> Result(a, DecodeError)", provenance: "authored")[Constructors compose directions; custom callbacks are supplied by the caller.]
      #attribute(name: "Definition and placeholder", type: "Deferred schema result; fn() -> a", provenance: "derived")[Definition discovery is computed on demand. This is not a promised cached or constant-time schema lookup.]
      #relates(cardinality: "1 : 0..1")[A codec supplies one Schema when known. Its type parameter a is supplied by the native program, never by runtime schema text.]
    ]
    #entity(id: "contract", title: "Contract", description: [Normalized schema retained independently of native callbacks.], kind: "value-object", owner: "Runtime contracts", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
      #attribute(name: "Normalized acceptance", type: "Finite Tree", provenance: "derived")[Normalization sorts properties, enum labels, and variants without changing associations. Equality for matching strips descriptions.]
      #relates(cardinality: "1 : 0..n")[Validation may produce multiple witnesses. A contract retains no callback, process identity, or native type.]
    ]
    #entity(id: "witness", title: "ValidatedValue", description: [Immutable acceptance evidence for one retained value.], kind: "value-object", owner: "Runtime contracts", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
      #attribute(name: "Value and accepting schema", type: "Value × normalized Tree", provenance: "derived")[Only successful validation constructs the public witness. Matching a codec checks normalized schema structure before its native decoder runs.]
      #relates(cardinality: "1 : 1")[The witness retains exactly one value and one accepting schema; it cannot bless a modified value.]
    ]
    #points(
      [Value objects have no persistent identifiers, mutable state fields, commands that change them, or emitted domain events. There is no vacant or revoked state to model: replacement discards the previous value and requires fresh evidence.],
      [Sum types model Value, SchemaView, typed failures, and union construction. Products model errors with paths, properties, variants, parse locations, and generated source results. Numeric bounds and enum membership are refinements on accepted values.],
      [Limits are immutable caller-authored settings. The byte setter retains its supplied value; a nonpositive byte limit rejects every input.],
    )
  ])

  #section(title: "Wire values", lead: [This unit owns exact numbers, strict document admission, rendering, and explicit standard-JSON conversion.], body: [
    #answers(title: "Wire value boundary", responsibility: [Preserve exact JSON meaning while admitting complete documents within explicit resource limits.], interface: [number construction/projection; value.object, parse, parse_bits, to_string, to_json, decoder.], interactions: [Codecs and schema loaders use strict admission. Standard-JSON bridges accept another parser's precision and duplicate-key policy.], invariants: [No NaN or infinity is a Number. Checked object construction rejects repeated keys without converting the object to a map.], failure: [ParseError retains location and reason; numeric construction and projection have separate typed outcomes.])
    #subsection(title: "Exact numbers")[
      #points(
        [Number parsing accepts the JSON numeric grammar: optional minus, integer digits with no leading zero except zero itself, optional nonempty fraction, and optional signed nonempty exponent. Whitespace and a leading plus are invalid.],
        [Normalization removes coefficient zeros and adjusts the decimal exponent without expanding the value. Comparison first distinguishes signs, then decimal magnitude and significant digits. Mathematical integrality follows normalized coefficient/exponent, so 1.0e2 is an integer.],
      )
      #md-table(3, (
        [Operation], [Meaning], [Failure or target rule],
        [parse(token, limits)], [Exact normalized decimal], [InvalidSyntax, TokenTooLong, TooManySignificandDigits, ExponentOutOfRange],
        [from_int / to_int], [Checked exact native integer conversion], [Erlang bignums; JavaScript safe integers only; projection has an output-digit bound],
        [from_float / to_float], [Shortest roundtrip decimal / nearest binary64], [Nonfinite input or overflow rejects; tiny nonzero numbers may round to zero],
        [from_float_exact / to_float_exact], [Exact binary rational / exact mathematical binary64 equality], [Overflow, underflow, inexactness, or invalid candidate remain distinct],
      ))
      #points(
        [Default Number limits are 1,024 token bytes, 800 significant digits as written, and normalized exponent magnitude 1,200. They admit finite binary64 decimal expansions, including subnormals. On JavaScript, written and normalized exponents and comparison magnitude must also fit exact native integer representation; an unrepresentable value is refused even when caller-selected limits allow it. Token and digit limits below one reject every token; a negative exponent bound rejects nonzero values.],
        [Native Int construction cannot recover precision already lost before the JavaScript boundary. The unsafe value is rejected even when a host has rounded it to another integer.],
      )
      #behavior(title: "Exact decimal survives comparison", level: "boundary", area: "Exact numbers")[
        #given[The numbers 1.2300e2 and 123 were admitted within number limits.]
        #when[The application compares them.]
        #then[The result is equality without binary rounding.]
      ]
      #points(
        [The decimal 0.1 can project through the rounded conversion. Exact projection rejects it as FloatInexact; 0.5 projects exactly. Sources: #lnk("../../../src/json/blueprint/number.gleam")[number implementation] and #lnk("../../../test/number_test.gleam")[target and numeric cases].],
      )
    ]
    #subsection(title: "Strict document admission")[
      #points(
        [Text parsing checks UTF-8 byte size before allocating the document tree. On JavaScript, a raw unpaired UTF-16 surrogate then fails with InvalidUnicodeScalar before UTF-8 conversion can replace it. Its location is the end of the valid prefix, measured in UTF-8 bytes and grapheme columns. Byte parsing additionally reports the first invalid UTF-8 byte. A valid document has exactly one root value followed only by JSON whitespace; trailing content rejects.],
        [Erlang uses OTP JSON hooks to reject duplicate names and retain exact integer values and decimal tokens. Built-in codecs decode the native tree directly; custom Value callbacks convert only their subtree. JavaScript retains the portable exact parser.],
      )
      #md-table(3, (
        [Bound], [Default], [Change],
        [Input bytes], [1,048,576], [with_max_bytes],
      ))
      #points(
        [There is no global depth, value-count or numeric-token admission bound, streaming admission or request-wide time budget. The caller has already allocated input text; byte admission is not a heap quota. Consumers own structural policy.],
        [String admission validates escapes and surrogate pairing. Literal control characters, malformed escapes, and unterminated strings reject. Object duplicate detection compares decoded names, so escaped equivalent names collide.],
        [Erlang object members follow native map order. JavaScript retains source order. Arrays retain input order. Value conversion copies strings so small retained values do not retain the complete source binary.],
        [JavaScript ParseError locations retain zero-based byte offsets and one-based line/column. Erlang native syntax and duplicate errors have an unavailable location, represented by zeroes; their description does not invent a source position. Public parse errors retain no input text. Syntax validation completes before typed callbacks run.],
      )
      #behavior(title: "The parser refuses repeated names", level: "boundary", area: "Strict admission")[
        #given[A document repeats the same decoded member name in one object.]
        #when[The application parses the document.]
        #then[Parsing fails with DuplicateObjectKey and returns no parsed tree.]
      ]
      #behavior(title: "Host text cannot silently replace malformed Unicode", level: "boundary", area: "Strict admission")[
        #given[JavaScript input text contains a raw unpaired surrogate and is within its byte bound.]
        #when[The application parses the text through the strict entry point.]
        #then[Parsing fails with InvalidUnicodeScalar at the first unpaired surrogate without retaining source text in the error.]
      ]
      #points(
        [#adr(14) records byte-only native admission and supersedes the independent limits in #adr(3). Source: #lnk("../../../src/json/blueprint/value.gleam")[value parser]. #lnk("../../../test/bounded_parsing_test.gleam")[admission tests] and #lnk("../../../test/value_parse_test.gleam")[grammar cases] cover the boundary. Benchmark observations are not hard heap quotas.],
      )
    ]
    #subsection(title: "Rendering and standard JSON bridges")[
      #points(
        [to_string emits compact JSON, escapes strings, and preserves ordered members. It does not normalize object order or reject duplicate members supplied through raw Object construction. Rendering has no independent byte bound.],
        [value.to_json first tries an exact native integer within 400 output digits, then a finite Float whose shortest roundtrip decimal compares equal to the Number. It returns the offending Number if no exact rendered standard-JSON form exists. This bridge criterion differs from exact binary64 equality: decimal 0.1 has an exact printed JSON form despite an inexact binary representation.],
        [codec.to_json retains the offending numeric node's Field/Index path as UnrepresentableNumber. Applications propagate that Result before entering APIs that require an infallible JSON encoder; replacing failure with null changes application data.],
        [value.decoder and codec.decoder consume a native parser's output. That parser owns size, duplicate names, member order, and already-rounded numeric precision. These bridges cannot restore discarded evidence or enforce strict text limits retroactively.],
        [Sources: #lnk("../../../src/json/blueprint/value.gleam")[rendering and bridge implementation] and #lnk("../../../test/value_test.gleam")[bridge cases].],
      )
    ]
  ])

  #section(title: "Typed codecs", lead: [This unit composes bidirectional conversion for caller-owned native types and discovers the supported schema.], body: [
    #answers(title: "Codec boundary", responsibility: [Encode and decode native a using one retained definition and known wire shape.], interface: [Primitive codecs, collection codecs, record and union builders, mapping, custom, encode/decode, schema, check, placeholder.], interactions: [On Erlang, strict text admission builds a native tree for direct built-in decoding; custom callbacks convert their subtree to Value. JavaScript decodes through Value. Schema publication exposes an opaque schema for consumer admission.], invariants: [Built-in constructors preserve their declared wire shape. Unknown child schema propagates through every enclosing schema query.], failure: [Value failures return path and Reason. Source definition mistakes panic at first affected use; check returns DefinitionError instead.])
    #subsection(title: "Constructor acceptance")[
      #md-table(3, (
        [Constructor], [Native and JSON shape], [Acceptance and encoding rule],
        [string / bool], [String / Bool], [Exact JSON type; placeholder empty string / false],
        [int], [Native Int / mathematical integer], [Both directions require at most 24 digits and target safety; a longer encoded integer returns ExpectedInt, an unsafe JavaScript integer returns UnsafeInteger],
        [float], [Float / number], [Decode nearest binary64, refuse overflow; encode shortest roundtrip decimal],
        [number], [Number / number], [Exact passthrough without native projection],
        [integer_between], [Int / bounded mathematical integer], [Inclusive safe-native bounds; projection digits derive from bounds],
        [number_between], [Number / bounded number], [Inclusive exact comparisons],
        [string_enum], [Caller value / bare string label], [Nonempty unique labels and unique native values; exact case-sensitive labels],
        [pair], [`#(a, b)` / two-element array], [Exact length; failures retain index 0 or 1],
        [list], [List(a) / array], [Decode and encode each item with its zero-based index],
        [nullable], [Option(a) / null or inner], [None is null; Some cannot encode through inner as null],
        [value], [Value / any], [Identity conversion with AnySchema; text admission still applies],
        [success], [r / empty object], [Decode the retained r from a closed empty object; encoder ignores input],
      ))
      #points(
        [A codec's accepted native domain can be narrower than its schema. Native Int digit limits and Float overflow are projections, not mathematical schema constraints. try_map may impose application checks that its preserved schema cannot express.],
        [For caller-authored mappings, a successful encode/decode roundtrip is a caller law. The type system proves neither inverse mappings nor equality to a schema language. A constant success codec has the retained constant as its valid native domain.],
        [DefinitionError distinguishes duplicate names/tags, empty union/enum, duplicate enum native values, reversed bounds, unsafe JavaScript integer bounds, and a field continuation that does not finish a record. Diagnostics name definition data rather than untrusted input.],
      )
      #behavior(title: "A nullable inner null cannot erase Some", level: "boundary", area: "Constructor acceptance")[
        #given[A native Some value has an inner encoder that produces null.]
        #when[The application encodes it through nullable.]
        #then[Encoding returns NullInsideNullable instead of losing its native distinction.]
      ]
      #behavior(title: "Integer encoding preserves its decoding domain", level: "boundary", area: "Constructor acceptance")[
        #given[A native integer exceeds the plain integer codec's digit domain.]
        #when[The application encodes it through that codec.]
        #then[Encoding refuses it rather than producing a value that the same codec cannot decode.]
        #then[Explicit integer ranges retain their separate bound-derived digit domain.]
      ]
      #points(
        [Sources: #lnk("../../../src/json/blueprint/codec.gleam")[constructors], #lnk("../../../test/codec_test.gleam")[codec cases], and #lnk("../../../test/api_control_test.gleam")[public failure handling].],
      )
    ]
    #subsection(title: "Record construction and dependent fields")[
      #points(
        [The #term("term-record-builder") binds each required field's value or each optional field's Option. success ends the continuation with the caller's record value. Getters are passed last with get:, so the continuation fixes the native record type before record access is checked.],
        [Encoding reads each getter in declaration order, encodes that field, then builds its continuation using the actual native field value. Decoding finds and decodes each named member, then builds the continuation using the decoded value. This permits a later field's application check to depend on earlier fields.],
        [Schema discovery follows continuations using each codec's #term("term-placeholder") and None for optional fields. Names and schema constraints must be independent of those placeholder values; a dynamic application check may differ, but the declared JSON shape cannot.],
        [The source computes continuation properties on demand. Neither schema discovery nor arbitrary-width record processing promises constant time or linear time for all public definitions. Caller callbacks must remain deterministic and cheap where they are used to describe a schema.],
        [Optional fields omit None and decode absence as None. Required fields reject absence. Explicit null is rejected by a nonnullable inner codec; nesting optional_field with nullable yields None, Some(None), and Some(Some(x)) for absence, null, and a value.],
        [Record decoding visits declared fields before it checks unused members. A missing or invalid declared field can therefore precede an extra/repeated member failure. Runtime contract validation checks all member names before property values; the two first-error orders need not coincide.],
      )
      #behavior(title: "An optional field preserves present null", level: "boundary", area: "Record construction")[
        #given[An optional field contains a nullable string codec.]
        #when[The application decodes an explicitly null field.]
        #then[The result for that field is Some(None).]
        #then[Re-encoding includes the field with null.]
      ]
      #points(
        [A total mapped record has no record-builder continuation capability. A field continuation must remain a field/success record codec; terminating it in another shape is NotARecord.],
        [An Order total that differs from earlier decoded item quantities can return Custom at Field("total") when the check belongs inside that field's codec. Mapping the whole record reports at the record root. #adr(4) records the builder and definition-error policy.],
      )
    ]
    #subsection(title: "Tagged union construction")[
      #points(
        [union joins variant and unit_variant continuations with match. Each payload variant supplies a typed encoder to the final exhaustive native case; unit variants supply a retained tagged value. Duplicate tags and an empty union are definition errors.],
        [The #term("term-tagged-union") envelope has tag and value for payload variants, and tag alone for unit variants. All other fields reject. A payload variant requires value; a unit variant rejects even an explicitly null value.],
        [Decoding checks repeated and unknown member names before selecting tag. Missing tag, nonstring tag, unknown tag, missing payload, and invalid payload return distinct reasons at tag or value paths. Nested unions retain nested envelopes rather than implicitly flattening variants.],
      )
      #behavior(title: "A unit variant rejects a payload", level: "boundary", area: "Tagged unions")[
        #given[The selected variant declares no payload.]
        #when[The application decodes an object containing value.]
        #then[Decoding returns UnknownField at Field("value").]
      ]
      #points(
        [Encoding trusts match to return the encoder for the selected native case. Reusing a Tagged value from another union is not dynamically certified against a registry; the author owns the union mapping laws. Tests exercise N-ary variants and unit shape in #lnk("../../../test/api_control_test.gleam")[public API cases].],
      )
    ]
    #subsection(title: "Mappings and custom conversion")[
      #points(
        [map takes total functions in both directions and derives its placeholder from the inner codec. try_map takes fallible functions plus an explicit placeholder; a conversion failure becomes Custom at the current codec path. Both preserve the inner schema without claiming that business checks are schema-expressible.],
        [custom accepts functions over Value, an Option(Schema), and a placeholder. None reports UnknownSchema; Some retains a checked schema but does not independently validate every callback result. Captured state and side effects remain callback-owner responsibility.],
        [placeholder returns description data for composing wrappers. It must never be encoded as fallback application data. A callback invoked during description may encounter this value even when application decoding never accepts it.],
      )
      #behavior(title: "Unknown custom schema propagates", level: "boundary", area: "Custom conversion")[
        #given[A custom child codec supplies no schema.]
        #when[The application requests its enclosing record's schema.]
        #then[The result is UnknownSchema.]
        #then[The package does not infer an accepting document from callbacks.]
      ]
    ]
    #subsection(title: "Paths and safe diagnostics")[
      #points(
        [EncodeError and DecodeError each carry a root-to-leaf List(PathSegment) and structured Reason. Field(name) and Index(index) locate data. Empty paths identify the root; parse failures become InvalidJson at the root with their own byte location.],
        [Built-in rendered value reasons omit input values and unknown names from diagnostics. The typed path can still contain a name from the input. Custom messages render verbatim; the caller owns redaction and user-facing safety.],
        [Reason and ParseReason may gain minor-release alternatives. Callers use a fallback branch where exhaustiveness across upgrades matters. Schema errors, document errors, definition errors, parse errors, value errors, and number projections remain separate outcome families.],
      )
    ]
  ])

  #section(title: "Runtime contracts", lead: [This unit loads the finite schema profile, validates immutable values, and checks structural agreement before native decoding.], body: [
    #answers(title: "Runtime contract boundary", responsibility: [Interpret an explicit supported schema and preserve acceptance evidence.], interface: [from_codec, total from_schema, parse, load, schema, same_schema, validate, value, decode, value_codec.], interactions: [The strict parser owns text limits. The schema model owns checked structure. Native decoding retains the caller's codec.], invariants: [Unsupported constraints never disappear. Matching preserves requiredness, tuple order, bounds, and variant associations.], failure: [LoadError separates JSON admission from document rejection. ValidationError carries first failure path and Reason. Native mismatch is ContractMismatch.])
    #subsection(title: "Schema discovery and public projection")[
      #points(
        [codec.schema returns an opaque #term("term-schema") or UnknownSchema after definition discovery. schema_value renders the schema node; schema_document adds the Draft 2020-12 declaration; schema_json renders the complete document as text.],
        [#term("term-schema-view") has fixed alternatives throughout 2.x: StringSchema, StringEnumSchema, IntSchema, IntegerRangeSchema, NumberSchema, NumberRangeSchema, BoolSchema, PairSchema, ListSchema, NullableSchema, ObjectSchema, UnionSchema, AnySchema, and OtherSchema.],
        [Descriptions are optional annotations read by codec.description; view looks through them. The latest description at one node replaces the earlier one. Child descriptions remain local to their nodes.],
        [A future minor-release kind reaches OtherSchema with its rendered schema object. A dedicated projection alternative requires a major release. PropertySchema and VariantSchema may gain fields; consumers read them by label. No current finite kind produces OtherSchema. #adr(5) records the evolution contract.],
      )
    ]
    #subsection(title: "Document loading profile")[
      #points(
        [load requires an object root with exactly the supported Draft 2020-12 URI in `$schema`. It removes that declaration, interprets the remaining supported shape, checks definition invariants, then normalizes. Nested `$schema` declarations reject as NestedDialect.],
      )
      #md-table(3, (
        [Shape], [Accepted members], [Restriction],
        [Any], [Empty object, optionally description; nested true], [Root still requires an object and `$schema`; false is not accepted],
        [String / boolean], [type; strings optionally enum], [Enum is nonempty unique string labels],
        [Integer / number], [type; optional minimum and maximum], [Both bounds or neither; inclusive and ordered; integer bounds project to safe native Int],
        [Closed object], [type, properties, required, additionalProperties], [All three structure members explicit; additionalProperties must be false],
        [Homogeneous array], [type, items], [Exactly one item schema],
        [Pair], [type, prefixItems, minItems, maxItems], [Two prefix schemas and both lengths equal two; no items member],
        [Nullable], [anyOf], [Exactly one plain null schema plus one supported object schema],
        [Tagged union], [type object, oneOf], [Nonempty closed variants; tag const string; exactly declared payload presence],
      ))
      #points(
        [description is permitted as an annotation on interpreted object schemas. Other keywords reject at their member path. The loader does not accept equivalent arbitrary forms, references, open objects, boolean false, standalone null, type arrays, or general anyOf/oneOf.],
        [Duplicate raw document members reject before interpretation. MalformedDocument reports observed keyword type and shape violations. UnsupportedDocument reports unhandled keywords, omitted profile-required members, and restrictions on otherwise valid schema forms. UnsupportedDialect retains the declared dialect; InvalidDefinition locates contradictions in the codec model such as reversed bounds or duplicate enum labels/tags.],
        [Object profile restrictions return UnsupportedDocument: omitted additionalProperties reports OpenObject; omitted properties or required and undeclared required names report UnsupportedSchemaForm at the member or name path. Schema-valued additionalProperties also rejects as UnsupportedSchemaForm. Explicit wrong member types and duplicate required names remain malformed. No omitted member is filled in to admit a new shape.],
        [Document errors describe the first profile rejection, not complete Draft 2020-12 meta-schema validation. UnsupportedDocument does not certify that the rest of the schema is valid. Boolean roots, missing dialect/type, type arrays, one-sided or nonnative integer bounds, nonstring enum values and tags, and noncanonical tuple/nullable/tagged forms remain refused as unsupported. Actual wrong keyword types remain malformed. Arbitrary third-party protocol schemas are outside the supported profile.],
      )
      #behavior(title: "Profile restrictions do not claim malformed schema", level: "boundary", area: "Document loading")[
        #given[A schema uses an otherwise valid form outside the finite profile.]
        #when[The application requests a runtime contract.]
        #then[Loading refuses it as unsupported at the relevant path.]
        #then[No broader schema form is admitted by changing the diagnostic.]
      ]
      #behavior(title: "An unsupported keyword remains an error", level: "boundary", area: "Document loading")[
        #given[A finite-profile schema includes an unhandled keyword.]
        #when[The application loads it as a contract.]
        #then[Loading returns UnsupportedDocument at that keyword.]
        #then[No contract with the constraint discarded is returned.]
      ]
      #points(
        [Sources: #lnk("../../../src/json/blueprint/contract.gleam")[loader], #lnk("../../../test/contract_document_test.gleam")[document cases], and #lnk("../../../test/contract_test.gleam")[contract cases].],
      )
    ]
    #subsection(title: "Normalization and schema matching")[
      #points(
        [from_schema is total because every public Schema is checked. from_codec can fail with UnknownSchema and can panic on a source definition mistake. No process-local schema identity token is required.],
        [Normalization recursively sorts object properties by name, enum labels by text, and variants by tag. It retains associations and child order. Descriptions remain available for rendering; matching separately removes them recursively.],
        [#term("term-contract-match") is exact equality of those normalized shapes. It is not a solver for equivalence, subtyping, satisfiability, or data migration. A rebuilt equal contract can match a witness.],
      )
      #behavior(title: "Different bounds cannot reuse a witness", level: "boundary", area: "Contract matching")[
        #given[A value was validated under integer bounds zero through ten.]
        #when[The application decodes the witness with a codec declaring zero through eleven.]
        #then[Decoding returns ContractMismatch before native conversion.]
      ]
      #points(
        [Bound equality must hold even when this particular value lies within both ranges. Matching a custom codec's declared schema still does not certify its executable callbacks. #adr(6) records the witness contract.],
      )
    ]
    #subsection(title: "Validation and native conversion")[
      #points(
        [Validation walks the value and returns the first located failure. It checks exact numeric integrality and bounds without native Int/Float projection; it checks exact pair length, list elements, enum labels, closed property requiredness, and tagged payload shape.],
        [Closed object and union validation reject duplicate or unknown names before validating declared children. Required properties and payloads retain Field paths; collections retain Index paths. AnySchema accepts the supplied value unchanged, including a manually constructed raw Object with duplicate members.],
        [Successful validation creates the opaque witness. contract.decode obtains the retained codec's schema, compares normalized shapes, then invokes that codec's native decoder. Schema mismatch and unavailable schema both become ContractMismatch.],
        [A witness for the mathematical integer 1e30 can still fail codec.int native decoding due to its 24-digit projection bound or JavaScript safety. A witness for a finite exact number beyond binary64 can fail codec.float with FloatOutOfRange. Those outcomes do not invalidate the mathematical schema.],
        [contract.value_codec supplies Codec(Value) with the contract's schema. Encoding and decoding validate against that same finite schema. Successful conversion returns the supplied Value unchanged, retaining object order and exact numbers. A failure retains the validation path and Reason in the operation's EncodeError or DecodeError. Enclosing record and collection codecs prepend their Field and Index paths.],
        [This adapter validates structure and supported value constraints on each call without projecting exact numbers into native types. Typed and generated codecs retain their own encoding checks; they do not gain a separate schema-validation pass. Schema acceptance does not certify caller callbacks or business policy. #adr(6) records the scope and migration cost.],
        [Direct validate/load have no independent depth, width, or time guard. Parsed text has a byte-admission bound, which is not a heap quota; manually assembled values carry no admission proof. Consumers choose bounded construction/admission where their threat model requires it.],
        [Object validation searches names with string-specific comparisons up to 40 input members and builds a temporary dictionary above that count. A direct check of the first 32 members rejects an early name failure before the dictionary is built. Accepted values, member order, and first-error paths do not depend on the cutoff, and the dictionary is discarded after each validation. #adr(9) records the trade-off.],
      )
      #behavior(title: "The dynamic codec enforces its contract when encoding", level: "boundary", area: "Value encoding")[
        #given[The application retains a contract-backed Value codec.]
        #when[The application encodes a value through that codec.]
        #then[A value accepted by the contract is returned unchanged.]
        #then[A value refused by the contract returns an encoding failure with the first validation path and reason.]
      ]
    ]
  ])

  #section(title: "Legacy compatibility", lead: [The frozen 1.x surface retains established one-way decoding, independent encoders, broader schema description, and recursive references.], body: [
    #answers(title: "Legacy boundary", responsibility: [Keep published combinators and established data readable without inferring modern codec laws.], interface: [json/blueprint Decoder and FieldDecoder, decode0..decode9, field/optional_field, list, tuples, map, union/enum helpers, self_decoder, reuse_decoder; json/blueprint/schema.], interactions: [gleam/json parses after a byte precheck. Legacy schema rendering is independent from native decoder behavior.], invariants: [Legacy wire forms remain available explicitly. Opaque Decoder retains its decoder callback, schema description, and definitions.], failure: [json.DecodeError and dynamic decode errors retain legacy semantics; no strict finite-contract acceptance is inferred.])
    #entity(id: "legacy-decoder", title: "Legacy Decoder and FieldDecoder", description: [Immutable one-way native decoder with an independent legacy schema description.], kind: "value-object", owner: "Legacy compatibility", domain: "JSON contracts", lifecycle: "immutable", tint: "teal")[
      #attribute(name: "Callback and description", type: "Dynamic decoder × SchemaDefinition × definitions", provenance: "derived")[Combinators assemble conversion and description. FieldDecoder additionally retains its property name. No modern schema-validation witness is inferred.]
      #relates(cardinality: "1 : 0..n")[Reusable decoders retain named definitions for references; lazy self-decoding resolves through the caller's retained decoder function.]
    ]
    #points(
      [Legacy unions use type/data; legacy enum encoders use an enum object. Optional fields treat absence and null alike. Nonempty record decoding ignores unknown fields; decode0 permits scalar/nonempty input.],
      [decode uses a 1 MiB precheck before gleam/json. decode_with_max_bytes changes that bound. Native parsing owns duplicates and precision; there is no depth/value/token bound on this path.],
      [self_decoder accepts a lazy decoder and describes a root reference. reuse_decoder hashes the rendered schema definition with SHA-1 to name a `$defs` entry and rewrites root self-references to that entry. Nested recursion needs this explicit rebasing; the hash is a deterministic local description key, not a security authority or schema-equivalence proof.],
      [The legacy schema description supports type combinations, enum/const, nullable/optional, numeric constraints, string lengths/patterns/formats, array and object constraint families, allOf/anyOf/oneOf/not, references, and boolean schemas. This is a rendering surface, not the modern finite validator or proof that each described constraint is enforced by its decoder.],
      [The legacy renderer declares Draft-07 while some descriptions use later forms such as prefixItems and `$defs`. Consumers must not infer dialect correctness or general validation parity from that label. Changing only the label cannot prove compatibility.],
      [Callers that use only the published combinators compile unchanged. Direct construction of Decoder and FieldDecoder records and imports from the internal dynamic module are unsupported: callers build decoders with the combinators and import the standard dynamic decode module. get_dynamic_decoder returns a function from a dynamic value to the decoded value or a list of decode errors with the same expected, found and path fields. #adr(7) records the compatibility boundary.],
      [The #lnk("../../MIGRATION.md")[2.0 migration guide] gives application steps for retaining this API and for separately adopting codecs. Sources: #lnk("../../../src/json/blueprint.gleam")[legacy decoder], #lnk("../../../src/json/blueprint/schema.gleam")[legacy schema renderer], #lnk("../../../examples/test/legacy/union_type_test.gleam")[compiled legacy examples], and #lnk("../../../examples/test/migration_test.gleam")[the compiled migration example].],
    )
  ])

  #section(title: "Unsupported schema families", lead: [The finite profile is the whole supported schema language. A document outside it is refused and never partially interpreted.], body: [
    #md-table(3, (
      [Family], [Status], [Contract required before support],
      [String constraints], [Refused], [Length, patterns, and explicit format semantics: Unicode length policy, regex dialect and limits, annotation versus assertion],
      [Numeric constraints], [Only inclusive bounds are supported], [Exclusivity and multipleOf: exact arithmetic, projection distinction, hostile-resource budgets],
      [Collections and objects], [Closed objects, homogeneous lists and pairs only], [Additional item and property constraints and broader object models: uniqueness, contains, pattern properties, limits and error selection],
      [Enums and alternatives], [String enums, nullable values and tagged unions only], [Numeric enums, aliases, and general alternatives: canonical encoding, overlap, branch failures, equivalence limits],
      [References and recursion], [Refused by the runtime profile], [Recursive codec and schema families and named definitions: resolution scope, cycles, finite traversal and expansion, recursive laws],
      [Raw unmodeled schemas], [Refused], [Data for consumer policy without a validation claim: supported interpretation and admission stay explicit],
      [Evolution], [No fixtures], [Schema and wire migration fixtures: compatibility direction and accepted transformations],
    ))
    #points(
      [A family enters the profile only when it defines encoding and decoding agreement, schema semantics, rejection behavior, finite resource policy, and independent oracle fixtures. No constraint is silently discarded to accept a remote schema.],
      [Provider and protocol consumers own admission of a supported schema. They may reject AnySchema, tuple forms, optionality, unions, numeric precision, or future OtherSchema independently of generic local validity. Successful local loading is not proof of remote acceptance.],
      [The legacy surface describes the broader schema language, but that description is not modern codec or runtime validation support. #adr(1) records the rationale and scope.],
    )
  ])


  #section(title: "Verification and host boundaries", lead: [Verification distinguishes finite acceptance, native projection and legacy behavior.], body: [
    #subsection(title: "Oracle and behavioral evidence")[
      #points(
        [The independent oracle compares emitted and normalized schemas, codec decoding, and runtime validation with Python jsonschema Draft202012Validator against a frozen manifest. Selected cases carry stable identifiers and expected schemas/instances; missing, extra, duplicate, or replaced cases fail closed.],
        [The frozen manifest holds the finite cases in named families. Duplicate-key evidence is checked before native export can erase it. Exact-number kernel tests and target float-bit tests remain separate from this Boolean finite corpus. The retained 62-case Erlang arithmetic oracle executes the public number API and independently recomputes its results with Python Decimal and Fraction; both-target unit tests retain native-integer differences.],
        [Constructor law tests cover admitted native encode/decode and valid re-encoding where applicable. The contract-backed Value adapter enforces finite schema acceptance in both directions. Custom mapping and native projection constraints require their own explicit law scope.],
        [Hostile tests exercise parser grammar, resource bounds, duplicate keys, malformed/unsupported schemas, and deterministic generated inputs. Wide collection traversal uses tail-recursive paths where the implementation supplies them; caller-constructed unbounded trees retain no guaranteed stack bound.],
        [The pinned JSONTestSuite byte corpus runs on both targets without network access. Two upstream-valid duplicate-name documents are explicit strict-policy refusals; each implementation-defined fixture has a declared result. Deterministic generated documents and mutations compare acceptance and exact rendered meaning with Python JSON decoding and symbolic normalized decimal coefficients and exponents. Successful byte admission also agrees with text admission and parse/render/parse. This bounded corpus is not exhaustive fuzzing or general conformance certification.],
        [Sources: #lnk("../../../test/schema_check.py")[independent checker], #lnk("../../../test/schema_manifest.json")[frozen manifest], #lnk("../../../test/schema_oracle_test.gleam")[runtime cases], and #lnk("../../../test/hostile_test.gleam")[hostile cases]. #lnk("../../ORACLE.md")[The oracle document] pins the references, states reproducible commands and evidence limits; #adr(2) records the source attribution.],
      )
    ]
    #subsection(title: "Native host boundaries")[
      #points(
        [Erlang/OTP and Node targets exercise the common public contracts with explicit safe-integer, object-order, parse-location and runtime-capacity differences. Number FFI owns host byte handling, integer admission, binary64 parts, exact decimal/binary comparison, and exact decimal expansion. JSON FFI owns bounded byte checks, JavaScript host-string scalar validation and copied strings; internal dynamic FFI preserves legacy/native decoder conversion.],
        [FFI cannot trust an external host caller's Gleam type annotation. JavaScript adversarial tests inject nonfinite, fractional, unsafe, and previously rounded Int values. Native function name/arity changes need explicit upgrade audits because foreign callers bypass Gleam compiler checks.],
        [Sources: #lnk("../../../src/json_number_ffi.erl")[Erlang number FFI], #lnk("../../../src/json_number_ffi.mjs")[JavaScript number FFI], #lnk("../../../src/json_blueprint_ffi.erl")[Erlang JSON FFI], and #lnk("../../../src/json_blueprint_ffi.mjs")[JavaScript JSON FFI].],
      )
    ]
  ])


  #section(title: "End-to-end walkthrough", lead: [A caller retains one User codec, admits text, publishes its schema, and can validate runtime data before native conversion.], body: [
    #points(
      [User has name:String, age:Int bounded zero through 150, optional email:String, and Role encoded as admin/member. The record builder ends in User(name:, age:, email:, role:) and supplies native getters for each field.],
      [The input {"name":"Ada","age":36,"role":"admin"} passes byte admission, retains exact age, and decodes email as None. Encoding omits email. Schema publication includes closed properties, required name/age/role, exact age bounds, and the enum labels.],
    )
    #sequence(title: "Validation precedes native conversion", caption: [The sequence is synchronous. Callback behavior belongs to the retained native codec; no process or transport is implied.], participants: (
      (id: "app", label: "Application", shape: "actor"),
      (id: "parser", label: "Value parser"),
      (id: "contract", label: "Contract"),
      (id: "codec", label: "User codec"),
    ), steps: (
      seq-msg("app", "parser", "parse text within configured limits"),
      seq-msg("parser", "app", "immutable Value", dashed: true),
      seq-msg("app", "contract", "validate retained schema and Value"),
      seq-msg("contract", "app", "ValidatedValue or located rejection", dashed: true),
      seq-msg("app", "contract", "decode retained witness with User codec"),
      seq-msg("contract", "codec", "after normalized structural match"),
      seq-msg("codec", "contract", "native conversion result", dashed: true),
      seq-msg("contract", "app", "User or native decoding failure", dashed: true),
    ))
    #points(
      [An age of 151 fails at Field("age") with IntegerOutsideRange. An explicit email:null fails unless that field's inner codec is nullable. A repeated age key fails text admission before conversion.],
      [A remote schema can be parsed only if it belongs to the finite profile. A default-open object is refused as an unsupported form. A consumer needing broader remote schemas must preserve the unsupported result rather than substitute a permissive contract.],
      [Mapping User into an application-specific type retains the wire schema. The application handles Custom failures explicitly and owns mapping laws. Admitting a tool or provider request remains that consumer's separate decision.],
    )
  ])
  #pagebreak(weak: true)
]
