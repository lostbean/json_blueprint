#let terms = (
  (slug: "term-codegen-definition", title: [Codegen definition], body: [A development-time value joining a runtime codec, a native type expression, and source-lowering instructions. Named callbacks include explicit source references.]),
  (slug: "term-generated-module", title: [Generated module], body: [A returned Gleam source artifact with its relative module path and, for codec generation, a content fingerprint. Writing and compiling it belong to the caller's build workflow.]),
  (slug: "term-schema-materialization", title: [Schema materialization], body: [Generated functions that reconstruct checked schema structure without constructing codec callbacks. A materialized function may allocate a schema tree on each call.]),
  (slug: "term-schema-driven-generator", title: [Schema-driven generator], body: [The development-time function that turns an admitted closed-object schema into public native record types and a root typed codec accessor. It never constructs a native type from schema text at application runtime.]),
)
