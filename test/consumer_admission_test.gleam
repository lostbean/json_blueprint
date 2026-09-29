import gleam/list
import gleeunit/should
import json/blueprint/codec.{type Schema}
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
    codec.FieldSchema(name, inner) -> [
      Requirement(path, ClosedObject),
      ..at(inner, list.append(path, [Property(name)]))
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
    codec.TaggedSchema(left_tag, left, right_tag, right) -> [
      Requirement(path, ClosedObject),
      Requirement(path, TaggedAlternatives),
      ..list.append(
        at(left, list.append(path, [TaggedCase(left_tag), Property("value")])),
        at(right, list.append(path, [TaggedCase(right_tag), Property("value")])),
      )
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

pub fn admit_object_root(entry: ToolEntry) -> List(AdmissionIssue) {
  case entry.schema {
    codec.FieldSchema(_, _)
    | codec.ObjectSchema(_)
    | codec.TaggedSchema(_, _, _, _) -> []
    _ -> [RootMustBeObject]
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

  // 2. Tool with scalar root schema is rejected by Relay/LLM profile
  let scalar_tool = ToolEntry("ping", "Ping", codec.StringSchema)
  admit_object_root(scalar_tool)
  |> should.equal([RootMustBeObject])

  // 3. Custom codec with UnknownSchema returns error on entry construction
  let custom_codec =
    codec.new(
      fn(i: Int) {
        let assert Ok(num) = number.from_int(i)
        Ok(value.Number(num))
      },
      fn(_) { Ok(1) },
    )
  codec.schema(custom_codec)
  |> should.equal(Error(codec.UnknownSchema))
}

pub fn fabric_schema_admission_policies_test() {
  // Tool schema with an optional property
  let request_schema =
    codec.FieldSchema(
      "request",
      codec.ObjectSchema([
        codec.PropertySchema("id", True, codec.IntegerRangeSchema(1, 10)),
        codec.PropertySchema(
          "labels",
          False,
          codec.ListSchema(codec.NullableSchema(codec.StringSchema)),
        ),
      ]),
    )

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
    codec.TaggedSchema("number", codec.IntSchema, "text", codec.StringSchema)
  let choice_reqs = extract_requirements(choice_schema)

  let choice_issues = reject_feature(choice_reqs, TaggedAlternatives)
  choice_issues
  |> should.equal([
    UnsupportedFeature(Requirement([], TaggedAlternatives)),
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

  // TaggedSchema
  extract_requirements(codec.TaggedSchema(
    "small",
    codec.IntegerRangeSchema(1, 2),
    "many",
    codec.ListSchema(codec.StringSchema),
  ))
  |> should.equal([
    Requirement([], ClosedObject),
    Requirement([], TaggedAlternatives),
    Requirement([TaggedCase("small"), Property("value")], IntegerValues),
    Requirement([TaggedCase("small"), Property("value")], IntegerBounds(1, 2)),
    Requirement([TaggedCase("many"), Property("value")], ArrayValues),
    Requirement([TaggedCase("many"), Property("value"), Element], TextValues),
  ])

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
}
