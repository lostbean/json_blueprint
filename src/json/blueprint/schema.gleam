import gleam/bit_array
import gleam/crypto
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

pub const json_schema_version = "http://json-schema.org/draft-07/schema#"

/// Represents a complete JSON Schema document
pub type Schema {
  Schema(
    schema: SchemaDefinition,
    // Optional fields from draft 2020-12
    vocabulary: Option(List(String)),
    id: Option(String),
    comment: Option(String),
    defs: Option(List(#(String, SchemaDefinition))),
  )
}

// [... keep all previous type definitions ...]
/// Core schema definition that can be used recursively
pub type SchemaDefinition {
  // Type constraints
  Type(type_: SchemaType)
  Enum(values: List(json.Json), type_: Option(SchemaType))
  Const(value: json.Json)

  // Not required
  Nullable(schema: SchemaDefinition)

  // Not required
  Optional(schema: SchemaDefinition)

  // Numeric constraints
  Number(
    minimum: Option(Float),
    maximum: Option(Float),
    exclusive_minimum: Option(Float),
    exclusive_maximum: Option(Float),
    multiple_of: Option(Float),
  )

  // String constraints
  String(
    min_length: Option(Int),
    max_length: Option(Int),
    pattern: Option(String),
    format: Option(StringFormat),
  )

  // Array constraints
  Array(items: Option(SchemaDefinition))

  // Array constraints
  DetailedArray(
    items: Option(SchemaDefinition),
    prefix_items: Option(List(SchemaDefinition)),
    min_items: Option(Int),
    max_items: Option(Int),
    unique_items: Option(Bool),
    contains: Option(SchemaDefinition),
    min_contains: Option(Int),
    max_contains: Option(Int),
  )

  // Object constraints
  Object(
    properties: List(#(String, SchemaDefinition)),
    additional_properties: Option(Bool),
    required: Option(List(String)),
  )

  // Object constraints
  DetailedObject(
    properties: Option(List(#(String, SchemaDefinition))),
    pattern_properties: Option(List(#(String, SchemaDefinition))),
    additional_properties: Option(SchemaDefinition),
    required: Option(List(String)),
    property_names: Option(SchemaDefinition),
    min_properties: Option(Int),
    max_properties: Option(Int),
  )

  // Combination schemas
  AllOf(schemas: List(SchemaDefinition))
  AnyOf(schemas: List(SchemaDefinition))
  OneOf(schemas: List(SchemaDefinition))
  Not(schema: SchemaDefinition)

  // References
  Ref(ref: String)

  // Boolean schemas
  TrueValue
  FalseValue
}

/// Represents the allowed basic JSON Schema types
pub type SchemaType {
  Null
  BooleanType
  ObjectType
  ArrayType
  NumberType
  StringType
  IntegerType

  // Multiple types allowed
  Multiple(List(SchemaType))
}

/// Common string formats defined in the spec
pub type StringFormat {
  DateTime
  Date
  Time
  Duration
  Email
  IdnEmail
  Hostname
  IdnHostname
  Ipv4
  Ipv6
  Uri
  UriReference
  Iri
  IriReference
  UriTemplate
  JsonPointer
  RelativeJsonPointer
  Regex
}

/// Helper function to create a new schema with default values
pub fn new_schema(
  definition: SchemaDefinition,
  references: Option(List(#(String, SchemaDefinition))),
) -> Schema {
  Schema(
    schema: definition,
    vocabulary: None,
    id: None,
    comment: None,
    defs: references,
  )
}

/// Helper to create a basic type constraint
pub fn type_constraint(type_: SchemaType) -> SchemaDefinition {
  Type(type_)
}

/// Helper to create a string constraint
pub fn string_constraint(
  min_length min_length: Option(Int),
  max_length max_length: Option(Int),
  pattern pattern: Option(String),
  format format: Option(StringFormat),
) -> SchemaDefinition {
  String(
    min_length: min_length,
    max_length: max_length,
    pattern: pattern,
    format: format,
  )
}

/// Helper to create a number constraint
pub fn number_constraint(
  minimum minimum: Option(Float),
  maximum maximum: Option(Float),
  exclusive_minimum exclusive_minimum: Option(Float),
  exclusive_maximum exclusive_maximum: Option(Float),
  multiple_of multiple_of: Option(Float),
) -> SchemaDefinition {
  Number(
    minimum: minimum,
    maximum: maximum,
    exclusive_minimum: exclusive_minimum,
    exclusive_maximum: exclusive_maximum,
    multiple_of: multiple_of,
  )
}

/// Convert a Schema to JSON string
pub fn to_json_string(schema: Schema) -> String {
  schema
  |> to_json
  |> json.to_string
}

/// Convert a Schema to JSON value
pub fn to_json(schema: Schema) -> json.Json {
  // Add optional top-level fields
  let fields =
    [#("$schema", json.string(json_schema_version))]
    |> prepend_option(schema.vocabulary, "$vocabulary", fn(vocab) {
      json.array(vocab, json.string)
    })
    |> prepend_option(schema.id, "$id", json.string)
    |> prepend_option(schema.comment, "$comment", json.string)
    |> prepend_option(schema.defs, "$defs", fn(defs) {
      json.object(
        list.map(defs, fn(def) { #(def.0, schema_definition_to_json(def.1)) }),
      )
    })

  // Add the main schema definition
  let schema_fields = schema_definition_to_json_fields(schema.schema, False)
  let fields = list.append(fields, schema_fields)

  json.object(fields)
}

pub fn hash_schema_definition(def: SchemaDefinition) -> String {
  def
  |> schema_definition_to_json
  |> json.to_string
  |> bit_array.from_string
  |> crypto.hash(crypto.Sha1, _)
  |> bit_array.base16_encode
}

pub fn map_ref(
  def: SchemaDefinition,
  f: fn(String) -> String,
) -> SchemaDefinition {
  case def {
    Ref(ref) -> Ref(f(ref))
    Array(items) -> Array(option.map(items, fn(i) { map_ref(i, f) }))
    DetailedArray(
      items,
      prefix_items,
      min_items,
      max_items,
      unique_items,
      contains,
      min_contains,
      max_contains,
    ) ->
      DetailedArray(
        option.map(items, fn(i) { map_ref(i, f) }),
        option.map(prefix_items, fn(items) {
          list.map(items, fn(i) { map_ref(i, f) })
        }),
        min_items,
        max_items,
        unique_items,
        option.map(contains, fn(c) { map_ref(c, f) }),
        min_contains,
        max_contains,
      )
    Object(properties, additional_properties, required) ->
      Object(
        list.map(properties, fn(prop) { #(prop.0, map_ref(prop.1, f)) }),
        additional_properties,
        required,
      )
    DetailedObject(
      properties,
      pattern_properties,
      additional_properties,
      required,
      property_names,
      min_properties,
      max_properties,
    ) ->
      DetailedObject(
        option.map(properties, fn(props) {
          list.map(props, fn(prop) { #(prop.0, map_ref(prop.1, f)) })
        }),
        option.map(pattern_properties, fn(patterns) {
          list.map(patterns, fn(pattern) { #(pattern.0, map_ref(pattern.1, f)) })
        }),
        option.map(additional_properties, fn(props) { map_ref(props, f) }),
        required,
        option.map(property_names, fn(names) { map_ref(names, f) }),
        min_properties,
        max_properties,
      )
    AllOf(schemas) -> AllOf(list.map(schemas, fn(s) { map_ref(s, f) }))
    AnyOf(schemas) -> AnyOf(list.map(schemas, fn(s) { map_ref(s, f) }))
    OneOf(schemas) -> OneOf(list.map(schemas, fn(s) { map_ref(s, f) }))
    Not(schema) -> Not(map_ref(schema, f))
    Nullable(schema) -> Nullable(map_ref(schema, f))
    Optional(schema) -> Optional(map_ref(schema, f))
    _ -> def
  }
}

/// Convert a SchemaDefinition to JSON value
fn schema_definition_to_json(def: SchemaDefinition) -> json.Json {
  json.object(schema_definition_to_json_fields(def, False))
}

fn prepend_option(
  list: List(#(String, json.Json)),
  maybe: Option(a),
  name: String,
  to_json: fn(a) -> json.Json,
) -> List(#(String, json.Json)) {
  case maybe {
    option.Some(value) -> {
      list.prepend(list, #(name, to_json(value)))
    }
    None -> list
  }
}

/// Convert a SchemaDefinition to a list of JSON fields
fn schema_definition_to_json_fields(
  def: SchemaDefinition,
  make_type_nullable: Bool,
) -> List(#(String, json.Json)) {
  let with_nullable_type = fn(type_) {
    case make_type_nullable {
      False -> schema_type_to_json(type_)
      True -> schema_type_to_json(Multiple([type_, Null]))
    }
  }

  case def {
    Type(type_) -> [#("type", with_nullable_type(type_))]

    Enum(values, schema) ->
      [#("enum", json.preprocessed_array(values))]
      |> prepend_option(schema, "type", with_nullable_type)

    Const(value) -> [#("const", value)]

    Nullable(schema) -> schema_definition_to_json_fields(schema, True)

    Optional(schema) ->
      schema_definition_to_json_fields(schema, make_type_nullable)

    Number(minimum, maximum, exclusive_minimum, exclusive_maximum, multiple_of) -> {
      [#("type", with_nullable_type(NumberType))]
      |> prepend_option(minimum, "minimum", json.float)
      |> prepend_option(maximum, "maximum", json.float)
      |> prepend_option(exclusive_minimum, "exclusiveMinimum", json.float)
      |> prepend_option(exclusive_maximum, "exclusiveMaximum", json.float)
      |> prepend_option(multiple_of, "multipleOf", json.float)
    }

    String(min_length, max_length, pattern, format) -> {
      [#("type", with_nullable_type(StringType))]
      |> prepend_option(min_length, "minLength", json.int)
      |> prepend_option(max_length, "maxLength", json.int)
      |> prepend_option(pattern, "pattern", json.string)
      |> prepend_option(format, "format", fn(f) {
        json.string(string_format_to_string(f))
      })
    }

    Array(items) -> {
      [#("type", with_nullable_type(ArrayType))]
      |> prepend_option(items, "items", fn(schema) {
        schema_definition_to_json(schema)
      })
    }

    Object(properties, additional_properties, required) -> {
      [
        #("type", with_nullable_type(ObjectType)),
        #(
          "properties",
          json.object(
            list.map(properties, fn(prop) {
              #(prop.0, schema_definition_to_json(prop.1))
            }),
          ),
        ),
      ]
      |> prepend_option(
        additional_properties,
        "additionalProperties",
        json.bool,
      )
      |> prepend_option(required, "required", json.array(_, json.string))
    }

    DetailedArray(
      items,
      prefix_items,
      min_items,
      max_items,
      unique_items,
      contains,
      min_contains,
      max_contains,
    ) -> {
      [#("type", with_nullable_type(ArrayType))]
      |> prepend_option(items, "items", fn(schema) {
        schema_definition_to_json(schema)
      })
      |> prepend_option(prefix_items, "prefixItems", fn(schemas) {
        json.array(schemas, schema_definition_to_json)
      })
      |> prepend_option(min_items, "minItems", json.int)
      |> prepend_option(max_items, "maxItems", json.int)
      |> prepend_option(unique_items, "uniqueItems", json.bool)
      |> prepend_option(contains, "contains", fn(schema) {
        schema_definition_to_json(schema)
      })
      |> prepend_option(min_contains, "minContains", json.int)
      |> prepend_option(max_contains, "maxContains", json.int)
    }

    DetailedObject(
      properties,
      pattern_properties,
      additional_properties,
      required,
      property_names,
      min_properties,
      max_properties,
    ) -> {
      [#("type", with_nullable_type(ObjectType))]
      |> prepend_option(properties, "properties", fn(props) {
        json.object(
          list.map(props, fn(prop) {
            #(prop.0, schema_definition_to_json(prop.1))
          }),
        )
      })
      |> prepend_option(pattern_properties, "patternProperties", fn(patterns) {
        json.object(
          list.map(patterns, fn(pattern) {
            #(pattern.0, schema_definition_to_json(pattern.1))
          }),
        )
      })
      |> prepend_option(
        additional_properties,
        "additionalProperties",
        fn(schema) { schema_definition_to_json(schema) },
      )
      |> prepend_option(required, "required", fn(reqs) {
        json.array(reqs, json.string)
      })
      |> prepend_option(property_names, "propertyNames", fn(schema) {
        schema_definition_to_json(schema)
      })
      |> prepend_option(min_properties, "minProperties", json.int)
      |> prepend_option(max_properties, "maxProperties", json.int)
    }

    AllOf(schemas) -> [
      #("allOf", json.array(schemas, schema_definition_to_json)),
    ]
    AnyOf(schemas) -> [
      #("anyOf", json.array(schemas, schema_definition_to_json)),
    ]
    OneOf(schemas) -> [
      #("oneOf", json.array(schemas, schema_definition_to_json)),
    ]
    Not(schema) -> [#("not", schema_definition_to_json(schema))]

    Ref(ref) ->
      case make_type_nullable {
        False -> [#("$ref", json.string(ref))]
        True ->
          schema_definition_to_json_fields(AnyOf([Ref(ref), Type(Null)]), False)
      }

    TrueValue -> [#("type", json.bool(True))]
    FalseValue -> [#("type", json.bool(False))]
  }
}

/// Convert a SchemaType to JSON value
fn schema_type_to_json(type_: SchemaType) -> json.Json {
  case type_ {
    Null -> json.string("null")
    BooleanType -> json.string("boolean")
    ObjectType -> json.string("object")
    ArrayType -> json.string("array")
    NumberType -> json.string("number")
    StringType -> json.string("string")
    IntegerType -> json.string("integer")
    Multiple(types) -> json.array(types, fn(t) { schema_type_to_json(t) })
  }
}

/// Convert a StringFormat to string
fn string_format_to_string(format: StringFormat) -> String {
  case format {
    DateTime -> "date-time"
    Date -> "date"
    Time -> "time"
    Duration -> "duration"
    Email -> "email"
    IdnEmail -> "idn-email"
    Hostname -> "hostname"
    IdnHostname -> "idn-hostname"
    Ipv4 -> "ipv4"
    Ipv6 -> "ipv6"
    Uri -> "uri"
    UriReference -> "uri-reference"
    Iri -> "iri"
    IriReference -> "iri-reference"
    UriTemplate -> "uri-template"
    JsonPointer -> "json-pointer"
    RelativeJsonPointer -> "relative-json-pointer"
    Regex -> "regex"
  }
}
