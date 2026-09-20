import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import json/blueprint/codec
import json/blueprint/internal/schema_materialize
import json/blueprint/number

// Inspectable definitions for primitives, bounded integers, pairs, lists,
// nullable/optional fields, objects, enums, and named imap mappings.
// Opaque arbitrary Codec closures are intentionally not accepted as compiler
// input because Gleam cannot inspect their source.
pub opaque type Definition(a) {
  Definition(
    codec: codec.Codec(a),
    gleam_type: String,
    lower: fn(String) -> Lowered,
  )
}

pub opaque type Properties(a) {
  Properties(
    value: codec.Properties(a),
    gleam_type: String,
    names: List(String),
    lower: fn(String) -> LoweredProperties,
  )
}

// Gleam cannot recover a source name from a function value. The caller pairs
// runtime functions with their fully qualified names. Generated compilation
// type-checks the referenced functions, and parity tests check agreement, but
// a same-typed mismatch between either callback and its reference is trusted.
pub opaque type Mapping(a, b) {
  Mapping(
    from: fn(a) -> b,
    to: fn(b) -> a,
    from_reference: String,
    to_reference: String,
  )
}

pub opaque type EnumVariant(a) {
  EnumVariant(label: String, value: a, reference: String)
}

pub type GeneratedModule {
  GeneratedModule(path: String, content: String, fingerprint: String)
}

pub type CompileError {
  InvalidCodecName(String, String)
  InvalidModulePath(String, String)
  InvalidTypeReference(String)
  MissingTypeImport(String)
  InvalidFunctionReference(String)
  ConflictingImportAlias(String, String, String)
  DuplicateSchemaAccessor(String)
  UnsupportedSchemaConstructor(List(String), String)
  NativeNumberUnsupported
  InvalidEnum(codec.EnumError)
  UnknownSchema(String)
}

type Lowered {
  Lowered(
    encoder: String,
    decoder: String,
    native_encoder: String,
    native_decoder: String,
    native_supported: Bool,
    declarations: List(String),
    imports: List(String),
  )
}

type LoweredProperties {
  LoweredProperties(
    encoder: String,
    decoder: String,
    native_encoder: String,
    native_decoder: String,
    native_supported: Bool,
    declarations: List(String),
    imports: List(String),
  )
}

pub fn named_mapping(
  from: fn(a) -> b,
  from_reference: String,
  to: fn(b) -> a,
  to_reference: String,
) -> Result(Mapping(a, b), CompileError) {
  case
    parse_function_reference(from_reference),
    parse_function_reference(to_reference)
  {
    Ok(_), Ok(_) -> Ok(Mapping(from, to, from_reference, to_reference))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

pub fn enum_variant(
  label: String,
  value: a,
  reference: String,
) -> Result(EnumVariant(a), CompileError) {
  case parse_constructor_reference(reference) {
    Ok(_) -> Ok(EnumVariant(label, value, reference))
    Error(error) -> Error(error)
  }
}

pub fn string() -> Definition(String) {
  Definition(codec.string(), "String", fn(prefix) {
    Lowered(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: True,
      declarations: [
        "fn "
          <> prefix
          <> "_encode(item: String) -> Result(value.Value, codec.EncodeError) {\n"
          <> "  codec.encode_string_value(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(String, codec.DecodeError) {\n"
          <> "  codec.decode_string_value(raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: String) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  Ok(json.string(item))\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(String, codec.DecodeError) {\n"
          <> "  codec.decode_native_string(raw)\n}",
      ],
      imports: ["gleam/dynamic"],
    )
  })
}

pub fn int() -> Definition(Int) {
  Definition(codec.int(), "Int", fn(prefix) {
    Lowered(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: True,
      declarations: [
        "fn "
          <> prefix
          <> "_encode(item: Int) -> Result(value.Value, codec.EncodeError) {\n"
          <> "  codec.encode_int_value(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(Int, codec.DecodeError) {\n"
          <> "  codec.decode_int_value(raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: Int) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  codec.encode_native_int(item)\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(Int, codec.DecodeError) {\n"
          <> "  codec.decode_native_int(raw)\n}",
      ],
      imports: ["gleam/dynamic"],
    )
  })
}

pub fn number() -> Definition(number.Number) {
  Definition(codec.number(), "number.Number", fn(prefix) {
    Lowered(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: False,
      declarations: [
        "fn "
          <> prefix
          <> "_encode(item: number.Number) -> Result(value.Value, codec.EncodeError) {\n"
          <> "  codec.encode_number_value(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(number.Number, codec.DecodeError) {\n"
          <> "  codec.decode_number_value(raw)\n}",
      ],
      imports: ["json/blueprint/number"],
    )
  })
}

pub fn bool() -> Definition(Bool) {
  Definition(codec.bool(), "Bool", fn(prefix) {
    Lowered(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: True,
      declarations: [
        "fn "
          <> prefix
          <> "_encode(item: Bool) -> Result(value.Value, codec.EncodeError) {\n"
          <> "  codec.encode_bool_value(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(Bool, codec.DecodeError) {\n"
          <> "  codec.decode_bool_value(raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: Bool) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  Ok(json.bool(item))\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(Bool, codec.DecodeError) {\n"
          <> "  codec.decode_native_bool(raw)\n}",
      ],
      imports: ["gleam/dynamic"],
    )
  })
}

pub fn integer_between(
  min: Int,
  max: Int,
) -> Result(Definition(Int), codec.ConstraintError) {
  case codec.integer_between(min, max) {
    Error(error) -> Error(error)
    Ok(runtime_codec) ->
      Ok(
        Definition(runtime_codec, "Int", fn(prefix) {
          Lowered(
            encoder: prefix <> "_encode",
            decoder: prefix <> "_decode",
            native_encoder: prefix <> "_native_encode",
            native_decoder: prefix <> "_native_decode",
            native_supported: True,
            declarations: [
              "fn "
                <> prefix
                <> "_encode(item: Int) -> Result(value.Value, codec.EncodeError) {\n"
                <> "  codec.encode_integer_between_value("
                <> schema_materialize.format_int_literal(min)
                <> ", "
                <> schema_materialize.format_int_literal(max)
                <> ", item)\n}",
              "fn "
                <> prefix
                <> "_decode(raw: value.Value) -> Result(Int, codec.DecodeError) {\n"
                <> "  codec.decode_integer_between_value("
                <> schema_materialize.format_int_literal(min)
                <> ", "
                <> schema_materialize.format_int_literal(max)
                <> ", raw)\n}",
              "fn "
                <> prefix
                <> "_native_encode(item: Int) -> Result(json.Json, codec.EncodeError) {\n"
                <> "  codec.encode_native_integer_between("
                <> schema_materialize.format_int_literal(min)
                <> ", "
                <> schema_materialize.format_int_literal(max)
                <> ", item)\n}",
              "fn "
                <> prefix
                <> "_native_decode(raw: dynamic.Dynamic) -> Result(Int, codec.DecodeError) {\n"
                <> "  case codec.decode_native_int(raw) {\n    Error(error) -> Error(error)\n    Ok(item) if item >= "
                <> schema_materialize.format_int_literal(min)
                <> " && item <= "
                <> schema_materialize.format_int_literal(max)
                <> " -> Ok(item)\n    Ok(item) -> Error(codec.CannotDecode(codec.DecodeIntegerOutsideRange("
                <> schema_materialize.format_int_literal(min)
                <> ", "
                <> schema_materialize.format_int_literal(max)
                <> ", item)))\n  }\n}",
            ],
            imports: ["gleam/dynamic"],
          )
        }),
      )
  }
}

pub fn pair(left: Definition(a), right: Definition(b)) -> Definition(#(a, b)) {
  let Definition(left_codec, left_type, lower_left) = left
  let Definition(right_codec, right_type, lower_right) = right
  Definition(
    codec.pair(left_codec, right_codec),
    "#(" <> left_type <> ", " <> right_type <> ")",
    fn(prefix) {
      let left_lowered = lower_left(prefix <> "_left")
      let right_lowered = lower_right(prefix <> "_right")
      Lowered(
        encoder: prefix <> "_encode",
        decoder: prefix <> "_decode",
        native_encoder: prefix <> "_native_encode",
        native_decoder: prefix <> "_native_decode",
        native_supported: left_lowered.native_supported
          && right_lowered.native_supported,
        declarations: list.append(
          lower_declarations(left_lowered),
          list.append(lower_declarations(right_lowered), [
            "fn "
              <> prefix
              <> "_encode(item: #("
              <> left_type
              <> ", "
              <> right_type
              <> ")) -> Result(value.Value, codec.EncodeError) {\n"
              <> "  codec.encode_pair_with("
              <> lower_encoder(left_lowered)
              <> ", "
              <> lower_encoder(right_lowered)
              <> ", item)\n}",
            "fn "
              <> prefix
              <> "_decode(raw: value.Value) -> Result(#("
              <> left_type
              <> ", "
              <> right_type
              <> "), codec.DecodeError) {\n  codec.decode_pair_with("
              <> lower_decoder(left_lowered)
              <> ", "
              <> lower_decoder(right_lowered)
              <> ", raw)\n}",
            "fn "
              <> prefix
              <> "_native_encode(item: #("
              <> left_type
              <> ", "
              <> right_type
              <> ")) -> Result(json.Json, codec.EncodeError) {\n"
              <> "  codec.encode_native_pair_with("
              <> lower_native_encoder(left_lowered)
              <> ", "
              <> lower_native_encoder(right_lowered)
              <> ", item)\n}",
            "fn "
              <> prefix
              <> "_native_decode(raw: dynamic.Dynamic) -> Result(#("
              <> left_type
              <> ", "
              <> right_type
              <> "), codec.DecodeError) {\n"
              <> "  codec.decode_native_pair_with("
              <> lower_native_decoder(left_lowered)
              <> ", "
              <> lower_native_decoder(right_lowered)
              <> ", raw)\n}",
          ]),
        ),
        imports: list.append(
          lower_imports(left_lowered),
          lower_imports(right_lowered),
        ),
      )
    },
  )
}

pub fn list(inner: Definition(a)) -> Definition(List(a)) {
  let Definition(inner_codec, inner_type, lower_inner) = inner
  Definition(codec.list(inner_codec), "List(" <> inner_type <> ")", fn(prefix) {
    let inner_lowered = lower_inner(prefix <> "_item")
    Lowered(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: inner_lowered.native_supported,
      declarations: list.append(lower_declarations(inner_lowered), [
        "fn "
          <> prefix
          <> "_encode(items: List("
          <> inner_type
          <> ")) -> Result(value.Value, codec.EncodeError) {\n"
          <> "  codec.encode_list_with("
          <> lower_encoder(inner_lowered)
          <> ", items)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(List("
          <> inner_type
          <> "), codec.DecodeError) {\n"
          <> "  codec.decode_list_with("
          <> lower_decoder(inner_lowered)
          <> ", raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(items: List("
          <> inner_type
          <> ")) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  codec.encode_native_list_with("
          <> lower_native_encoder(inner_lowered)
          <> ", items)\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(List("
          <> inner_type
          <> "), codec.DecodeError) {\n"
          <> "  codec.decode_native_list_with("
          <> lower_native_decoder(inner_lowered)
          <> ", raw)\n}",
      ]),
      imports: lower_imports(inner_lowered),
    )
  })
}

pub fn nullable(inner: Definition(a)) -> Definition(codec.Nullable(a)) {
  let Definition(inner_codec, inner_type, lower_inner) = inner
  Definition(
    codec.nullable(inner_codec),
    "codec.Nullable(" <> inner_type <> ")",
    fn(prefix) {
      let inner_lowered = lower_inner(prefix <> "_inner")
      Lowered(
        encoder: prefix <> "_encode",
        decoder: prefix <> "_decode",
        native_encoder: prefix <> "_native_encode",
        native_decoder: prefix <> "_native_decode",
        native_supported: inner_lowered.native_supported,
        declarations: list.append(lower_declarations(inner_lowered), [
          "fn "
            <> prefix
            <> "_encode(item: codec.Nullable("
            <> inner_type
            <> ")) -> Result(value.Value, codec.EncodeError) {\n"
            <> "  codec.encode_nullable_with("
            <> lower_encoder(inner_lowered)
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_decode(raw: value.Value) -> Result(codec.Nullable("
            <> inner_type
            <> "), codec.DecodeError) {\n"
            <> "  codec.decode_nullable_with("
            <> lower_decoder(inner_lowered)
            <> ", raw)\n}",
          "fn "
            <> prefix
            <> "_native_encode(item: codec.Nullable("
            <> inner_type
            <> ")) -> Result(json.Json, codec.EncodeError) {\n"
            <> "  codec.encode_native_nullable_with("
            <> lower_native_encoder(inner_lowered)
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_native_decode(raw: dynamic.Dynamic) -> Result(codec.Nullable("
            <> inner_type
            <> "), codec.DecodeError) {\n"
            <> "  codec.decode_native_nullable_with("
            <> lower_native_decoder(inner_lowered)
            <> ", raw)\n}",
        ]),
        imports: lower_imports(inner_lowered),
      )
    },
  )
}

pub fn string_enum(
  type_name: String,
  variants: List(EnumVariant(a)),
) -> Result(Definition(a), CompileError) {
  case parse_type_reference(type_name) {
    Error(error) -> Error(error)
    Ok(_) -> {
      let runtime_variants =
        list.map(variants, fn(variant) {
          let EnumVariant(label, item, _) = variant
          #(label, item)
        })
      case codec.string_enum(runtime_variants) {
        Error(error) -> Error(InvalidEnum(error))
        Ok(runtime_codec) ->
          Ok(
            Definition(runtime_codec, type_name, fn(prefix) {
              let encoder_arms = emit_enum_encoder_arms(variants, [])
              let decoder_arms = emit_enum_decoder_arms(variants, [])
              let native_encoder_arms =
                emit_native_enum_encoder_arms(variants, [])
              let native_decoder_arms =
                emit_native_enum_decoder_arms(variants, [])
              let imports =
                list.map(variants, fn(variant) {
                  let EnumVariant(_, _, reference) = variant
                  reference_module_unchecked(reference)
                })
              Lowered(
                encoder: prefix <> "_encode",
                decoder: prefix <> "_decode",
                native_encoder: prefix <> "_native_encode",
                native_decoder: prefix <> "_native_decode",
                native_supported: True,
                declarations: [
                  "fn "
                    <> prefix
                    <> "_encode(item: "
                    <> type_name
                    <> ") -> Result(value.Value, codec.EncodeError) {\n  case item {\n"
                    <> string.join(encoder_arms, "\n")
                    <> "\n    _ -> Error(codec.CannotEncode(codec.EncodeUnknownEnumValue(\"Value is not in the string enum\")))\n  }\n}",
                  "fn "
                    <> prefix
                    <> "_decode(raw: value.Value) -> Result("
                    <> type_name
                    <> ", codec.DecodeError) {\n  case raw {\n"
                    <> "    value.String(label) -> case label {\n"
                    <> string.join(decoder_arms, "\n")
                    <> "\n      _ -> Error(codec.CannotDecode(codec.DecodeUnknownEnumLabel(label)))\n    }\n"
                    <> "    _ -> Error(codec.CannotDecode(codec.DecodeExpectedString))\n  }\n}",
                  "fn "
                    <> prefix
                    <> "_native_encode(item: "
                    <> type_name
                    <> ") -> Result(json.Json, codec.EncodeError) {\n  case item {\n"
                    <> string.join(native_encoder_arms, "\n")
                    <> "\n    _ -> Error(codec.CannotEncode(codec.EncodeUnknownEnumValue(\"Value is not in the string enum\")))\n  }\n}",
                  "fn "
                    <> prefix
                    <> "_native_decode(raw: dynamic.Dynamic) -> Result("
                    <> type_name
                    <> ", codec.DecodeError) {\n"
                    <> "  case codec.decode_native_string(raw) {\n"
                    <> "    Error(error) -> Error(error)\n"
                    <> "    Ok(label) -> case label {\n"
                    <> string.join(native_decoder_arms, "\n")
                    <> "\n      _ -> Error(codec.CannotDecode(codec.DecodeUnknownEnumLabel(label)))\n    }\n  }\n}",
                ],
                imports: ["gleam/dynamic", ..imports],
              )
            }),
          )
      }
    }
  }
}

pub fn required(name: String, inner: Definition(a)) -> Properties(a) {
  let Definition(inner_codec, inner_type, lower_inner) = inner
  Properties(codec.required(name, inner_codec), inner_type, [name], fn(prefix) {
    let inner_lowered = lower_inner(prefix <> "_value")
    LoweredProperties(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: inner_lowered.native_supported,
      declarations: list.append(lower_declarations(inner_lowered), [
        "fn "
          <> prefix
          <> "_encode(item: "
          <> inner_type
          <> ") -> Result(List(#(String, value.Value)), codec.EncodeError) {\n"
          <> "  codec.encode_required_property_with("
          <> schema_materialize.escape_string_literal(name)
          <> ", "
          <> lower_encoder(inner_lowered)
          <> ", item)\n}",
        "fn "
          <> prefix
          <> "_decode(fields: List(#(String, value.Value))) -> Result("
          <> inner_type
          <> ", codec.DecodeError) {\n"
          <> "  codec.decode_required_property_with("
          <> schema_materialize.escape_string_literal(name)
          <> ", fields, "
          <> lower_decoder(inner_lowered)
          <> ")\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: "
          <> inner_type
          <> ") -> Result(List(#(String, json.Json)), codec.EncodeError) {\n"
          <> "  codec.encode_native_required_property_with("
          <> schema_materialize.escape_string_literal(name)
          <> ", "
          <> lower_native_encoder(inner_lowered)
          <> ", item)\n}",
        "fn "
          <> prefix
          <> "_native_decode(fields: dict.Dict(String, dynamic.Dynamic)) -> Result("
          <> inner_type
          <> ", codec.DecodeError) {\n"
          <> "  codec.decode_native_required_property_with("
          <> schema_materialize.escape_string_literal(name)
          <> ", fields, "
          <> lower_native_decoder(inner_lowered)
          <> ")\n}",
      ]),
      imports: ["gleam/dict", "gleam/dynamic", ..lower_imports(inner_lowered)],
    )
  })
}

pub fn optional(
  name: String,
  inner: Definition(a),
) -> Properties(codec.Optional(a)) {
  let Definition(inner_codec, inner_type, lower_inner) = inner
  let optional_type = "codec.Optional(" <> inner_type <> ")"
  Properties(
    codec.optional(name, inner_codec),
    optional_type,
    [name],
    fn(prefix) {
      let inner_lowered = lower_inner(prefix <> "_value")
      LoweredProperties(
        encoder: prefix <> "_encode",
        decoder: prefix <> "_decode",
        native_encoder: prefix <> "_native_encode",
        native_decoder: prefix <> "_native_decode",
        native_supported: inner_lowered.native_supported,
        declarations: list.append(lower_declarations(inner_lowered), [
          "fn "
            <> prefix
            <> "_encode(item: "
            <> optional_type
            <> ") -> Result(List(#(String, value.Value)), codec.EncodeError) {\n"
            <> "  codec.encode_optional_property_with("
            <> schema_materialize.escape_string_literal(name)
            <> ", "
            <> lower_encoder(inner_lowered)
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_decode(fields: List(#(String, value.Value))) -> Result("
            <> optional_type
            <> ", codec.DecodeError) {\n"
            <> "  codec.decode_optional_property_with("
            <> schema_materialize.escape_string_literal(name)
            <> ", fields, "
            <> lower_decoder(inner_lowered)
            <> ")\n}",
          "fn "
            <> prefix
            <> "_native_encode(item: "
            <> optional_type
            <> ") -> Result(List(#(String, json.Json)), codec.EncodeError) {\n"
            <> "  codec.encode_native_optional_property_with("
            <> schema_materialize.escape_string_literal(name)
            <> ", "
            <> lower_native_encoder(inner_lowered)
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_native_decode(fields: dict.Dict(String, dynamic.Dynamic)) -> Result("
            <> optional_type
            <> ", codec.DecodeError) {\n"
            <> "  codec.decode_native_optional_property_with("
            <> schema_materialize.escape_string_literal(name)
            <> ", fields, "
            <> lower_native_decoder(inner_lowered)
            <> ")\n}",
        ]),
        imports: ["gleam/dict", "gleam/dynamic", ..lower_imports(inner_lowered)],
      )
    },
  )
}

pub fn combine(
  left: Properties(a),
  right: Properties(b),
) -> Result(Properties(#(a, b)), codec.PropertyError) {
  let Properties(left_value, left_type, left_names, lower_left) = left
  let Properties(right_value, right_type, right_names, lower_right) = right
  case codec.combine(left_value, right_value) {
    Error(error) -> Error(error)
    Ok(value) ->
      Ok(
        Properties(
          value,
          "#(" <> left_type <> ", " <> right_type <> ")",
          list.append(left_names, right_names),
          fn(prefix) {
            let left_lowered = lower_left(prefix <> "_left")
            let right_lowered = lower_right(prefix <> "_right")
            LoweredProperties(
              encoder: prefix <> "_encode",
              decoder: prefix <> "_decode",
              native_encoder: prefix <> "_native_encode",
              native_decoder: prefix <> "_native_decode",
              native_supported: left_lowered.native_supported
                && right_lowered.native_supported,
              declarations: list.append(
                lower_property_declarations(left_lowered),
                list.append(lower_property_declarations(right_lowered), [
                  "fn "
                    <> prefix
                    <> "_encode(item: #("
                    <> left_type
                    <> ", "
                    <> right_type
                    <> ")) -> Result(List(#(String, value.Value)), codec.EncodeError) {\n"
                    <> "  codec.encode_properties_pair_with("
                    <> lower_property_encoder(left_lowered)
                    <> ", "
                    <> lower_property_encoder(right_lowered)
                    <> ", item)\n}",
                  "fn "
                    <> prefix
                    <> "_decode(fields: List(#(String, value.Value))) -> Result(#("
                    <> left_type
                    <> ", "
                    <> right_type
                    <> "), codec.DecodeError) {\n  codec.decode_properties_pair_with("
                    <> lower_property_decoder(left_lowered)
                    <> ", "
                    <> lower_property_decoder(right_lowered)
                    <> ", fields)\n}",
                  "fn "
                    <> prefix
                    <> "_native_encode(item: #("
                    <> left_type
                    <> ", "
                    <> right_type
                    <> ")) -> Result(List(#(String, json.Json)), codec.EncodeError) {\n"
                    <> "  codec.encode_native_properties_pair_with("
                    <> lower_property_native_encoder(left_lowered)
                    <> ", "
                    <> lower_property_native_encoder(right_lowered)
                    <> ", item)\n}",
                  "fn "
                    <> prefix
                    <> "_native_decode(fields: dict.Dict(String, dynamic.Dynamic)) -> Result(#("
                    <> left_type
                    <> ", "
                    <> right_type
                    <> "), codec.DecodeError) {\n"
                    <> "  codec.decode_native_properties_pair_with("
                    <> lower_property_native_decoder(left_lowered)
                    <> ", "
                    <> lower_property_native_decoder(right_lowered)
                    <> ", fields)\n}",
                ]),
              ),
              imports: list.append(
                lower_property_imports(left_lowered),
                lower_property_imports(right_lowered),
              ),
            )
          },
        ),
      )
  }
}

pub fn object(properties: Properties(a)) -> Definition(a) {
  let Properties(runtime_properties, object_type, names, lower_props) =
    properties
  Definition(codec.object(runtime_properties), object_type, fn(prefix) {
    let lowered = lower_props(prefix <> "_properties")
    let names_name = prefix <> "_property_names"
    Lowered(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: lowered.native_supported,
      declarations: [
        "const " <> names_name <> ": List(String) = " <> emit_string_list(names),
        ..list.append(lower_property_declarations(lowered), [
          "fn "
            <> prefix
            <> "_encode(item: "
            <> object_type
            <> ") -> Result(value.Value, codec.EncodeError) {\n"
            <> "  codec.encode_object_with("
            <> lower_property_encoder(lowered)
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_decode(raw: value.Value) -> Result("
            <> object_type
            <> ", codec.DecodeError) {\n"
            <> "  codec.decode_object_with("
            <> names_name
            <> ", "
            <> lower_property_decoder(lowered)
            <> ", raw)\n}",
          "fn "
            <> prefix
            <> "_native_encode(item: "
            <> object_type
            <> ") -> Result(json.Json, codec.EncodeError) {\n"
            <> "  codec.encode_native_object_with("
            <> lower_property_native_encoder(lowered)
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_native_decode(raw: dynamic.Dynamic) -> Result("
            <> object_type
            <> ", codec.DecodeError) {\n"
            <> "  codec.decode_native_object_with("
            <> names_name
            <> ", "
            <> lower_property_native_decoder(lowered)
            <> ", raw)\n}",
        ])
      ],
      imports: lower_property_imports(lowered),
    )
  })
}

pub fn imap(
  inner: Definition(a),
  output_type: String,
  mapping: Mapping(a, b),
) -> Result(Definition(b), CompileError) {
  case parse_type_reference(output_type) {
    Error(error) -> Error(error)
    Ok(_) -> {
      let Definition(inner_codec, _, lower_inner) = inner
      let Mapping(from, to, from_reference, to_reference) = mapping
      Ok(
        Definition(codec.imap(inner_codec, from, to), output_type, fn(prefix) {
          let inner_lowered = lower_inner(prefix <> "_inner")
          let from_expr = normalize_reference_unchecked(from_reference)
          let to_expr = normalize_reference_unchecked(to_reference)
          let modules = [
            reference_module_unchecked(from_reference),
            reference_module_unchecked(to_reference),
          ]
          Lowered(
            encoder: prefix <> "_encode",
            decoder: prefix <> "_decode",
            native_encoder: prefix <> "_native_encode",
            native_decoder: prefix <> "_native_decode",
            native_supported: inner_lowered.native_supported,
            declarations: list.append(lower_declarations(inner_lowered), [
              "fn "
                <> prefix
                <> "_encode(item: "
                <> output_type
                <> ") -> Result(value.Value, codec.EncodeError) {\n"
                <> "  codec.encode_mapped_with("
                <> lower_encoder(inner_lowered)
                <> ", "
                <> to_expr
                <> ", item)\n}",
              "fn "
                <> prefix
                <> "_decode(raw: value.Value) -> Result("
                <> output_type
                <> ", codec.DecodeError) {\n"
                <> "  codec.decode_mapped_with("
                <> lower_decoder(inner_lowered)
                <> ", "
                <> from_expr
                <> ", raw)\n}",
              "fn "
                <> prefix
                <> "_native_encode(item: "
                <> output_type
                <> ") -> Result(json.Json, codec.EncodeError) {\n"
                <> "  "
                <> lower_native_encoder(inner_lowered)
                <> "("
                <> to_expr
                <> "(item))\n}",
              "fn "
                <> prefix
                <> "_native_decode(raw: dynamic.Dynamic) -> Result("
                <> output_type
                <> ", codec.DecodeError) {\n"
                <> "  case "
                <> lower_native_decoder(inner_lowered)
                <> "(raw) {\n    Ok(item) -> Ok("
                <> from_expr
                <> "(item))\n    Error(error) -> Error(error)\n  }\n}",
            ]),
            imports: list.append(lower_imports(inner_lowered), modules),
          )
        }),
      )
    }
  }
}

pub fn runtime(definition: Definition(a)) -> codec.Codec(a) {
  let Definition(runtime_codec, _, _) = definition
  runtime_codec
}

/// Compile one canonical typed definition into Blueprint Value operations,
/// gleam/json-native text operations, a schema, and an interchangeable Codec.
/// Native text parsing follows gleam/json's parser normalization and duplicate
/// object-key behavior rather than the stricter runtime Blueprint parser.
pub fn compile(
  module_path: String,
  name: String,
  definition: Definition(a),
) -> Result(GeneratedModule, CompileError) {
  case schema_materialize.validate_module_path(module_path) {
    Error(error) -> Error(translate_schema_error(error))
    Ok(valid_path) ->
      case schema_materialize.validate_accessor_name(name) {
        Error(schema_materialize.InvalidAccessorName(_, reason)) ->
          Error(InvalidCodecName(name, reason))
        Error(error) -> Error(translate_schema_error(error))
        Ok(valid_name) -> compile_valid(valid_path, valid_name, definition)
      }
  }
}

fn translate_schema_error(
  error: schema_materialize.MaterializationError,
) -> CompileError {
  case error {
    schema_materialize.UnknownSchema(accessor) -> UnknownSchema(accessor)
    schema_materialize.InvalidModuleName(module_path, reason) ->
      InvalidModulePath(module_path, reason)
    schema_materialize.InvalidAccessorName(name, reason) ->
      InvalidCodecName(name, reason)
    schema_materialize.DuplicateAccessor(name) -> DuplicateSchemaAccessor(name)
    schema_materialize.UnsupportedConstructor(path, constructor) ->
      UnsupportedSchemaConstructor(path, constructor)
  }
}

fn compile_valid(
  module_path: String,
  name: String,
  definition: Definition(a),
) -> Result(GeneratedModule, CompileError) {
  let Definition(runtime_codec, type_name, lower) = definition
  use type_reference <- result.try(parse_type_reference(type_name))
  let lowered = lower(name <> "_compiled")
  case lowered.native_supported {
    False -> Error(NativeNumberUnsupported)
    True ->
      compile_supported(
        module_path,
        name,
        runtime_codec,
        type_reference,
        lowered,
      )
  }
}

fn compile_supported(
  module_path: String,
  name: String,
  runtime_codec: codec.Codec(a),
  type_reference: TypeReference,
  lowered: Lowered,
) -> Result(GeneratedModule, CompileError) {
  let imports =
    list.append(
      [
        "gleam/dynamic",
        "gleam/dynamic/decode",
        "gleam/json",
        "json/blueprint/codec",
        "json/blueprint/value",
      ],
      lower_imports(lowered),
    )
    |> unique_sorted
  use validated_imports <- result.try(validate_imports(type_reference, imports))
  case codec.schema(runtime_codec) {
    Error(codec.UnknownSchema) -> Error(UnknownSchema(name))
    Ok(schema) ->
      case schema_materialize.emit_schema_expression(schema, [name]) {
        Error(error) -> Error(translate_schema_error(error))
        Ok(schema_expression) -> {
          let declarations = lower_declarations(lowered)
          let encoder_name = "encode_" <> name
          let decoder_name = "decode_" <> name
          let json_encoder_name = "encode_" <> name <> "_json"
          let json_decoder_name = "decode_" <> name <> "_json"
          let schema_name = name <> "_schema"
          let codec_name = name <> "_codec"
          let body =
            "// @generated by json_blueprint.codegen; do not edit\n"
            <> string.join(
              list.map(validated_imports, fn(module) { "import " <> module }),
              "\n",
            )
            <> "\n\n"
            <> "const "
            <> schema_name
            <> "_value: codec.Schema = "
            <> schema_expression
            <> "\n\n"
            <> string.join(declarations, "\n\n")
            <> "\n\n"
            <> "pub fn "
            <> encoder_name
            <> "(item: "
            <> type_reference.expression
            <> ") -> Result(value.Value, codec.EncodeError) {\n  "
            <> lower_encoder(lowered)
            <> "(item)\n}\n\n"
            <> "pub fn "
            <> decoder_name
            <> "(raw: value.Value) -> Result("
            <> type_reference.expression
            <> ", codec.DecodeError) {\n  "
            <> lower_decoder(lowered)
            <> "(raw)\n}\n\n"
            <> "pub fn "
            <> json_encoder_name
            <> "(item: "
            <> type_reference.expression
            <> ") -> Result(String, codec.EncodeError) {\n"
            <> "  case "
            <> lower_native_encoder(lowered)
            <> "(item) {\n    Error(error) -> Error(error)\n    Ok(encoded) -> Ok(json.to_string(encoded))\n  }\n}\n\n"
            <> "pub fn "
            <> json_decoder_name
            <> "(source: String) -> Result("
            <> type_reference.expression
            <> ", codec.JsonDecodeError) {\n"
            <> "  case json.parse(from: source, using: decode.dynamic) {\n"
            <> "    Error(error) -> Error(codec.NativeJsonFailure(error))\n"
            <> "    Ok(raw) -> case "
            <> lower_native_decoder(lowered)
            <> "(raw) {\n      Ok(item) -> Ok(item)\n      Error(error) -> Error(codec.TypedCodecFailure(error))\n    }\n  }\n}\n\n"
            <> "pub fn "
            <> schema_name
            <> "() -> codec.Schema {\n  "
            <> schema_name
            <> "_value\n}\n\n"
            <> "pub fn "
            <> codec_name
            <> "() -> codec.Codec("
            <> type_reference.expression
            <> ") {\n  codec.from_json_parts("
            <> encoder_name
            <> ", "
            <> decoder_name
            <> ", "
            <> json_encoder_name
            <> ", "
            <> json_decoder_name
            <> ", "
            <> schema_name
            <> "())\n}\n"
          let fingerprint = fingerprint(body)
          let content =
            string.replace(
              body,
              "\n\nconst " <> schema_name <> "_value",
              "\n\npub const generated_fingerprint: String = \""
                <> fingerprint
                <> "\"\n\nconst "
                <> schema_name
                <> "_value",
            )
          Ok(GeneratedModule(module_path <> ".gleam", content, fingerprint))
        }
      }
  }
}

fn fingerprint(content: String) -> String {
  content
  |> bit_array.from_string
  |> crypto.hash(crypto.Sha1, _)
  |> bit_array.base16_encode
}

fn validate_imports(
  type_reference: TypeReference,
  imports: List(String),
) -> Result(List(String), CompileError) {
  use aliases_checked <- result.try(check_import_aliases(imports, []))
  case
    missing_type_alias(
      type_module_aliases(type_reference.expression),
      aliases_checked,
    )
  {
    Some(alias) -> Error(MissingTypeImport(alias))
    None -> Ok(imports)
  }
}

fn check_import_aliases(
  imports: List(String),
  seen: List(#(String, String)),
) -> Result(List(#(String, String)), CompileError) {
  case imports {
    [] -> Ok(seen)
    [module, ..rest] -> {
      let alias = module_alias(module)
      case find_alias(seen, alias) {
        Some(#(_, existing)) if existing != module ->
          Error(ConflictingImportAlias(alias, existing, module))
        _ -> check_import_aliases(rest, [#(alias, module), ..seen])
      }
    }
  }
}

fn find_alias(
  seen: List(#(String, String)),
  alias: String,
) -> Option(#(String, String)) {
  case seen {
    [] -> None
    [entry, ..] if entry.0 == alias -> Some(entry)
    [_, ..rest] -> find_alias(rest, alias)
  }
}

fn missing_type_alias(
  aliases: List(String),
  imports: List(#(String, String)),
) -> Option(String) {
  case aliases {
    [] -> None
    [alias, ..rest] ->
      case find_alias(imports, alias) {
        Some(_) -> missing_type_alias(rest, imports)
        None -> Some(alias)
      }
  }
}

fn type_module_aliases(expression: String) -> List(String) {
  type_module_aliases_scan(string.to_graphemes(expression), [], [])
  |> unique_sorted
}

fn type_module_aliases_scan(
  remaining: List(String),
  token_reversed: List(String),
  aliases: List(String),
) -> List(String) {
  case remaining {
    [] -> aliases
    [".", ..rest] -> {
      let token = string.join(list.reverse(token_reversed), "")
      let updated_aliases = case token {
        "" -> aliases
        _ -> [token, ..aliases]
      }
      type_module_aliases_scan(rest, [], updated_aliases)
    }
    [character, ..rest] ->
      case is_type_identifier_character(character) {
        True ->
          type_module_aliases_scan(rest, [character, ..token_reversed], aliases)
        False -> type_module_aliases_scan(rest, [], aliases)
      }
  }
}

fn is_type_identifier_character(character: String) -> Bool {
  is_upper_alpha(character)
  || is_lower_alpha(character)
  || is_digit(character)
  || character == "_"
}

fn module_alias(module: String) -> String {
  case list.reverse(string.split(module, "/")) {
    [alias, ..] -> alias
    [] -> module
  }
}

type TypeReference {
  TypeReference(expression: String)
}

fn parse_type_reference(raw: String) -> Result(TypeReference, CompileError) {
  case valid_type_expression(string.to_graphemes(raw), 0, False) {
    True -> Ok(TypeReference(raw))
    False -> Error(InvalidTypeReference(raw))
  }
}

fn valid_type_expression(
  graphemes: List(String),
  depth: Int,
  has_content: Bool,
) -> Bool {
  case graphemes {
    [] -> depth == 0 && has_content
    ["(", ..rest] -> valid_type_expression(rest, depth + 1, has_content)
    [")", ..rest] if depth > 0 ->
      valid_type_expression(rest, depth - 1, has_content)
    [ch, ..rest] ->
      case is_type_character(ch) {
        True -> valid_type_expression(rest, depth, has_content || ch != " ")
        False -> False
      }
  }
}

fn is_type_character(ch: String) -> Bool {
  is_upper_alpha(ch)
  || is_lower_alpha(ch)
  || is_digit(ch)
  || ch == "_"
  || ch == "."
  || ch == "#"
  || ch == ","
  || ch == " "
}

fn parse_function_reference(
  raw: String,
) -> Result(#(String, String), CompileError) {
  case string.split(raw, ".") {
    [module, name] ->
      case
        schema_materialize.validate_module_path(module),
        schema_materialize.validate_accessor_name(name)
      {
        Ok(_), Ok(_) -> Ok(#(module, module <> "." <> name))
        _, _ -> Error(InvalidFunctionReference(raw))
      }
    _ -> Error(InvalidFunctionReference(raw))
  }
}

fn parse_constructor_reference(
  raw: String,
) -> Result(#(String, String), CompileError) {
  case string.split(raw, ".") {
    [module, name] ->
      case
        schema_materialize.validate_module_path(module),
        is_upper_identifier(name)
      {
        Ok(_), True -> Ok(#(module, module <> "." <> name))
        _, _ -> Error(InvalidFunctionReference(raw))
      }
    _ -> Error(InvalidFunctionReference(raw))
  }
}

fn is_upper_identifier(name: String) -> Bool {
  case string.to_graphemes(name) {
    [] -> False
    [first, ..rest] ->
      is_upper_alpha(first)
      && list.all(rest, fn(ch) {
        is_upper_alpha(ch) || is_lower_alpha(ch) || is_digit(ch) || ch == "_"
      })
  }
}

fn is_upper_alpha(ch: String) -> Bool {
  case ch {
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    _ -> False
  }
}

fn is_lower_alpha(ch: String) -> Bool {
  case ch {
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    _ -> False
  }
}

fn is_digit(ch: String) -> Bool {
  case ch {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn emit_enum_encoder_arms(
  variants: List(EnumVariant(a)),
  acc: List(String),
) -> List(String) {
  case variants {
    [] -> list.reverse(acc)
    [EnumVariant(label, _, reference), ..rest] -> {
      let expression = normalize_reference_unchecked(reference)
      emit_enum_encoder_arms(rest, [
        "    "
          <> expression
          <> " -> Ok(value.String("
          <> schema_materialize.escape_string_literal(label)
          <> "))",
        ..acc
      ])
    }
  }
}

fn emit_enum_decoder_arms(
  variants: List(EnumVariant(a)),
  acc: List(String),
) -> List(String) {
  case variants {
    [] -> list.reverse(acc)
    [EnumVariant(label, _, reference), ..rest] -> {
      let expression = normalize_reference_unchecked(reference)
      emit_enum_decoder_arms(rest, [
        "      "
          <> schema_materialize.escape_string_literal(label)
          <> " -> Ok("
          <> expression
          <> ")",
        ..acc
      ])
    }
  }
}

fn emit_native_enum_encoder_arms(
  variants: List(EnumVariant(a)),
  acc: List(String),
) -> List(String) {
  case variants {
    [] -> list.reverse(acc)
    [EnumVariant(label, _, reference), ..rest] -> {
      let expression = normalize_reference_unchecked(reference)
      emit_native_enum_encoder_arms(rest, [
        "    "
          <> expression
          <> " -> Ok(json.string("
          <> schema_materialize.escape_string_literal(label)
          <> "))",
        ..acc
      ])
    }
  }
}

fn emit_native_enum_decoder_arms(
  variants: List(EnumVariant(a)),
  acc: List(String),
) -> List(String) {
  case variants {
    [] -> list.reverse(acc)
    [EnumVariant(label, _, reference), ..rest] -> {
      let expression = normalize_reference_unchecked(reference)
      emit_native_enum_decoder_arms(rest, [
        "      "
          <> schema_materialize.escape_string_literal(label)
          <> " -> Ok("
          <> expression
          <> ")",
        ..acc
      ])
    }
  }
}

fn reference_module_unchecked(reference: String) -> String {
  case parse_function_reference(reference) {
    Ok(#(module, _)) -> module
    Error(_) ->
      case parse_constructor_reference(reference) {
        Ok(#(module, _)) -> module
        Error(_) -> ""
      }
  }
}

fn normalize_reference_unchecked(reference: String) -> String {
  case parse_function_reference(reference) {
    Ok(#(module, _)) -> reference_with_alias(module, reference)
    Error(_) ->
      case parse_constructor_reference(reference) {
        Ok(#(module, _)) -> reference_with_alias(module, reference)
        Error(_) -> reference
      }
  }
}

fn reference_with_alias(module: String, reference: String) -> String {
  let name = case string.split(reference, ".") {
    [_, function_name] -> function_name
    _ -> reference
  }
  let alias = case list.reverse(string.split(module, "/")) {
    [last, ..] -> last
    [] -> module
  }
  alias <> "." <> name
}

fn lower_encoder(lowered: Lowered) -> String {
  let Lowered(encoder, _, _, _, _, _, _) = lowered
  encoder
}

fn lower_decoder(lowered: Lowered) -> String {
  let Lowered(_, decoder, _, _, _, _, _) = lowered
  decoder
}

fn lower_native_encoder(lowered: Lowered) -> String {
  let Lowered(_, _, encoder, _, _, _, _) = lowered
  encoder
}

fn lower_native_decoder(lowered: Lowered) -> String {
  let Lowered(_, _, _, decoder, _, _, _) = lowered
  decoder
}

fn lower_declarations(lowered: Lowered) -> List(String) {
  let Lowered(_, _, _, _, _, declarations, _) = lowered
  declarations
}

fn lower_imports(lowered: Lowered) -> List(String) {
  let Lowered(_, _, _, _, _, _, imports) = lowered
  imports
}

fn lower_property_encoder(lowered: LoweredProperties) -> String {
  let LoweredProperties(encoder, _, _, _, _, _, _) = lowered
  encoder
}

fn lower_property_decoder(lowered: LoweredProperties) -> String {
  let LoweredProperties(_, decoder, _, _, _, _, _) = lowered
  decoder
}

fn lower_property_native_encoder(lowered: LoweredProperties) -> String {
  let LoweredProperties(_, _, encoder, _, _, _, _) = lowered
  encoder
}

fn lower_property_native_decoder(lowered: LoweredProperties) -> String {
  let LoweredProperties(_, _, _, decoder, _, _, _) = lowered
  decoder
}

fn lower_property_declarations(lowered: LoweredProperties) -> List(String) {
  let LoweredProperties(_, _, _, _, _, declarations, _) = lowered
  declarations
}

fn lower_property_imports(lowered: LoweredProperties) -> List(String) {
  let LoweredProperties(_, _, _, _, _, _, imports) = lowered
  imports
}

fn emit_string_list(items: List(String)) -> String {
  "["
  <> string.join(
    list.map(items, schema_materialize.escape_string_literal),
    ", ",
  )
  <> "]"
}

fn unique_sorted(items: List(String)) -> List(String) {
  items
  |> list.sort(string.compare)
  |> unique([])
}

fn unique(items: List(String), seen: List(String)) -> List(String) {
  case items {
    [] -> list.reverse(seen)
    [item, ..rest] ->
      case list.contains(seen, item) {
        True -> unique(rest, seen)
        False -> unique(rest, [item, ..seen])
      }
  }
}
