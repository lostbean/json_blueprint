//// Codec definitions that run as a `Codec(a)` and compile to a Gleam module
//// with the same encoder, decoders and schema.
////
//// This module belongs to `json_blueprint_codegen`, a dev-only package: use
//// it in a build task or a test, not at run time. A `Definition(a)` is built
//// from the same shapes as `json/blueprint/codec`; mappings to your own types
//// name their functions (`named_mapping`, `enum_variant`) because the
//// generated source must call them. `runtime` returns the definition's codec.
//// `compile` returns a `GeneratedModule` whose content the caller writes
//// under `src/`, formats with `gleam format`, and keeps fresh with a test
//// that compiles again and compares. A definition mistake, such as a
//// property named twice, is a `CompileError`.
////
//// Generated modules call `json/blueprint/internal/generated`, whose names
//// json_blueprint keeps stable within a major version. They decode text with
//// the strict parser; `decode_<name>_json_native` uses `gleam/json` instead,
//// returns `json.DecodeError`, and rejects text above 1 MiB before parsing.
////
//// ```gleam
//// import json/blueprint/codec
//// import json/blueprint/codegen
////
//// pub fn names_definition() -> codegen.Definition(List(String)) {
////   codegen.list(codegen.string())
//// }
////
//// pub fn example() {
////   let assert Ok(["a", "b"]) =
////     codec.decode_json(codegen.runtime(names_definition()), "[\"a\",\"b\"]")
////   // In a build task: write `content` to "src/" <> path.
////   let assert Ok(codegen.GeneratedModule(path:, content:, fingerprint: _)) =
////     codegen.compile("generated/names_codec", "names", names_definition())
////   #(path, content)
//// }
//// ```

import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import json/blueprint/codec
import json/blueprint/codegen/internal/schema_materialize
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

/// The properties of an object definition whose record type is `r`, with
/// values of type `a`. `combine` pairs them; `object` closes them.
pub opaque type Properties(r, a) {
  Properties(
    // Continue a record codec of `r` with these properties: `get` reads them
    // from the record and `next` builds the rest from their values.
    build: fn(fn(r) -> a, fn(a) -> codec.Codec(r)) -> codec.Codec(r),
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
  InvalidDefinition(codec.DefinitionError)
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
    placeholder: String,
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
    placeholder: String,
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
          <> "  generated.encode_string(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(String, codec.DecodeError) {\n"
          <> "  generated.decode_string(raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: String) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  Ok(json.string(item))\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(String, codec.DecodeError) {\n"
          <> "  generated.decode_native_string(raw)\n}",
      ],
      imports: ["gleam/dynamic"],
      placeholder: "\"\"",
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
          <> "  generated.encode_int(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(Int, codec.DecodeError) {\n"
          <> "  generated.decode_int(raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: Int) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  generated.encode_native_int(item)\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(Int, codec.DecodeError) {\n"
          <> "  generated.decode_native_int(raw)\n}",
      ],
      imports: ["gleam/dynamic"],
      placeholder: "0",
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
          <> "  generated.encode_number(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(number.Number, codec.DecodeError) {\n"
          <> "  generated.decode_number(raw)\n}",
      ],
      imports: ["json/blueprint/number"],
      placeholder: "generated.zero_number()",
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
          <> "  generated.encode_bool(item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(Bool, codec.DecodeError) {\n"
          <> "  generated.decode_bool(raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: Bool) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  Ok(json.bool(item))\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(Bool, codec.DecodeError) {\n"
          <> "  generated.decode_native_bool(raw)\n}",
      ],
      imports: ["gleam/dynamic"],
      placeholder: "False",
    )
  })
}

/// An integer from `min` to `max` inclusive. Reversed bounds are a
/// definition mistake that `compile` reports.
pub fn integer_between(min: Int, max: Int) -> Definition(Int) {
  let min_text = schema_materialize.format_int_literal(min)
  let max_text = schema_materialize.format_int_literal(max)
  let bounds = min_text <> ", " <> max_text
  Definition(codec.integer_between(min, max), "Int", fn(prefix) {
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
          <> "  generated.encode_integer_between("
          <> bounds
          <> ", item)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(Int, codec.DecodeError) {\n"
          <> "  generated.decode_integer_between("
          <> bounds
          <> ", raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(item: Int) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  generated.encode_native_integer_between("
          <> bounds
          <> ", item)\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(Int, codec.DecodeError) {\n"
          <> "  generated.decode_native_integer_between("
          <> bounds
          <> ", raw)\n}",
      ],
      imports: ["gleam/dynamic"],
      placeholder: min_text,
    )
  })
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
          left_lowered.declarations,
          list.append(right_lowered.declarations, [
            "fn "
              <> prefix
              <> "_encode(item: #("
              <> left_type
              <> ", "
              <> right_type
              <> ")) -> Result(value.Value, codec.EncodeError) {\n"
              <> "  generated.encode_pair("
              <> left_lowered.encoder
              <> ", "
              <> right_lowered.encoder
              <> ", item)\n}",
            "fn "
              <> prefix
              <> "_decode(raw: value.Value) -> Result(#("
              <> left_type
              <> ", "
              <> right_type
              <> "), codec.DecodeError) {\n  generated.decode_pair("
              <> left_lowered.decoder
              <> ", "
              <> right_lowered.decoder
              <> ", raw)\n}",
            "fn "
              <> prefix
              <> "_native_encode(item: #("
              <> left_type
              <> ", "
              <> right_type
              <> ")) -> Result(json.Json, codec.EncodeError) {\n"
              <> "  generated.encode_native_pair("
              <> left_lowered.native_encoder
              <> ", "
              <> right_lowered.native_encoder
              <> ", item)\n}",
            "fn "
              <> prefix
              <> "_native_decode(raw: dynamic.Dynamic) -> Result(#("
              <> left_type
              <> ", "
              <> right_type
              <> "), codec.DecodeError) {\n"
              <> "  generated.decode_native_pair("
              <> left_lowered.native_decoder
              <> ", "
              <> right_lowered.native_decoder
              <> ", raw)\n}",
          ]),
        ),
        imports: list.append(left_lowered.imports, right_lowered.imports),
        placeholder: "#("
          <> left_lowered.placeholder
          <> ", "
          <> right_lowered.placeholder
          <> ")",
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
      declarations: list.append(inner_lowered.declarations, [
        "fn "
          <> prefix
          <> "_encode(items: List("
          <> inner_type
          <> ")) -> Result(value.Value, codec.EncodeError) {\n"
          <> "  generated.encode_list("
          <> inner_lowered.encoder
          <> ", items)\n}",
        "fn "
          <> prefix
          <> "_decode(raw: value.Value) -> Result(List("
          <> inner_type
          <> "), codec.DecodeError) {\n"
          <> "  generated.decode_list("
          <> inner_lowered.decoder
          <> ", raw)\n}",
        "fn "
          <> prefix
          <> "_native_encode(items: List("
          <> inner_type
          <> ")) -> Result(json.Json, codec.EncodeError) {\n"
          <> "  generated.encode_native_list("
          <> inner_lowered.native_encoder
          <> ", items)\n}",
        "fn "
          <> prefix
          <> "_native_decode(raw: dynamic.Dynamic) -> Result(List("
          <> inner_type
          <> "), codec.DecodeError) {\n"
          <> "  generated.decode_native_list("
          <> inner_lowered.native_decoder
          <> ", raw)\n}",
      ]),
      imports: inner_lowered.imports,
      placeholder: "[]",
    )
  })
}

pub fn nullable(inner: Definition(a)) -> Definition(Option(a)) {
  let Definition(inner_codec, inner_type, lower_inner) = inner
  Definition(
    codec.nullable(inner_codec),
    "option.Option(" <> inner_type <> ")",
    fn(prefix) {
      let inner_lowered = lower_inner(prefix <> "_inner")
      Lowered(
        encoder: prefix <> "_encode",
        decoder: prefix <> "_decode",
        native_encoder: prefix <> "_native_encode",
        native_decoder: prefix <> "_native_decode",
        native_supported: inner_lowered.native_supported,
        declarations: list.append(inner_lowered.declarations, [
          "fn "
            <> prefix
            <> "_encode(item: option.Option("
            <> inner_type
            <> ")) -> Result(value.Value, codec.EncodeError) {\n"
            <> "  generated.encode_nullable("
            <> inner_lowered.encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_decode(raw: value.Value) -> Result(option.Option("
            <> inner_type
            <> "), codec.DecodeError) {\n"
            <> "  generated.decode_nullable("
            <> inner_lowered.decoder
            <> ", raw)\n}",
          "fn "
            <> prefix
            <> "_native_encode(item: option.Option("
            <> inner_type
            <> ")) -> Result(json.Json, codec.EncodeError) {\n"
            <> "  generated.encode_native_nullable("
            <> inner_lowered.native_encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_native_decode(raw: dynamic.Dynamic) -> Result(option.Option("
            <> inner_type
            <> "), codec.DecodeError) {\n"
            <> "  generated.decode_native_nullable("
            <> inner_lowered.native_decoder
            <> ", raw)\n}",
        ]),
        imports: ["gleam/option", ..inner_lowered.imports],
        placeholder: "option.None",
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
      let runtime_codec = codec.string_enum(runtime_variants)
      let placeholder = case variants {
        [EnumVariant(_, _, reference), ..] ->
          normalize_reference_unchecked(reference)
        [] -> "panic"
      }
      {
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
                  <> "\n    _ -> generated.unknown_enum_value()\n  }\n}",
                "fn "
                  <> prefix
                  <> "_decode(raw: value.Value) -> Result("
                  <> type_name
                  <> ", codec.DecodeError) {\n  case raw {\n"
                  <> "    value.String(label) -> case label {\n"
                  <> string.join(decoder_arms, "\n")
                  <> "\n      _ -> generated.unknown_enum_label()\n    }\n"
                  <> "    _ -> generated.expected_string()\n  }\n}",
                "fn "
                  <> prefix
                  <> "_native_encode(item: "
                  <> type_name
                  <> ") -> Result(json.Json, codec.EncodeError) {\n  case item {\n"
                  <> string.join(native_encoder_arms, "\n")
                  <> "\n    _ -> generated.unknown_enum_value()\n  }\n}",
                "fn "
                  <> prefix
                  <> "_native_decode(raw: dynamic.Dynamic) -> Result("
                  <> type_name
                  <> ", codec.DecodeError) {\n"
                  <> "  case generated.decode_native_string(raw) {\n"
                  <> "    Error(error) -> Error(error)\n"
                  <> "    Ok(label) -> case label {\n"
                  <> string.join(native_decoder_arms, "\n")
                  <> "\n      _ -> generated.unknown_enum_label()\n    }\n  }\n}",
              ],
              imports: ["gleam/dynamic", ..imports],
              placeholder:,
            )
          }),
        )
      }
    }
  }
}

/// A required property.
pub fn required(name: String, inner: Definition(a)) -> Properties(r, a) {
  let Definition(inner_codec, inner_type, lower_inner) = inner
  Properties(
    build: fn(get, next) { codec.field(name, inner_codec, get, next) },
    gleam_type: inner_type,
    names: [name],
    lower: fn(prefix) {
      let inner_lowered = lower_inner(prefix <> "_value")
      let quoted = schema_materialize.escape_string_literal(name)
      LoweredProperties(
        encoder: prefix <> "_encode",
        decoder: prefix <> "_decode",
        native_encoder: prefix <> "_native_encode",
        native_decoder: prefix <> "_native_decode",
        native_supported: inner_lowered.native_supported,
        declarations: list.append(inner_lowered.declarations, [
          "fn "
            <> prefix
            <> "_encode(item: "
            <> inner_type
            <> ") -> Result(List(#(String, value.Value)), codec.EncodeError) {\n"
            <> "  generated.encode_required("
            <> quoted
            <> ", "
            <> inner_lowered.encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_decode(fields: List(#(String, value.Value))) -> Result("
            <> inner_type
            <> ", codec.DecodeError) {\n"
            <> "  generated.decode_required("
            <> quoted
            <> ", fields, "
            <> inner_lowered.decoder
            <> ")\n}",
          "fn "
            <> prefix
            <> "_native_encode(item: "
            <> inner_type
            <> ") -> Result(List(#(String, json.Json)), codec.EncodeError) {\n"
            <> "  generated.encode_native_required("
            <> quoted
            <> ", "
            <> inner_lowered.native_encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_native_decode(fields: dict.Dict(String, dynamic.Dynamic)) -> Result("
            <> inner_type
            <> ", codec.DecodeError) {\n"
            <> "  generated.decode_native_required("
            <> quoted
            <> ", fields, "
            <> inner_lowered.native_decoder
            <> ")\n}",
        ]),
        imports: ["gleam/dict", "gleam/dynamic", ..inner_lowered.imports],
        placeholder: inner_lowered.placeholder,
      )
    },
  )
}

/// An optional property: absent is `None`. With a `nullable` inner
/// definition, absent, `null` and a value are `None`, `Some(None)` and
/// `Some(Some(x))`.
pub fn optional(
  name: String,
  inner: Definition(a),
) -> Properties(r, Option(a)) {
  let Definition(inner_codec, inner_type, lower_inner) = inner
  let optional_type = "option.Option(" <> inner_type <> ")"
  Properties(
    build: fn(get, next) { codec.optional_field(name, inner_codec, get, next) },
    gleam_type: optional_type,
    names: [name],
    lower: fn(prefix) {
      let inner_lowered = lower_inner(prefix <> "_value")
      let quoted = schema_materialize.escape_string_literal(name)
      LoweredProperties(
        encoder: prefix <> "_encode",
        decoder: prefix <> "_decode",
        native_encoder: prefix <> "_native_encode",
        native_decoder: prefix <> "_native_decode",
        native_supported: inner_lowered.native_supported,
        declarations: list.append(inner_lowered.declarations, [
          "fn "
            <> prefix
            <> "_encode(item: "
            <> optional_type
            <> ") -> Result(List(#(String, value.Value)), codec.EncodeError) {\n"
            <> "  generated.encode_optional("
            <> quoted
            <> ", "
            <> inner_lowered.encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_decode(fields: List(#(String, value.Value))) -> Result("
            <> optional_type
            <> ", codec.DecodeError) {\n"
            <> "  generated.decode_optional("
            <> quoted
            <> ", fields, "
            <> inner_lowered.decoder
            <> ")\n}",
          "fn "
            <> prefix
            <> "_native_encode(item: "
            <> optional_type
            <> ") -> Result(List(#(String, json.Json)), codec.EncodeError) {\n"
            <> "  generated.encode_native_optional("
            <> quoted
            <> ", "
            <> inner_lowered.native_encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_native_decode(fields: dict.Dict(String, dynamic.Dynamic)) -> Result("
            <> optional_type
            <> ", codec.DecodeError) {\n"
            <> "  generated.decode_native_optional("
            <> quoted
            <> ", fields, "
            <> inner_lowered.native_decoder
            <> ")\n}",
        ]),
        imports: [
          "gleam/dict",
          "gleam/dynamic",
          "gleam/option",
          ..inner_lowered.imports
        ],
        placeholder: "option.None",
      )
    },
  )
}

/// Both groups of properties, as a pair. A name in both groups is a
/// definition mistake that `compile` reports.
pub fn combine(
  left: Properties(r, a),
  right: Properties(r, b),
) -> Properties(r, #(a, b)) {
  let Properties(build_left, left_type, left_names, lower_left) = left
  let Properties(build_right, right_type, right_names, lower_right) = right
  let pair_type = "#(" <> left_type <> ", " <> right_type <> ")"
  Properties(
    build: fn(get: fn(r) -> #(a, b), next) {
      build_left(fn(record) { get(record).0 }, fn(first) {
        build_right(fn(record) { get(record).1 }, fn(second) {
          next(#(first, second))
        })
      })
    },
    gleam_type: pair_type,
    names: list.append(left_names, right_names),
    lower: fn(prefix) {
      let left_lowered = lower_left(prefix <> "_left")
      let right_lowered = lower_right(prefix <> "_right")
      LoweredProperties(
        encoder: prefix <> "_encode",
        decoder: prefix <> "_decode",
        native_encoder: prefix <> "_native_encode",
        native_decoder: prefix <> "_native_decode",
        native_supported: left_lowered.native_supported
          && right_lowered.native_supported,
        declarations: list.flatten([
          left_lowered.declarations,
          right_lowered.declarations,
          [
            "fn "
              <> prefix
              <> "_encode(item: "
              <> pair_type
              <> ") -> Result(List(#(String, value.Value)), codec.EncodeError) {\n"
              <> "  generated.encode_fields_pair("
              <> left_lowered.encoder
              <> ", "
              <> right_lowered.encoder
              <> ", item)\n}",
            "fn "
              <> prefix
              <> "_decode(fields: List(#(String, value.Value))) -> Result("
              <> pair_type
              <> ", codec.DecodeError) {\n  generated.decode_fields_pair("
              <> left_lowered.decoder
              <> ", "
              <> right_lowered.decoder
              <> ", fields)\n}",
            "fn "
              <> prefix
              <> "_native_encode(item: "
              <> pair_type
              <> ") -> Result(List(#(String, json.Json)), codec.EncodeError) {\n"
              <> "  generated.encode_native_fields_pair("
              <> left_lowered.native_encoder
              <> ", "
              <> right_lowered.native_encoder
              <> ", item)\n}",
            "fn "
              <> prefix
              <> "_native_decode(fields: dict.Dict(String, dynamic.Dynamic)) -> Result("
              <> pair_type
              <> ", codec.DecodeError) {\n"
              <> "  generated.decode_native_fields_pair("
              <> left_lowered.native_decoder
              <> ", "
              <> right_lowered.native_decoder
              <> ", fields)\n}",
          ],
        ]),
        imports: list.append(left_lowered.imports, right_lowered.imports),
        placeholder: "#("
          <> left_lowered.placeholder
          <> ", "
          <> right_lowered.placeholder
          <> ")",
      )
    },
  )
}

/// A closed object of the properties.
pub fn object(properties: Properties(a, a)) -> Definition(a) {
  let Properties(build, object_type, names, lower_properties) = properties
  let runtime_codec = build(fn(item) { item }, codec.success)
  Definition(runtime_codec, object_type, fn(prefix) {
    let lowered = lower_properties(prefix <> "_properties")
    let names_name = prefix <> "_property_names"
    Lowered(
      encoder: prefix <> "_encode",
      decoder: prefix <> "_decode",
      native_encoder: prefix <> "_native_encode",
      native_decoder: prefix <> "_native_decode",
      native_supported: lowered.native_supported,
      declarations: [
        "const " <> names_name <> ": List(String) = " <> emit_string_list(names),
        ..list.append(lowered.declarations, [
          "fn "
            <> prefix
            <> "_encode(item: "
            <> object_type
            <> ") -> Result(value.Value, codec.EncodeError) {\n"
            <> "  generated.encode_object("
            <> lowered.encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_decode(raw: value.Value) -> Result("
            <> object_type
            <> ", codec.DecodeError) {\n"
            <> "  generated.decode_object("
            <> names_name
            <> ", "
            <> lowered.decoder
            <> ", raw)\n}",
          "fn "
            <> prefix
            <> "_native_encode(item: "
            <> object_type
            <> ") -> Result(json.Json, codec.EncodeError) {\n"
            <> "  generated.encode_native_object("
            <> lowered.native_encoder
            <> ", item)\n}",
          "fn "
            <> prefix
            <> "_native_decode(raw: dynamic.Dynamic) -> Result("
            <> object_type
            <> ", codec.DecodeError) {\n"
            <> "  generated.decode_native_object("
            <> names_name
            <> ", "
            <> lowered.native_decoder
            <> ", raw)\n}",
        ])
      ],
      imports: lowered.imports,
      placeholder: lowered.placeholder,
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
        Definition(codec.map(inner_codec, from, to), output_type, fn(prefix) {
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
            declarations: list.append(inner_lowered.declarations, [
              "fn "
                <> prefix
                <> "_encode(item: "
                <> output_type
                <> ") -> Result(value.Value, codec.EncodeError) {\n"
                <> "  generated.encode_mapped("
                <> inner_lowered.encoder
                <> ", "
                <> to_expr
                <> ", item)\n}",
              "fn "
                <> prefix
                <> "_decode(raw: value.Value) -> Result("
                <> output_type
                <> ", codec.DecodeError) {\n"
                <> "  generated.decode_mapped("
                <> inner_lowered.decoder
                <> ", "
                <> from_expr
                <> ", raw)\n}",
              "fn "
                <> prefix
                <> "_native_encode(item: "
                <> output_type
                <> ") -> Result(json.Json, codec.EncodeError) {\n"
                <> "  "
                <> inner_lowered.native_encoder
                <> "("
                <> to_expr
                <> "(item))\n}",
              "fn "
                <> prefix
                <> "_native_decode(raw: dynamic.Dynamic) -> Result("
                <> output_type
                <> ", codec.DecodeError) {\n"
                <> "  case "
                <> inner_lowered.native_decoder
                <> "(raw) {\n    Ok(item) -> Ok("
                <> from_expr
                <> "(item))\n    Error(error) -> Error(error)\n  }\n}",
            ]),
            imports: list.append(inner_lowered.imports, modules),
            placeholder: from_expr <> "(" <> inner_lowered.placeholder <> ")",
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

/// Add the same schema description to runtime and generated codecs.
pub fn describe(
  definition: Definition(a),
  description: String,
) -> Definition(a) {
  let Definition(runtime_codec, gleam_type, lower) = definition
  Definition(codec.describe(runtime_codec, description), gleam_type, lower)
}

/// Compile one canonical typed definition into Blueprint Value operations,
/// gleam/json-native text operations, a schema, and an interchangeable Codec.
/// Ordinary text decoding uses Blueprint's strict parser. An explicitly named
/// native decoder remains available for callers needing `gleam/json` parsing.
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
  use _ <- result.try(
    codec.check(runtime_codec) |> result.map_error(InvalidDefinition),
  )
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
        "gleam/json",
        "gleam/option",
        "json/blueprint/codec",
        "json/blueprint/internal/generated",
        "json/blueprint/value",
      ],
      lowered.imports,
    )
    |> unique_sorted
  use validated_imports <- result.try(validate_imports(type_reference, imports))
  case codec.schema(runtime_codec) {
    Error(codec.UnknownSchema) -> Error(UnknownSchema(name))
    Ok(schema) ->
      case schema_materialize.emit_schema_expression(schema, [name]) {
        Error(error) -> Error(translate_schema_error(error))
        Ok(schema_expression) -> {
          let declarations = lowered.declarations
          let encoder_name = "encode_" <> name
          let decoder_name = "decode_" <> name
          let json_encoder_name = "encode_" <> name <> "_json"
          let json_decoder_name = "decode_" <> name <> "_json"
          let native_json_decoder_name = json_decoder_name <> "_native"
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
            <> lowered.encoder
            <> "(item)\n}\n\n"
            <> "pub fn "
            <> decoder_name
            <> "(raw: value.Value) -> Result("
            <> type_reference.expression
            <> ", codec.DecodeError) {\n  "
            <> lowered.decoder
            <> "(raw)\n}\n\n"
            <> "pub fn "
            <> json_encoder_name
            <> "(item: "
            <> type_reference.expression
            <> ") -> Result(String, codec.EncodeError) {\n"
            <> "  case "
            <> lowered.native_encoder
            <> "(item) {\n    Error(error) -> Error(error)\n    Ok(encoded) -> Ok(json.to_string(encoded))\n  }\n}\n\n"
            <> "pub fn "
            <> json_decoder_name
            <> "(source: String) -> Result("
            <> type_reference.expression
            <> ", codec.DecodeError) {\n"
            <> "  codec.decode_json("
            <> codec_name
            <> "(), source)\n}\n\n"
            <> "pub fn "
            <> native_json_decoder_name
            <> "(source: String) -> Result("
            <> type_reference.expression
            <> ", json.DecodeError) {\n"
            <> "  generated.decode_json_native(source, "
            <> lowered.native_decoder
            <> ", "
            <> lowered.placeholder
            <> ")\n}\n\n"
            <> "pub fn "
            <> schema_name
            <> "() -> codec.Schema {\n  "
            <> schema_name
            <> "_value\n}\n\n"
            <> "pub fn "
            <> codec_name
            <> "() -> codec.Codec("
            <> type_reference.expression
            <> ") {\n  codec.custom(\n    encode: "
            <> encoder_name
            <> ",\n    decode: "
            <> decoder_name
            <> ",\n    schema: option.Some("
            <> schema_name
            <> "()),\n    placeholder: "
            <> lowered.placeholder
            <> ",\n  )\n}\n"
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
