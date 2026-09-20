import gleam/int
import gleam/list
import gleam/string
import json/blueprint/codec

pub type SchemaExport {
  SchemaExport(name: String, schema: codec.Schema)
}

pub type MaterializationError {
  UnknownSchema(accessor: String)
  InvalidModuleName(module_path: String, reason: String)
  InvalidAccessorName(name: String, reason: String)
  DuplicateAccessor(name: String)
  UnsupportedConstructor(path: List(String), constructor: String)
}

pub type GeneratedModule {
  GeneratedModule(path: String, content: String)
}

const gleam_keywords = [
  "as", "assert", "auto", "case", "const", "echo", "else", "external", "fn",
  "if", "import", "let", "opaque", "panic", "pub", "todo", "try", "type", "use",
]

pub fn is_gleam_keyword(name: String) -> Bool {
  list.contains(gleam_keywords, name)
}

pub fn validate_accessor_name(
  name: String,
) -> Result(String, MaterializationError) {
  case string.is_empty(name) {
    True -> Error(InvalidAccessorName(name, "accessor name cannot be empty"))
    False ->
      case is_gleam_keyword(name) {
        True ->
          Error(InvalidAccessorName(name, "accessor name cannot be a keyword"))
        False ->
          case is_valid_lower_identifier(name) {
            True -> Ok(name)
            False ->
              Error(InvalidAccessorName(
                name,
                "accessor name must start with [a-z] and contain only [a-z0-9_]",
              ))
          }
      }
  }
}

pub fn validate_module_path(
  path: String,
) -> Result(String, MaterializationError) {
  case string.is_empty(path) {
    True -> Error(InvalidModuleName(path, "module path cannot be empty"))
    False -> {
      let segments = string.split(path, "/")
      let are_segments_valid =
        list.all(segments, fn(seg) {
          !string.is_empty(seg)
          && !is_gleam_keyword(seg)
          && is_valid_lower_identifier(seg)
        })
      case are_segments_valid {
        True -> Ok(path)
        False ->
          Error(InvalidModuleName(
            path,
            "module path segments must be non-empty, lowercase identifiers, and not keywords",
          ))
      }
    }
  }
}

fn is_valid_lower_identifier(text: String) -> Bool {
  let graphemes = string.to_graphemes(text)
  case graphemes {
    [] -> False
    [first, ..rest] ->
      is_lower_alpha(first)
      && list.all(rest, fn(ch) {
        is_lower_alpha(ch) || is_digit(ch) || ch == "_"
      })
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

pub fn escape_string_literal(raw: String) -> String {
  let graphemes = string.to_graphemes(raw)
  let escaped_chars =
    list.map(graphemes, fn(g) {
      case g {
        "\"" -> "\\\""
        "\\" -> "\\\\"
        "\n" -> "\\n"
        "\r" -> "\\r"
        "\t" -> "\\t"
        "\f" -> "\\f"
        other -> other
      }
    })
  "\"" <> string.join(escaped_chars, "") <> "\""
}

pub fn from_codec(
  name: String,
  c: codec.Codec(a),
) -> Result(SchemaExport, MaterializationError) {
  case validate_accessor_name(name) {
    Error(err) -> Error(err)
    Ok(valid_name) ->
      case codec.schema(c) {
        Error(codec.UnknownSchema) -> Error(UnknownSchema(valid_name))
        Ok(s) -> Ok(SchemaExport(valid_name, s))
      }
  }
}

pub fn emit_schema_expression(
  schema: codec.Schema,
  path: List(String),
) -> Result(String, MaterializationError) {
  case schema {
    codec.StringSchema -> Ok("codec.StringSchema")
    codec.StringEnumSchema(labels) -> {
      let escaped_labels = list.map(labels, escape_string_literal)
      Ok(
        "codec.StringEnumSchema([" <> string.join(escaped_labels, ", ") <> "])",
      )
    }
    codec.IntSchema -> Ok("codec.IntSchema")
    codec.NumberSchema -> Ok("codec.NumberSchema")
    codec.BoolSchema -> Ok("codec.BoolSchema")
    codec.FieldSchema(name, inner) -> {
      let next_path = list.append(path, [name])
      case emit_schema_expression(inner, next_path) {
        Error(err) -> Error(err)
        Ok(inner_str) ->
          Ok(
            "codec.FieldSchema("
            <> escape_string_literal(name)
            <> ", "
            <> inner_str
            <> ")",
          )
      }
    }
    codec.ObjectSchema(properties) -> {
      emit_properties(properties, path, [])
    }
    codec.ListSchema(inner) -> {
      let next_path = list.append(path, ["*"])
      case emit_schema_expression(inner, next_path) {
        Error(err) -> Error(err)
        Ok(inner_str) -> Ok("codec.ListSchema(" <> inner_str <> ")")
      }
    }
    codec.PairSchema(left, right) -> {
      let left_path = list.append(path, ["0"])
      let right_path = list.append(path, ["1"])
      case emit_schema_expression(left, left_path) {
        Error(err) -> Error(err)
        Ok(left_str) ->
          case emit_schema_expression(right, right_path) {
            Error(err) -> Error(err)
            Ok(right_str) ->
              Ok("codec.PairSchema(" <> left_str <> ", " <> right_str <> ")")
          }
      }
    }
    codec.NullableSchema(inner) -> {
      let next_path = list.append(path, ["non_null"])
      case emit_schema_expression(inner, next_path) {
        Error(err) -> Error(err)
        Ok(inner_str) -> Ok("codec.NullableSchema(" <> inner_str <> ")")
      }
    }
    codec.TaggedSchema(left_tag, left, right_tag, right) -> {
      let left_path = list.append(path, [left_tag])
      let right_path = list.append(path, [right_tag])
      case emit_schema_expression(left, left_path) {
        Error(err) -> Error(err)
        Ok(left_str) ->
          case emit_schema_expression(right, right_path) {
            Error(err) -> Error(err)
            Ok(right_str) ->
              Ok(
                "codec.TaggedSchema("
                <> escape_string_literal(left_tag)
                <> ", "
                <> left_str
                <> ", "
                <> escape_string_literal(right_tag)
                <> ", "
                <> right_str
                <> ")",
              )
          }
      }
    }
    codec.IntegerRangeSchema(min, max) ->
      Ok(
        "codec.IntegerRangeSchema("
        <> int.to_string(min)
        <> ", "
        <> int.to_string(max)
        <> ")",
      )
    codec.NumberRangeSchema(_, _) ->
      Error(UnsupportedConstructor(path, "NumberRangeSchema"))
  }
}

fn emit_properties(
  properties: List(codec.PropertySchema),
  path: List(String),
  acc: List(String),
) -> Result(String, MaterializationError) {
  case properties {
    [] -> {
      let props_str = string.join(list.reverse(acc), ", ")
      Ok("codec.ObjectSchema([" <> props_str <> "])")
    }
    [codec.PropertySchema(name, required, schema), ..rest] -> {
      let next_path = list.append(path, [name])
      case emit_schema_expression(schema, next_path) {
        Error(err) -> Error(err)
        Ok(schema_str) -> {
          let req_str = case required {
            True -> "True"
            False -> "False"
          }
          let prop_str =
            "codec.PropertySchema("
            <> escape_string_literal(name)
            <> ", "
            <> req_str
            <> ", "
            <> schema_str
            <> ")"
          emit_properties(rest, path, [prop_str, ..acc])
        }
      }
    }
  }
}

pub fn materialize(
  module_path: String,
  exports: List(SchemaExport),
) -> Result(GeneratedModule, MaterializationError) {
  case validate_module_path(module_path) {
    Error(err) -> Error(err)
    Ok(valid_path) -> {
      case validate_and_check_exports(exports, []) {
        Error(err) -> Error(err)
        Ok(Nil) -> {
          // Canonical ordering rule: sort exports alphabetically by validated accessor name
          let sorted_exports =
            list.sort(exports, fn(a, b) { string.compare(a.name, b.name) })
          emit_functions(sorted_exports, [])
          |> fn(res) {
            case res {
              Error(err) -> Error(err)
              Ok(fn_bodies) -> {
                let content =
                  "// @generated by json_blueprint schema materialization\n"
                  <> "import json/blueprint/codec\n\n"
                  <> string.join(fn_bodies, "\n\n")
                  <> "\n"
                Ok(GeneratedModule(
                  path: valid_path <> ".gleam",
                  content: content,
                ))
              }
            }
          }
        }
      }
    }
  }
}

fn validate_and_check_exports(
  exports: List(SchemaExport),
  seen: List(String),
) -> Result(Nil, MaterializationError) {
  case exports {
    [] -> Ok(Nil)
    [SchemaExport(name, _), ..rest] ->
      case validate_accessor_name(name) {
        Error(err) -> Error(err)
        Ok(valid_name) ->
          case list.contains(seen, valid_name) {
            True -> Error(DuplicateAccessor(valid_name))
            False -> validate_and_check_exports(rest, [valid_name, ..seen])
          }
      }
  }
}

fn emit_functions(
  exports: List(SchemaExport),
  acc: List(String),
) -> Result(List(String), MaterializationError) {
  case exports {
    [] -> Ok(list.reverse(acc))
    [SchemaExport(name, s), ..rest] ->
      case emit_schema_expression(s, [name]) {
        Error(err) -> Error(err)
        Ok(expr_str) -> {
          let fn_code =
            "pub fn " <> name <> "() -> codec.Schema {\n  " <> expr_str <> "\n}"
          emit_functions(rest, [fn_code, ..acc])
        }
      }
  }
}
