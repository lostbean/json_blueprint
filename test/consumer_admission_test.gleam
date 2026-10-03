//// A consumer package's view of `codec.Schema`: Relay, the standalone LLM
//// client and Fabric walk a tool schema to decide whether they can admit it.
//// Like a separate package, this module uses only the public API: schemas
//// come from codecs, and `codec.view` and `codec.description` read them.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec.{type Schema}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value.{type Value}

pub type Segment {
  Property(String)
  Element
  TupleIndex(Int)
  NonNullCase
  TaggedCase(String)
}

pub type Feature {
  TextValues
  StringEnumValues(List(String))
  IntegerValues
  ExactDecimalValues
  BooleanValues
  ClosedObject
  OptionalProperty
  ArrayValues
  FixedTuple
  NullableValues
  TaggedAlternatives
  UnitAlternative
  IntegerBounds(min: Int, max: Int)
  DecimalBounds(min: number.Number, max: number.Number)
  AnyValues
  /// A schema kind added after this consumer was written.
  OtherKind(document: Value)
}

pub type Requirement {
  Requirement(path: List(Segment), feature: Feature)
}

pub fn extract_requirements(schema: Schema) -> List(Requirement) {
  at(schema, [])
}

fn at(schema: Schema, path: List(Segment)) -> List(Requirement) {
  case codec.view(schema) {
    codec.StringSchema -> [Requirement(path, TextValues)]
    codec.StringEnumSchema(labels) -> [
      Requirement(path, StringEnumValues(labels)),
    ]
    codec.IntSchema -> [Requirement(path, IntegerValues)]
    codec.NumberSchema -> [Requirement(path, ExactDecimalValues)]
    codec.BoolSchema -> [Requirement(path, BooleanValues)]
    codec.IntegerRangeSchema(min, max) -> [
      Requirement(path, IntegerValues),
      Requirement(path, IntegerBounds(min, max)),
    ]
    codec.NumberRangeSchema(min, max) -> [
      Requirement(path, ExactDecimalValues),
      Requirement(path, DecimalBounds(min, max)),
    ]
    codec.ObjectSchema(properties) -> [
      Requirement(path, ClosedObject),
      ..properties_at(properties, path)
    ]
    codec.ListSchema(inner) -> [
      Requirement(path, ArrayValues),
      ..at(inner, list.append(path, [Element]))
    ]
    codec.PairSchema(left, right) -> [
      Requirement(path, ArrayValues),
      Requirement(path, FixedTuple),
      ..list.append(
        at(left, list.append(path, [TupleIndex(0)])),
        at(right, list.append(path, [TupleIndex(1)])),
      )
    ]
    codec.NullableSchema(inner) -> [
      Requirement(path, NullableValues),
      ..at(inner, list.append(path, [NonNullCase]))
    ]
    codec.UnionSchema(variants) -> [
      Requirement(path, ClosedObject),
      Requirement(path, TaggedAlternatives),
      ..list.flat_map(variants, fn(variant) {
        let case_path = list.append(path, [TaggedCase(variant.tag)])
        case variant.payload {
          None -> [Requirement(case_path, UnitAlternative)]
          Some(payload) ->
            at(payload, list.append(case_path, [Property("value")]))
        }
      })
    ]
    codec.AnySchema -> [Requirement(path, AnyValues)]
    codec.OtherSchema(document) -> [Requirement(path, OtherKind(document))]
  }
}

fn properties_at(
  properties: List(codec.PropertySchema),
  path: List(Segment),
) -> List(Requirement) {
  list.flat_map(properties, fn(property) {
    let location = list.append(path, [Property(property.name)])
    case property.required {
      True -> at(property.schema, location)
      False -> [
        Requirement(location, OptionalProperty),
        ..at(property.schema, location)
      ]
    }
  })
}

pub type AdmissionIssue {
  UnsupportedFeature(Requirement)
  RootMustBeObject
  DuplicateToolName(String)
  UnknownToolSchema
}

pub type ToolEntry {
  ToolEntry(name: String, description: String, schema: Schema)
}

pub fn tool_entry(
  name: String,
  description: String,
  input: codec.Codec(a),
) -> Result(ToolEntry, AdmissionIssue) {
  case codec.schema(input) {
    Ok(schema) -> Ok(ToolEntry(name, description, schema))
    Error(codec.UnknownSchema) -> Error(UnknownToolSchema)
  }
}

pub fn admit_object_root(entry: ToolEntry) -> List(AdmissionIssue) {
  case object_root(entry.schema) {
    True -> []
    False -> [RootMustBeObject]
  }
}

fn object_root(schema: Schema) -> Bool {
  case codec.view(schema) {
    codec.ObjectSchema(_) | codec.UnionSchema(_) -> True
    // A kind this consumer does not know is not admitted as an object.
    codec.OtherSchema(_) -> False
    _ -> False
  }
}

pub fn reject_feature(
  requirements: List(Requirement),
  forbidden: Feature,
) -> List(AdmissionIssue) {
  list.filter_map(requirements, fn(requirement) {
    case requirement.feature == forbidden {
      True -> Ok(UnsupportedFeature(requirement))
      False -> Error(Nil)
    }
  })
}

fn schema_of(c: codec.Codec(a)) -> Schema {
  let assert Ok(schema) = codec.schema(c)
  schema
}

pub type Command {
  Start(delay: Int)
  Stop
  Restart
}

fn command_codec() -> codec.Codec(Command) {
  codec.union({
    use start <- codec.variant("start", codec.integer_between(0, 60), Start)
    use stop <- codec.unit_variant("stop", Stop)
    use restart <- codec.unit_variant("restart", Restart)
    codec.match(fn(command) {
      case command {
        Start(delay) -> start(delay)
        Stop -> stop
        Restart -> restart
      }
    })
  })
}

fn user_codec() -> codec.Codec(#(Int, String)) {
  use id <- codec.field("id", codec.int(), get: fn(u) { u.0 })
  use name <- codec.field("name", codec.string(), get: fn(u) { u.1 })
  codec.success(#(id, name))
}

pub type Choice {
  Number(Int)
  Text(String)
  Nothing
}

fn choice_codec() -> codec.Codec(Choice) {
  codec.union({
    use number <- codec.variant("number", codec.int(), Number)
    use text <- codec.variant("text", codec.string(), Text)
    use nothing <- codec.unit_variant("nothing", Nothing)
    codec.match(fn(choice) {
      case choice {
        Number(n) -> number(n)
        Text(t) -> text(t)
        Nothing -> nothing
      }
    })
  })
}

pub fn relay_and_standalone_llm_admission_test() {
  // 1. Tool with object root schema is admitted
  let user_schema = schema_of(user_codec())
  let user_tool = ToolEntry("get_user", "Fetch user by id", user_schema)
  admit_object_root(user_tool)
  |> should.equal([])

  // A described object root and a union root are objects too
  let described = schema_of(codec.describe(user_codec(), "A user"))
  codec.description(described) |> should.equal(Some("A user"))
  admit_object_root(ToolEntry("described", "", described))
  |> should.equal([])
  let assert Ok(command_tool) =
    tool_entry("control", "Control the job", command_codec())
  admit_object_root(command_tool)
  |> should.equal([])

  // 2. Tool with scalar root schema is rejected by Relay/LLM profile
  let scalar_tool = ToolEntry("ping", "Ping", schema_of(codec.string()))
  admit_object_root(scalar_tool)
  |> should.equal([RootMustBeObject])

  // An any root is not an object either
  admit_object_root(ToolEntry("forward", "", schema_of(codec.value())))
  |> should.equal([RootMustBeObject])

  // 3. Custom codec with UnknownSchema fails entry construction
  let custom_codec =
    codec.custom(
      encode: fn(i: Int) {
        let assert Ok(num) = number.from_int(i)
        Ok(value.Number(num))
      },
      decode: fn(_) { Ok(1) },
      schema: None,
      placeholder: 0,
    )
  codec.schema(custom_codec)
  |> should.equal(Error(codec.UnknownSchema))
  tool_entry("custom", "", custom_codec)
  |> should.equal(Error(UnknownToolSchema))
  contract.from_codec(custom_codec)
  |> should.equal(Error(codec.UnknownSchema))
}

pub fn fabric_schema_admission_policies_test() {
  // Tool schema with an optional property, under a single required field
  let inner = {
    use id <- codec.field("id", codec.integer_between(1, 10), get: fn(r) { r.0 })
    use labels <- codec.optional_field(
      "labels",
      codec.list(codec.nullable(codec.string())),
      get: fn(r) { r.1 },
    )
    codec.success(#(id, labels))
  }
  let request = {
    use request <- codec.field("request", inner, get: fn(r) { r })
    codec.success(request)
  }

  let reqs = extract_requirements(schema_of(request))

  // Policy rejecting OptionalProperty finds the exact located requirement
  let issues = reject_feature(reqs, OptionalProperty)
  issues
  |> should.equal([
    UnsupportedFeature(Requirement(
      [Property("request"), Property("labels")],
      OptionalProperty,
    )),
  ])

  // Tool schema with TaggedAlternatives
  let choice_reqs = extract_requirements(schema_of(choice_codec()))

  let choice_issues = reject_feature(choice_reqs, TaggedAlternatives)
  choice_issues
  |> should.equal([UnsupportedFeature(Requirement([], TaggedAlternatives))])

  // A policy without unit variants finds each one by its tag
  reject_feature(
    extract_requirements(schema_of(command_codec())),
    UnitAlternative,
  )
  |> should.equal([
    UnsupportedFeature(Requirement([TaggedCase("stop")], UnitAlternative)),
    UnsupportedFeature(Requirement([TaggedCase("restart")], UnitAlternative)),
  ])

  // A policy without pass-through values finds a `value()` field
  let envelope = {
    use kind <- codec.field("kind", codec.string(), get: fn(e) { e.0 })
    use body <- codec.field("body", codec.value(), get: fn(e) { e.1 })
    codec.success(#(kind, body))
  }
  reject_feature(extract_requirements(schema_of(envelope)), AnyValues)
  |> should.equal([
    UnsupportedFeature(Requirement([Property("body")], AnyValues)),
  ])
}

pub type Many {
  Small(Int)
  Many(List(String))
  NoneLeft
}

pub fn structural_requirements_extraction_test() {
  // PairSchema
  extract_requirements(schema_of(codec.pair(codec.bool(), codec.int())))
  |> should.equal([
    Requirement([], ArrayValues),
    Requirement([], FixedTuple),
    Requirement([TupleIndex(0)], BooleanValues),
    Requirement([TupleIndex(1)], IntegerValues),
  ])

  // NullableSchema with IntegerRange
  extract_requirements(schema_of(codec.nullable(codec.integer_between(1, 10))))
  |> should.equal([
    Requirement([], NullableValues),
    Requirement([NonNullCase], IntegerValues),
    Requirement([NonNullCase], IntegerBounds(1, 10)),
  ])

  // UnionSchema with payload variants and a unit variant
  let many =
    codec.union({
      use small <- codec.variant("small", codec.integer_between(1, 2), Small)
      use many <- codec.variant("many", codec.list(codec.string()), Many)
      use none <- codec.unit_variant("none", NoneLeft)
      codec.match(fn(item) {
        case item {
          Small(n) -> small(n)
          Many(items) -> many(items)
          NoneLeft -> none
        }
      })
    })
  extract_requirements(schema_of(many))
  |> should.equal([
    Requirement([], ClosedObject),
    Requirement([], TaggedAlternatives),
    Requirement([TaggedCase("small"), Property("value")], IntegerValues),
    Requirement([TaggedCase("small"), Property("value")], IntegerBounds(1, 2)),
    Requirement([TaggedCase("many"), Property("value")], ArrayValues),
    Requirement([TaggedCase("many"), Property("value"), Element], TextValues),
    Requirement([TaggedCase("none")], UnitAlternative),
  ])

  // The schema of a union codec
  extract_requirements(schema_of(command_codec()))
  |> should.equal([
    Requirement([], ClosedObject),
    Requirement([], TaggedAlternatives),
    Requirement([TaggedCase("start"), Property("value")], IntegerValues),
    Requirement([TaggedCase("start"), Property("value")], IntegerBounds(0, 60)),
    Requirement([TaggedCase("stop")], UnitAlternative),
    Requirement([TaggedCase("restart")], UnitAlternative),
  ])

  // A described enum: the view looks through the description
  let level =
    codec.string_enum([#("low", 0), #("high", 1)])
    |> codec.describe("Level")
  extract_requirements(schema_of(level))
  |> should.equal([Requirement([], StringEnumValues(["low", "high"]))])

  // NumberSchema and NumberRangeSchema
  let assert Ok(num0) = number.from_int(0)
  let assert Ok(num100) = number.from_int(100)
  extract_requirements(schema_of(codec.number()))
  |> should.equal([Requirement([], ExactDecimalValues)])

  extract_requirements(schema_of(codec.number_between(num0, num100)))
  |> should.equal([
    Requirement([], ExactDecimalValues),
    Requirement([], DecimalBounds(num0, num100)),
  ])

  // AnySchema, alone and as list items
  extract_requirements(schema_of(codec.list(codec.value())))
  |> should.equal([
    Requirement([], ArrayValues),
    Requirement([Element], AnyValues),
  ])
}

pub fn exact_decimal_admission_distinction_test() {
  let assert Ok(num_min) = number.from_int(0)
  let assert Ok(num_max) = number.from_int(100)

  let int_reqs = extract_requirements(schema_of(codec.int()))
  let number_reqs = extract_requirements(schema_of(codec.number()))
  let number_range_reqs =
    extract_requirements(schema_of(codec.number_between(num_min, num_max)))

  // Profile A: integer-only consumer (disallows fractional/exact decimals)
  // 1. Accepts integer schema
  reject_feature(int_reqs, ExactDecimalValues)
  |> should.equal([])

  // 2. Rejects NumberSchema with explicit UnsupportedFeature(ExactDecimalValues)
  reject_feature(number_reqs, ExactDecimalValues)
  |> should.equal([UnsupportedFeature(Requirement([], ExactDecimalValues))])

  // 3. Rejects NumberRangeSchema with explicit UnsupportedFeature(ExactDecimalValues)
  reject_feature(number_range_reqs, ExactDecimalValues)
  |> should.equal([UnsupportedFeature(Requirement([], ExactDecimalValues))])

  // Profile B: consumer that rejects integers but requires exact decimals
  reject_feature(number_reqs, IntegerValues)
  |> should.equal([])

  reject_feature(int_reqs, IntegerValues)
  |> should.equal([UnsupportedFeature(Requirement([], IntegerValues))])

  // `float()` and `number()` share the number schema
  codec.view(schema_of(codec.float())) |> should.equal(codec.NumberSchema)
  codec.schema(codec.float()) |> should.equal(codec.schema(codec.number()))
}
