# Evolve opaque schemas through a stable public projection

<a id="adr-0005"></a>

- **Decision.** Schema is opaque. `view` exposes a fixed 2.x `SchemaView` with opaque children and `OtherSchema(document)` for future minor-release kinds. Descriptions use an accessor rather than another kind wrapper.
- **Rationale.** Exhaustive matching on the former transparent union meant adding one schema kind broke provider and protocol walkers. A documented fallback branch could not enforce future compatibility.
- **Alternatives.** A kind-only classification cannot support recursive provider conversion. A visitor callback record itself changes when a new callback is added. An opaque visitor builder with a default is heavier than the stable projection.
- **Consequences.** A new dedicated view variant requires a major release; future minor kinds retain rendered data in OtherSchema. Consumers choose rejection or forwarding explicitly. Checked schema construction makes `contract.from_schema` total. `codec.value` can publish AnySchema without breaking existing walkers.
- **Evidence.** [Opaque-schema change](https://github.com/lostbean/json_blueprint/commit/06b8e3608c599521c737973a6e2d592c1d27632d) and [migration account](https://github.com/lostbean/json_blueprint/commit/07e64fc6d57d238003ffc0166d3ac2f777503ff6), dated 2026-10-03, supply decision provenance. The deleted intermediate migration guide recorded actual Relay/LLM exhaustive matches; current [consumer admission tests](../../test/consumer_admission_test.gleam), [opaque model](../../src/json/blueprint/codec.gleam), and [API tests](../../test/api_control_test.gleam) retain the contract. Old intermediate signatures are intentionally retired; they were not published compatibility promises.
