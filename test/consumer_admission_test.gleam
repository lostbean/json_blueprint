//// A consumer package's view of `codec.Schema`: Relay, the standalone LLM
//// client and Fabric walk a tool schema to decide whether they can admit it.

import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import json/blueprint/codec.{type Schema}
import json/blueprint/contract
import json/blueprint/number
import json/blueprint/value

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
}

pub type Requirement {
  Requirement(path: List(Segment), feature: Feature)
}

pub fn extract_requirements(schema: Schema) -> List(Requirement) {
  at(schema, [])
}

fn at(schema: Schema, path: List(Segment)) -> List(Requirement) {
  case schema {
    codec.DescribedSchema(_, inner) -> at(inner, path)
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
  }
}

fn properties_at(
  properties: List(codec.PropertySchema),
  path: List(Segment),
) -> List(Requirement) {
  case properties {
    [] -> []
    [codec.PropertySchema(name, required, s), ..rest] -> {
      let location = list.append(path, [Property(name)])
      let own = case required {
        True -> at(s, location)
        False -> [Requirement(location, OptionalProperty), ..at(s, location)]
      }
      list.append(own, properties_at(rest, path))
    }
  }
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
  case schema {
    codec.DescribedSchema(_, inner) -> object_root(inner)
    codec.ObjectSchema(_) | codec.UnionSchema(_) -> True
    _ -> False
  }
}

pub fn reject_feature(
  requirements: List(Requirement),
  forbidden: Feature,
) -> List(AdmissionIssue) {
  case requirements {
    [] -> []
    [req, ..rest] ->
      case req.feature == forbidden {
        True -> [UnsupportedFeature(req), ..reject_feature(rest, forbidden)]
        False -> reject_feature(rest, forbidden)
      }
  }
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

pub fn relay_and_standalone_llm_admission_test() {
  // 1. Tool with object root schema is admitted
  let user_schema =
    codec.ObjectSchema([
      codec.PropertySchema("id", True, codec.IntSchema),
      codec.PropertySchema("name", True, codec.StringSchema),
    ])
  let user_tool = ToolEntry("get_user", "Fetch user by id", user_schema)
  admit_object_root(user_tool)
  |> should.equal([])

  // A described object root and a union root are objects too
  admit_object_root(ToolEntry(
    "described",
    "",
    codec.DescribedSchema("A user", user_schema),
  ))
  |> should.equal([])
  let assert Ok(command_tool) =
    tool_entry("control", "Control the job", command_codec())
  admit_object_root(command_tool)
  |> should.equal([])

  // 2. Tool with scalar root schema is rejected by Relay/LLM profile
  let scalar_tool = ToolEntry("ping", "Ping", codec.StringSchema)
  admit_object_root(scalar_tool)
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
  let request_schema =
    codec.ObjectSchema([
      codec.PropertySchema(
        "request",
        True,
        codec.ObjectSchema([
          codec.PropertySchema("id", True, codec.IntegerRangeSchema(1, 10)),
          codec.PropertySchema(
            "labels",
            False,
            codec.ListSchema(codec.NullableSchema(codec.StringSchema)),
          ),
        ]),
      ),
    ])

  let reqs = extract_requirements(request_schema)

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
  let choice_schema =
    codec.UnionSchema([
      codec.VariantSchema("number", Some(codec.IntSchema)),
      codec.VariantSchema("text", Some(codec.StringSchema)),
      codec.VariantSchema("nothing", None),
    ])
  let choice_reqs = extract_requirements(choice_schema)

  let choice_issues = reject_feature(choice_reqs, TaggedAlternatives)
  choice_issues
  |> should.equal([UnsupportedFeature(Requirement([], TaggedAlternatives))])

  // A policy without unit variants finds each one by its tag
  let assert Ok(command_schema) = codec.schema(command_codec())
  reject_feature(extract_requirements(command_schema), UnitAlternative)
  |> should.equal([
    UnsupportedFeature(Requirement([TaggedCase("stop")], UnitAlternative)),
    UnsupportedFeature(Requirement([TaggedCase("restart")], UnitAlternative)),
  ])
}

pub fn structural_requirements_extraction_test() {
  // PairSchema
  extract_requirements(codec.PairSchema(codec.BoolSchema, codec.IntSchema))
  |> should.equal([
    Requirement([], ArrayValues),
    Requirement([], FixedTuple),
    Requirement([TupleIndex(0)], BooleanValues),
    Requirement([TupleIndex(1)], IntegerValues),
  ])

  // NullableSchema with IntegerRange
  extract_requirements(codec.NullableSchema(codec.IntegerRangeSchema(1, 10)))
  |> should.equal([
    Requirement([], NullableValues),
    Requirement([NonNullCase], IntegerValues),
    Requirement([NonNullCase], IntegerBounds(1, 10)),
  ])

  // UnionSchema with payload variants and a unit variant
  extract_requirements(
    codec.UnionSchema([
      codec.VariantSchema("small", Some(codec.IntegerRangeSchema(1, 2))),
      codec.VariantSchema("many", Some(codec.ListSchema(codec.StringSchema))),
      codec.VariantSchema("none", None),
    ]),
  )
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
  let assert Ok(command_schema) = codec.schema(command_codec())
  extract_requirements(command_schema)
  |> should.equal([
    Requirement([], ClosedObject),
    Requirement([], TaggedAlternatives),
    Requirement([TaggedCase("start"), Property("value")], IntegerValues),
    Requirement([TaggedCase("start"), Property("value")], IntegerBounds(0, 60)),
    Requirement([TaggedCase("stop")], UnitAlternative),
    Requirement([TaggedCase("restart")], UnitAlternative),
  ])

  // A described enum
  extract_requirements(codec.DescribedSchema(
    "Level",
    codec.StringEnumSchema(["low", "high"]),
  ))
  |> should.equal([Requirement([], StringEnumValues(["low", "high"]))])

  // NumberSchema and NumberRangeSchema
  let assert Ok(num0) = number.from_int(0)
  let assert Ok(num100) = number.from_int(100)
  extract_requirements(codec.NumberSchema)
  |> should.equal([Requirement([], ExactDecimalValues)])

  extract_requirements(codec.NumberRangeSchema(num0, num100))
  |> should.equal([
    Requirement([], ExactDecimalValues),
    Requirement([], DecimalBounds(num0, num100)),
  ])
}

pub fn exact_decimal_admission_distinction_test() {
  let assert Ok(num_min) = number.from_int(0)
  let assert Ok(num_max) = number.from_int(100)

  let int_schema = codec.IntSchema
  let number_schema = codec.NumberSchema
  let number_range_schema = codec.NumberRangeSchema(num_min, num_max)

  let int_reqs = extract_requirements(int_schema)
  let number_reqs = extract_requirements(number_schema)
  let number_range_reqs = extract_requirements(number_range_schema)

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

  // The codecs that produce these schemas
  codec.schema(codec.int()) |> should.equal(Ok(int_schema))
  codec.schema(codec.float()) |> should.equal(Ok(number_schema))
  codec.schema(codec.number()) |> should.equal(Ok(number_schema))
  codec.schema(codec.number_between(num_min, num_max))
  |> should.equal(Ok(number_range_schema))
}
