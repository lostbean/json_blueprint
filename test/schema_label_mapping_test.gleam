import gleam/option.{type Option}
import gleam/string
import gleeunit/should
import json/blueprint/codec
import json/blueprint/contract
import json/blueprint/value

type Choice {
  First
  Second
}

type Wrapped {
  Bare
  Chosen(Choice)
}

type Sample =
  #(
    Choice,
    Option(Choice),
    List(Choice),
    Option(Choice),
    #(Choice, Int),
    Wrapped,
  )

/// One codec shape with a string enumeration in every position that can hold
/// a child schema, built from the two labels and the two descriptions given.
fn sample(
  first: String,
  second: String,
  outer: String,
  inner: String,
) -> codec.Codec(Sample) {
  let choice = codec.string_enum([#(first, First), #(second, Second)])
  let wrapped =
    codec.union({
      use chosen <- codec.variant(
        "chosen",
        codec.describe(choice, inner),
        Chosen,
      )
      use bare <- codec.unit_variant("bare", Bare)
      codec.match(fn(item) {
        case item {
          Chosen(found) -> chosen(found)
          Bare -> bare
        }
      })
    })
  let record = {
    use required <- codec.field("choice", choice, get: fn(s: Sample) { s.0 })
    use optional <- codec.optional_field("maybe", choice, get: fn(s: Sample) {
      s.1
    })
    use many <- codec.field(
      "many",
      codec.describe(codec.list(choice), inner),
      get: fn(s: Sample) { s.2 },
    )
    use nullable <- codec.field(
      "nullable",
      codec.nullable(choice),
      get: fn(s: Sample) { s.3 },
    )
    use pair <- codec.field(
      "pair",
      codec.pair(choice, codec.integer_between(0, 9)),
      get: fn(s: Sample) { s.4 },
    )
    use wrapped <- codec.field("wrapped", wrapped, get: fn(s: Sample) { s.5 })
    codec.success(#(required, optional, many, nullable, pair, wrapped))
  }
  codec.describe(record, outer)
}

fn schema_of(codec: codec.Codec(a)) -> codec.Schema {
  let assert Ok(schema) = codec.schema(codec)
  schema
}

fn stand_in(label: String) -> String {
  case label {
    "id-7f3a" -> "stand-in-1"
    "id-c210" -> "stand-in-2"
    other -> other
  }
}

pub fn root_enumeration_equals_enum_of_mapped_labels_test() {
  let live = codec.string_enum([#("id-7f3a", First), #("id-c210", Second)])
  let stable =
    codec.string_enum([#("stand-in-1", First), #("stand-in-2", Second)])
  let assert Ok(mapped) = codec.map_enum_labels(schema_of(live), stand_in)
  mapped |> should.equal(schema_of(stable))
  codec.schema_value(mapped)
  |> value.to_string
  |> should.equal(value.to_string(codec.schema_value(schema_of(stable))))
  codec.view(mapped)
  |> should.equal(codec.StringEnumSchema(["stand-in-1", "stand-in-2"]))
}

pub fn every_nested_enumeration_is_mapped_test() {
  let live = sample("id-7f3a", "id-c210", "about id-7f3a", "one of id-c210")
  let stable =
    sample("stand-in-1", "stand-in-2", "about id-7f3a", "one of id-c210")
  let assert Ok(mapped) = codec.map_enum_labels(schema_of(live), stand_in)
  mapped |> should.equal(schema_of(stable))
  let assert Ok(expected) = codec.schema_json(stable)
  codec.schema_document(mapped) |> value.to_string |> should.equal(expected)
}

pub fn names_tags_and_descriptions_are_not_labels_test() {
  // The mapping would change every other string in the schema if it reached
  // them: a property is named "choice", a tag is "chosen".
  let live = sample("choice", "chosen", "choice", "chosen")
  let stable = sample("CHOICE", "CHOSEN", "choice", "chosen")
  let assert Ok(mapped) =
    codec.map_enum_labels(schema_of(live), string.uppercase)
  mapped |> should.equal(schema_of(stable))
}

pub fn identity_mapping_returns_the_same_schema_test() {
  let schema = schema_of(sample("a", "b", "outer", "inner"))
  codec.map_enum_labels(schema, fn(label) { label })
  |> should.equal(Ok(schema))
}

pub fn schema_without_enumerations_is_unchanged_test() {
  let schema =
    schema_of(codec.describe(codec.list(codec.string()), "some strings"))
  codec.map_enum_labels(schema, fn(_) { "x" }) |> should.equal(Ok(schema))
}

pub fn two_labels_mapped_to_one_string_is_a_definition_error_test() {
  let schema = schema_of(codec.string_enum([#("a", First), #("b", Second)]))
  codec.map_enum_labels(schema, fn(_) { "same" })
  |> should.equal(Error(codec.DuplicateEnumLabel("same")))
}

pub fn nested_collision_is_a_definition_error_test() {
  let schema = schema_of(sample("a", "b", "outer", "inner"))
  codec.map_enum_labels(schema, fn(_) { "same" })
  |> should.equal(Error(codec.DuplicateEnumLabel("same")))
}

pub fn label_mapped_onto_another_original_label_collides_test() {
  let schema = schema_of(codec.string_enum([#("a", First), #("b", Second)]))
  codec.map_enum_labels(schema, fn(label) {
    case label {
      "a" -> "b"
      other -> other
    }
  })
  |> should.equal(Error(codec.DuplicateEnumLabel("b")))
}

pub fn labels_may_swap_and_may_become_empty_test() {
  // The empty string is a JSON string and a valid label; the number of labels
  // never changes, so an enumeration cannot become empty.
  let schema = schema_of(codec.string_enum([#("a", First), #("b", Second)]))
  let assert Ok(mapped) =
    codec.map_enum_labels(schema, fn(label) {
      case label {
        "a" -> "b"
        _ -> ""
      }
    })
  mapped
  |> should.equal(schema_of(codec.string_enum([#("b", First), #("", Second)])))
}

pub fn mapped_schema_validates_mapped_documents_test() {
  let live = codec.list(codec.string_enum([#("id-7f3a", First)]))
  let assert Ok(mapped) = codec.map_enum_labels(schema_of(live), stand_in)
  let mapped_contract = contract.from_schema(mapped)
  let stable = value.Array([value.String("stand-in-1")])
  let original = value.Array([value.String("id-7f3a")])
  let assert Ok(validated) = contract.validate(mapped_contract, stable)
  contract.validate(mapped_contract, original) |> should.be_error
  // The codec is not mapped: it still reads and writes its own labels.
  codec.decode(live, original) |> should.equal(Ok([First]))
  contract.decode(live, validated)
  |> should.equal(Error(codec.DecodeError([], codec.ContractMismatch)))
}

pub fn every_description_is_mapped_and_nothing_else_test() {
  let rename = fn(text) { string.replace(text, "id-7f3a", "stand-in-1") }
  let live = sample("id-7f3a", "id-c210", "about id-7f3a", "one of id-7f3a")
  let stable =
    sample("id-7f3a", "id-c210", "about stand-in-1", "one of stand-in-1")
  let mapped = codec.map_descriptions(schema_of(live), rename)
  mapped |> should.equal(schema_of(stable))
  codec.description(mapped) |> should.equal(option.Some("about stand-in-1"))
  let assert Ok(expected) = codec.schema_json(stable)
  codec.schema_document(mapped) |> value.to_string |> should.equal(expected)
}

pub fn descriptions_and_labels_compose_test() {
  let live = sample("id-7f3a", "id-c210", "about id-7f3a", "one of id-c210")
  let stable =
    sample("stand-in-1", "stand-in-2", "about stand-in-1", "one of stand-in-2")
  let in_text = fn(text) {
    text
    |> string.replace("id-7f3a", "stand-in-1")
    |> string.replace("id-c210", "stand-in-2")
  }
  let assert Ok(mapped) =
    schema_of(live)
    |> codec.map_descriptions(in_text)
    |> codec.map_enum_labels(stand_in)
  mapped |> should.equal(schema_of(stable))
}
