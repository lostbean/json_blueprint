//// Every Gleam snippet of the README, verbatim, compiled and run. The
//// README test below fails when a snippet drifts from this file.

import gleam/option.{type Option}
import gleam/result
import json/blueprint/codec.{type Codec}

pub type Role {
  Admin
  Member
}

pub type User {
  User(name: String, age: Int, email: Option(String), role: Role)
}

pub fn user_codec() -> Codec(User) {
  let role = codec.string_enum([#("admin", Admin), #("member", Member)])
  use name <- codec.field("name", codec.string(), fn(u: User) { u.name })
  use age <- codec.field("age", codec.integer_between(0, 150), fn(u: User) {
    u.age
  })
  use email <- codec.optional_field("email", codec.string(), fn(u: User) {
    u.email
  })
  use role <- codec.field("role", role, fn(u: User) { u.role })
  codec.success(User(name:, age:, email:, role:))
}

pub fn round_trip() -> Result(User, String) {
  let text = "{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}"
  use user <- result.try(
    codec.decode_json(user_codec(), text)
    |> result.map_error(codec.describe_decode_error),
  )
  let assert Ok(_text) = codec.encode_json(user_codec(), user)
  let assert Ok(_schema) = codec.schema_json(user_codec())
  Ok(user)
}

import gleam/json
import gleam/list
import gleam/string
import json/blueprint/contract
import json/blueprint/value

pub type Shape {
  Circle(radius: Int)
  Label(text: String)
  Empty
}

pub fn shape_codec() -> Codec(Shape) {
  codec.union({
    use circle <- codec.variant("circle", codec.int(), Circle)
    use label <- codec.variant("label", codec.string(), Label)
    use empty <- codec.unit_variant("empty", Empty)
    codec.match(fn(shape) {
      case shape {
        Circle(radius) -> circle(radius)
        Label(text) -> label(text)
        Empty -> empty
      }
    })
  })
}

pub type Email {
  Email(address: String)
}

pub fn email_codec() -> Codec(Email) {
  codec.try_map(
    codec.string(),
    decode: fn(text) {
      case string.contains(text, "@") {
        True -> Ok(Email(text))
        False -> Error("an email address needs an @")
      }
    },
    encode: fn(email: Email) { Ok(email.address) },
    placeholder: Email(""),
  )
}

import gleam/int

pub type Order {
  Order(items: List(Int), total: Int)
}

pub fn order_codec() -> Codec(Order) {
  use items <- codec.field("items", codec.list(codec.int()), fn(o: Order) {
    o.items
  })
  use total <- codec.field("total", total_of(items), fn(o: Order) { o.total })
  codec.success(Order(items:, total:))
}

fn total_of(items: List(Int)) -> Codec(Int) {
  let sum = int.sum(items)
  let check = fn(total) {
    case total == sum {
      True -> Ok(total)
      False ->
        Error(
          "total "
          <> int.to_string(total)
          <> " differs from the item sum "
          <> int.to_string(sum),
        )
    }
  }
  codec.try_map(codec.int(), decode: check, encode: check, placeholder: sum)
}

pub fn explain(text: String) -> String {
  case codec.decode_json(user_codec(), text) {
    Ok(_) -> "ok"
    Error(error) ->
      case codec.is_limit_exceeded(error) {
        True -> "the request is too large"
        False -> codec.describe_decode_error(error)
      }
  }
}

pub fn status_codec(
  labels: List(String),
) -> Result(Codec(String), codec.DefinitionError) {
  codec.string_enum(list.map(labels, fn(label) { #(label, label) }))
  |> codec.check
}

pub fn with_gleam_json(user: User) -> Result(User, json.DecodeError) {
  let assert Ok(encoded) = codec.to_json(user_codec(), user)
  json.parse(json.to_string(encoded), codec.decoder(user_codec()))
}

pub fn decode_many(text: String) -> Result(List(User), codec.DecodeError) {
  let limits =
    value.default_limits()
    |> value.with_max_bytes(8 * 1024 * 1024)
    |> value.with_max_elements(2_000_000)
  codec.decode_json_with_limits(codec.list(user_codec()), text, limits)
}

pub fn check_arguments(
  schema_text: String,
  arguments: String,
) -> Result(value.Value, String) {
  let limits = value.default_limits()
  use remote <- result.try(
    contract.parse(schema_text, limits)
    |> result.map_error(contract.describe_load_error),
  )
  use parsed <- result.try(
    value.parse(arguments, limits)
    |> result.map_error(value.describe_parse_error),
  )
  contract.validate(remote, parsed)
  |> result.map(contract.value)
  |> result.map_error(contract.describe_validation_error)
}

// --- checks ------------------------------------------------------------------

import gleeunit/should

@external(erlang, "readme_test_ffi", "read_file_to_string")
@external(javascript, "./readme_test_ffi.mjs", "read_file_to_string")
fn read_file_to_string(path: String) -> Result(String, String)

pub fn readme_snippets_are_in_this_file_verbatim_test() {
  let assert Ok(readme) = read_file_to_string("README.md")
  let assert Ok(source) = read_file_to_string("test/readme_example_test.gleam")
  let snippets = gleam_snippets(string.replace(readme, "\r\n", "\n"), [])
  list.length(snippets) |> should.equal(9)
  snippets
  |> list.filter(fn(snippet) { !string.contains(source, snippet) })
  |> should.equal([])
}

fn gleam_snippets(text: String, found: List(String)) -> List(String) {
  case string.split_once(text, "```gleam\n") {
    Error(Nil) -> list.reverse(found)
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\n```") {
        Error(Nil) -> list.reverse(found)
        Ok(#(snippet, after)) -> gleam_snippets(after, [snippet, ..found])
      }
  }
}

pub fn round_trip_test() {
  round_trip() |> should.equal(Ok(User("Ada", 36, option.None, Admin)))
}

pub fn shape_codec_test() {
  codec.encode_json(shape_codec(), Circle(2))
  |> should.equal(Ok("{\"tag\":\"circle\",\"value\":2}"))
  codec.decode_json(shape_codec(), "{\"tag\":\"empty\"}")
  |> should.equal(Ok(Empty))
}

pub fn email_codec_test() {
  codec.decode_json(email_codec(), "\"a@b\"") |> should.equal(Ok(Email("a@b")))
  codec.decode_json(email_codec(), "\"ab\"")
  |> should.equal(
    Error(codec.DecodeError([], codec.Custom("an email address needs an @"))),
  )
}

pub fn email_message_test() {
  let assert Error(error) = codec.decode_json(email_codec(), "\"ab\"")
  codec.describe_decode_error(error)
  |> should.equal("$: an email address needs an @")
}

pub fn order_codec_test() {
  codec.decode_json(order_codec(), "{\"items\":[1,2],\"total\":3}")
  |> should.equal(Ok(Order([1, 2], 3)))
  let assert Error(error) =
    codec.decode_json(order_codec(), "{\"items\":[1,2],\"total\":4}")
  error
  |> should.equal(codec.DecodeError(
    [codec.Field("total")],
    codec.Custom("total 4 differs from the item sum 3"),
  ))
  codec.describe_decode_error(error)
  |> should.equal("$[\"total\"]: total 4 differs from the item sum 3")
  let assert Error(error) = codec.encode_json(order_codec(), Order([1, 2], 4))
  codec.describe_encode_error(error)
  |> should.equal("$[\"total\"]: total 4 differs from the item sum 3")
  codec.encode_json(order_codec(), Order([1, 2], 3))
  |> should.equal(Ok("{\"items\":[1,2],\"total\":3}"))
  let assert Ok(schema) = codec.schema_json(order_codec())
  let assert Ok(expected) =
    {
      use items <- codec.field("items", codec.list(codec.int()), fn(o: Order) {
        o.items
      })
      use total <- codec.field("total", codec.int(), fn(o: Order) { o.total })
      codec.success(Order(items:, total:))
    }
    |> codec.schema_json
  schema |> should.equal(expected)
}

pub fn explain_test() {
  explain("{\"name\":\"Ada\",\"age\":36,\"role\":\"admin\"}")
  |> should.equal("ok")
  explain("{\"name\":\"Ada\",\"age\":360,\"role\":\"admin\"}")
  |> should.equal("$[\"age\"]: integer outside range 0 to 150")
  explain("[" <> string.repeat(" ", 1_048_576) <> "]")
  |> should.equal("the request is too large")
}

pub fn status_codec_test() {
  let assert Ok(status) = status_codec(["open", "closed"])
  codec.decode_json(status, "\"open\"") |> should.equal(Ok("open"))
  status_codec(["open", "open"])
  |> should.equal(Error(codec.DuplicateEnumLabel("open")))
}

pub fn with_gleam_json_test() {
  let user = User("Ada", 36, option.Some("ada@example.com"), Member)
  with_gleam_json(user) |> should.equal(Ok(user))
}

pub fn decode_many_test() {
  let assert Ok(text) =
    codec.encode_json(codec.list(user_codec()), [
      User("Ada", 36, option.None, Admin),
    ])
  decode_many(text) |> should.equal(Ok([User("Ada", 36, option.None, Admin)]))
}

pub fn check_arguments_test() {
  let schema =
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\","
    <> "\"type\":\"object\",\"properties\":{\"limit\":"
    <> "{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},"
    <> "\"required\":[\"limit\"],\"additionalProperties\":false}"
  check_arguments(schema, "{\"limit\":3}") |> should.be_ok
  check_arguments(schema, "{\"limit\":30}")
  |> should.equal(Error("$[\"limit\"]: integer outside range 1 to 10"))
}
