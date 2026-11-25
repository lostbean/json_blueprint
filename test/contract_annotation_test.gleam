//// Draft 2020-12 annotation keywords do not constrain an instance, so the
//// loader accepts and ignores them wherever a schema object appears. Every
//// keyword that constrains a value is still refused.

import gleam/list
import gleeunit/should
import json/blueprint/codec.{Field, Index}
import json/blueprint/contract
import json/blueprint/value

const dialect = "\"$schema\":\"https://json-schema.org/draft/2020-12/schema\""

fn load(text: String) -> Result(contract.Contract, contract.LoadError) {
  contract.parse(text, value.default_limits())
}

fn loaded(text: String) -> contract.Contract {
  let assert Ok(loaded) = load(text)
  loaded
}

fn accepts(schema: contract.Contract, instance: String) -> Bool {
  let assert Ok(parsed) = value.parse(instance, value.default_limits())
  case contract.validate(schema, parsed) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn unsupported(
  path: List(codec.PathSegment),
  name: String,
) -> Result(contract.Contract, contract.LoadError) {
  Error(
    contract.InvalidDocument(contract.UnsupportedDocument(
      path,
      contract.UnsupportedKeyword(name),
    )),
  )
}

pub fn title_on_the_root_is_ignored_test() {
  let annotated =
    loaded(
      "{"
      <> dialect
      <> ",\"title\":\"Args\",\"type\":\"object\","
      <> "\"properties\":{},\"required\":[],\"additionalProperties\":false}",
    )
  let plain =
    loaded(
      "{"
      <> dialect
      <> ",\"type\":\"object\","
      <> "\"properties\":{},\"required\":[],\"additionalProperties\":false}",
    )
  contract.same_schema(annotated, plain) |> should.be_true
}

/// `model_json_schema()` of a Pydantic 2 model with `extra="forbid"`:
///
///     class WeatherArgs(BaseModel):
///         model_config = ConfigDict(extra="forbid")
///         city: str = Field(description="City name", examples=["Lisbon"])
///         days: int = Field(default=3, ge=1, le=14)
///         units: Literal["metric", "imperial"] = "metric"
///         note: str | None = None
///
/// Pydantic emits no `$schema`; the caller adds it.
const pydantic_weather =
  "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",
  \"additionalProperties\":false,
  \"properties\":{
    \"city\":{\"description\":\"City name\",\"examples\":[\"Lisbon\"],\"title\":\"City\",\"type\":\"string\"},
    \"days\":{\"default\":3,\"maximum\":14,\"minimum\":1,\"title\":\"Days\",\"type\":\"integer\"},
    \"units\":{\"default\":\"metric\",\"enum\":[\"metric\",\"imperial\"],\"title\":\"Units\",\"type\":\"string\"},
    \"note\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"null\"}],\"default\":null,\"title\":\"Note\"}},
  \"required\":[\"city\"],
  \"title\":\"WeatherArgs\",
  \"type\":\"object\"}"

pub fn pydantic_model_schema_loads_and_keeps_its_constraints_test() {
  let schema = loaded(pydantic_weather)
  accepts(schema, "{\"city\":\"Lisbon\"}") |> should.be_true
  accepts(
    schema,
    "{\"city\":\"Lisbon\",\"days\":14,\"units\":\"imperial\",\"note\":null}",
  )
  |> should.be_true
  accepts(schema, "{\"city\":\"Lisbon\",\"days\":15}") |> should.be_false
  accepts(schema, "{\"city\":\"Lisbon\",\"units\":\"kelvin\"}")
  |> should.be_false
  accepts(schema, "{\"days\":3}") |> should.be_false
  accepts(schema, "{\"city\":\"Lisbon\",\"extra\":1}") |> should.be_false
}

/// `z.toJSONSchema(Args)` from Zod 4 for:
///
///     const Args = z.strictObject({
///       query: z.string().describe("Search text"),
///       limit: z.int().min(1).max(50).default(10),
///       sort: z.enum(["relevance", "date"]).meta({ deprecated: true }),
///     }).meta({ title: "SearchArgs",
///               examples: [{ query: "gleam", limit: 10, sort: "date" }] })
const zod_search =
  "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",
  \"title\":\"SearchArgs\",
  \"examples\":[{\"query\":\"gleam\",\"limit\":10,\"sort\":\"date\"}],
  \"type\":\"object\",
  \"properties\":{
    \"query\":{\"type\":\"string\",\"description\":\"Search text\"},
    \"limit\":{\"default\":10,\"type\":\"integer\",\"minimum\":1,\"maximum\":50},
    \"sort\":{\"deprecated\":true,\"type\":\"string\",\"enum\":[\"relevance\",\"date\"]}},
  \"required\":[\"query\",\"limit\",\"sort\"],
  \"additionalProperties\":false}"

pub fn zod_object_schema_loads_and_keeps_its_constraints_test() {
  let schema = loaded(zod_search)
  accepts(schema, "{\"query\":\"gleam\",\"limit\":10,\"sort\":\"date\"}")
  |> should.be_true
  accepts(schema, "{\"query\":\"gleam\",\"limit\":0,\"sort\":\"date\"}")
  |> should.be_false
  accepts(schema, "{\"query\":\"gleam\",\"limit\":10,\"sort\":\"name\"}")
  |> should.be_false
  accepts(schema, "{\"query\":\"gleam\",\"sort\":\"date\"}") |> should.be_false
}

/// An MCP tool `inputSchema` in the shape servers publish, closed and with a
/// dialect, carrying every annotation keyword.
const mcp_tool_input =
  "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",
  \"$id\":\"https://example.com/tools/get_weather/input\",
  \"$comment\":\"Generated from the tool definition.\",
  \"title\":\"get_weather arguments\",
  \"description\":\"Arguments for get_weather.\",
  \"type\":\"object\",
  \"properties\":{
    \"location\":{\"type\":\"string\",\"description\":\"City name or zip code\",\"examples\":[\"Lisbon\",\"94103\"]},
    \"request_id\":{\"type\":\"string\",\"readOnly\":true},
    \"token\":{\"type\":\"string\",\"writeOnly\":true,\"deprecated\":false},
    \"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"title\":\"Tag\"},\"default\":[]}},
  \"required\":[\"location\"],
  \"additionalProperties\":false}"

pub fn mcp_tool_input_schema_loads_with_every_annotation_test() {
  let schema = loaded(mcp_tool_input)
  accepts(schema, "{\"location\":\"Lisbon\",\"tags\":[\"a\"]}")
  |> should.be_true
  accepts(schema, "{\"location\":1}") |> should.be_false
  accepts(schema, "{\"location\":\"Lisbon\",\"tags\":[1]}") |> should.be_false
}

pub fn mcp_tool_input_schema_still_refuses_an_open_object_test() {
  // The usual published form omits `additionalProperties`; the profile still
  // refuses it for that reason, not for its annotations.
  load(
    "{"
    <> dialect
    <> ",\"title\":\"get_weather arguments\",\"type\":\"object\","
    <> "\"properties\":{\"location\":{\"type\":\"string\",\"title\":\"Location\","
    <> "\"description\":\"City name or zip code\"}},\"required\":[\"location\"]}",
  )
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.UnsupportedDocument(
        [Field("additionalProperties")],
        contract.OpenObject,
      )),
    ),
  )
}

pub fn annotations_are_ignored_in_nullable_and_tagged_alternatives_test() {
  let schema =
    loaded(
      "{"
      <> dialect
      <> ",\"title\":\"Shape\",\"type\":\"object\",\"oneOf\":["
      <> "{\"title\":\"Circle\",\"description\":\"A circle.\",\"type\":\"object\","
      <> "\"properties\":{\"tag\":{\"const\":\"circle\",\"title\":\"Tag\"},"
      <> "\"value\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":10,\"title\":\"Radius\"}},"
      <> "\"required\":[\"tag\",\"value\"],\"additionalProperties\":false},"
      <> "{\"$comment\":\"no payload\",\"type\":\"object\","
      <> "\"properties\":{\"tag\":{\"const\":\"empty\",\"description\":\"Nothing.\"}},"
      <> "\"required\":[\"tag\"],\"additionalProperties\":false}]}",
    )
  accepts(schema, "{\"tag\":\"circle\",\"value\":3}") |> should.be_true
  accepts(schema, "{\"tag\":\"empty\"}") |> should.be_true
  accepts(schema, "{\"tag\":\"circle\",\"value\":11}") |> should.be_false
  let nullable =
    loaded(
      "{"
      <> dialect
      <> ",\"title\":\"Maybe\",\"default\":null,\"anyOf\":["
      <> "{\"type\":\"string\",\"title\":\"Text\"},"
      <> "{\"type\":\"null\",\"title\":\"Nothing\"}]}",
    )
  accepts(nullable, "null") |> should.be_true
  accepts(nullable, "\"a\"") |> should.be_true
  accepts(nullable, "1") |> should.be_false
}

pub fn annotations_do_not_change_the_contract_test() {
  let plain =
    loaded(
      "{"
      <> dialect
      <> ",\"type\":\"object\",\"properties\":{"
      <> "\"n\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":2}},"
      <> "\"required\":[\"n\"],\"additionalProperties\":false}",
    )
  let annotated =
    loaded(
      "{"
      <> dialect
      <> ",\"$id\":\"urn:example:n\",\"title\":\"N\","
      <> "\"examples\":[{\"n\":1}],\"default\":{\"n\":1},\"deprecated\":true,"
      <> "\"readOnly\":false,\"writeOnly\":false,\"$comment\":\"c\","
      <> "\"type\":\"object\",\"properties\":{"
      <> "\"n\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":2,\"title\":\"N\"}},"
      <> "\"required\":[\"n\"],\"additionalProperties\":false}",
    )
  contract.same_schema(annotated, plain) |> should.be_true
  // A default or an example outside the schema constrains nothing.
  let odd_default =
    loaded(
      "{"
      <> dialect
      <> ",\"type\":\"integer\",\"minimum\":1,\"maximum\":2,"
      <> "\"default\":\"none\",\"examples\":[99]}",
    )
  accepts(odd_default, "99") |> should.be_false
  accepts(odd_default, "\"none\"") |> should.be_false
}

pub fn keywords_that_constrain_a_value_are_still_refused_test() {
  list.each(
    [
      #("format", "\"email\""),
      #("pattern", "\"^a\""),
      #("minLength", "1"),
      #("const", "\"a\""),
      #("contentMediaType", "\"application/json\""),
      #("contentEncoding", "\"base64\""),
      #("$ref", "\"#/$defs/a\""),
      #("$defs", "{}"),
      #("$anchor", "\"a\""),
      #("not", "{}"),
    ],
    fn(keyword) {
      let #(name, raw) = keyword
      load(
        "{"
        <> dialect
        <> ",\"title\":\"T\",\"type\":\"string\",\""
        <> name
        <> "\":"
        <> raw
        <> "}",
      )
      |> should.equal(unsupported([Field(name)], name))
    },
  )
  load(
    "{"
    <> dialect
    <> ",\"type\":\"array\",\"items\":"
    <> "{\"title\":\"Item\",\"type\":\"string\",\"format\":\"uuid\"}}",
  )
  |> should.equal(unsupported([Field("items"), Field("format")], "format"))
}

pub fn annotations_with_the_wrong_type_are_malformed_test() {
  let malformed = fn(
    name: String,
    raw: String,
    reason: contract.MalformedReason,
  ) {
    load(
      "{" <> dialect <> ",\"type\":\"string\",\"" <> name <> "\":" <> raw <> "}",
    )
    |> should.equal(
      Error(
        contract.InvalidDocument(contract.MalformedDocument(
          [Field(name)],
          reason,
        )),
      ),
    )
  }
  malformed("title", "1", contract.ExpectedText)
  malformed("$comment", "[]", contract.ExpectedText)
  malformed("$id", "null", contract.ExpectedText)
  malformed("deprecated", "\"yes\"", contract.ExpectedBoolean)
  malformed("readOnly", "1", contract.ExpectedBoolean)
  malformed("writeOnly", "{}", contract.ExpectedBoolean)
  malformed("examples", "\"a\"", contract.ExpectedArray)
  // A property named like an annotation is a property, not an annotation.
  let schema =
    loaded(
      "{"
      <> dialect
      <> ",\"type\":\"object\",\"properties\":{"
      <> "\"title\":{\"type\":\"string\"}},"
      <> "\"required\":[\"title\"],\"additionalProperties\":false}",
    )
  accepts(schema, "{\"title\":\"x\"}") |> should.be_true
  accepts(schema, "{}") |> should.be_false
  // Annotations inside a variant sit at their own path.
  load(
    "{"
    <> dialect
    <> ",\"type\":\"object\",\"oneOf\":[{\"title\":2,"
    <> "\"type\":\"object\",\"properties\":{\"tag\":{\"const\":\"a\"}},"
    <> "\"required\":[\"tag\"],\"additionalProperties\":false}]}",
  )
  |> should.equal(
    Error(
      contract.InvalidDocument(contract.MalformedDocument(
        [Field("oneOf"), Index(0), Field("title")],
        contract.ExpectedText,
      )),
    ),
  )
}

/// `description` is checked in the same pass as the other annotations, so a
/// wrong `description` is reported before a later member's error. Members are
/// listed in an order both targets parse alike.
pub fn a_malformed_description_is_reported_before_later_members_test() {
  let malformed_at = fn(path: List(codec.PathSegment)) {
    Error(
      contract.InvalidDocument(contract.MalformedDocument(
        path,
        contract.ExpectedText,
      )),
    )
  }
  load("{" <> dialect <> ",\"type\":\"string\",\"description\":1,\"title\":2}")
  |> should.equal(malformed_at([Field("description")]))
  load(
    "{"
    <> dialect
    <> ",\"description\":1,\"items\":{\"type\":\"string\",\"title\":2},"
    <> "\"type\":\"array\"}",
  )
  |> should.equal(malformed_at([Field("description")]))
}
