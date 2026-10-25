#let terms = (
  (slug: "term-json-value", title: [JSON value], body: [An immutable JSON algebra value with ordered object members and an exact number alternative. Duplicate object members remain representable until a checked boundary rejects them.]),
  (slug: "term-exact-number", title: [Exact number], body: [A finite mathematical JSON number represented by a normalized decimal coefficient and exponent, with one positive zero. Its value is independent of a target's native integer or binary64 representation.]),
  (slug: "term-admission-limits", title: [Admission limits], body: [The caller-authored byte bound checked before text parsing. Consumers own policies for the decoded structure; explicit standalone number parsing can apply separate numeric limits. A value assembled without parsing carries no admission proof.]),
  (slug: "term-codec", title: [Codec], body: [A typed definition joining native encoding, native decoding, a placeholder, and an available or unavailable schema. The native type parameter belongs to the caller's compiled program.]),
  (slug: "term-placeholder", title: [Placeholder], body: [A codec's native value used to describe a definition without input and to construct a failing native decoder. It need not be valid application data.]),
  (slug: "term-schema", title: [Schema], body: [An opaque, checked description of the finite JSON acceptance profile. Descriptions are annotations on that structure.]),
  (slug: "term-schema-view", title: [Schema view], body: [The stable public projection of one schema node with opaque schema children. Its fallback carries a future kind's rendered JSON Schema object.]),
  (slug: "term-finite-profile", title: [Finite profile], body: [The supported schema language of primitives, exact bounds, closed objects, pairs, lists, nullable values, string enums, tagged unions, and any value. It is narrower than JSON Schema Draft 2020-12.]),
  (slug: "term-unsupported-document", title: [Unsupported document], body: [A schema document that is well-formed for its keywords but outside the finite profile. It is refused at the first unsupported feature, and the refusal does not certify the rest of the document.

    _Avoid_: invalid schema — a malformed keyword value is a separate outcome, and an unsupported form is valid JSON Schema.]),
  (slug: "term-contract", title: [Contract], body: [A normalized runtime-validation schema that retains no native type or application callback.]),
  (slug: "term-validated-value", title: [Validated value], body: [An opaque immutable pair of a JSON value and the normalized schema that accepted it. Its evidence applies to that value under that schema.]),
  (slug: "term-contract-match", title: [Contract match], body: [Equality of finite schema structure after normalization and removal of descriptions.]),
  (slug: "term-record-builder", title: [Record builder], body: [A continuation-based codec definition that binds decoded fields by name and ends with a native record constructor. Each field also supplies its native getter.]),
  (slug: "term-tagged-union", title: [Tagged union], body: [A closed object sum selected by a string tag, with a payload exactly when that selected variant declares one.]),
  (slug: "term-definition-error", title: [Definition error], body: [A contradiction in a codec definition, distinct from invalid input or unavailable schema.]),
  (slug: "term-native-projection", title: [Native projection], body: [A checked conversion of an exact number into a target's Int or Float representation. Wire acceptance and successful projection are separate facts.]),
  (slug: "term-legacy-decoder", title: [Legacy decoder], body: [The frozen 1.x one-way decoder with an independent legacy schema description. Its established data envelopes and acceptance rules differ from Codec.]),
  (slug: "term-oracle-corpus", title: [Oracle corpus], body: [The frozen manifest of finite-profile cases with stable identifiers, expected schemas, and instances. An independent checker compares package output with a Draft 2020-12 validator, and a missing, extra, repeated, or replaced case fails.]),
  (slug: "term-consumer", title: [Consumer], body: [A separate package or application that publishes, admits, or executes with codecs and schemas and owns its own protocol, provider, and business policy. A consumer imports only public modules of this package.]),
)
