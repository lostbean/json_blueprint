import gleam/io
import json/blueprint/internal/schema_materialize
import materialize_fixtures

@external(erlang, "file_test_ffi", "write_file")
@external(javascript, "./file_test_ffi.mjs", "write_file")
pub fn write_file(path: String, content: String) -> Result(Nil, String)

pub fn main() -> Nil {
  let res = generate_fixture()
  case res {
    Ok(path) -> io.println("Successfully generated schema fixture at: " <> path)
    Error(err) -> io.println("Failed to generate schema fixture: " <> err)
  }
}

pub fn generate_fixture() -> Result(String, String) {
  let order_c = materialize_fixtures.build_order_codec()
  let decision_c = materialize_fixtures.build_decision_codec()

  case schema_materialize.from_codec("order_schema", order_c) {
    Error(_) -> Error("failed to derive order_schema export")
    Ok(order_export) ->
      case schema_materialize.from_codec("decision_schema", decision_c) {
        Error(_) -> Error("failed to derive decision_schema export")
        Ok(decision_export) -> {
          let module_name = "generated/schema_catalog"
          case
            schema_materialize.materialize(module_name, [
              order_export,
              decision_export,
            ])
          {
            Error(_) -> Error("materialization failed")
            Ok(gen_mod) -> {
              let fixture_dir = "build/schema-materialization/fixture"
              let gleam_toml =
                "name = \"fixture\"\n"
                <> "version = \"0.1.0\"\n\n"
                <> "[dependencies]\n"
                <> "gleam_stdlib = \">= 0.60.0 and < 2.0.0\"\n"
                <> "json_blueprint = { path = \"../../..\" }\n\n"
                <> "[dev-dependencies]\n"
                <> "gleeunit = \">= 1.0.0 and < 2.0.0\"\n"

              let src_fixture = "pub fn main() {\n" <> "  Nil\n" <> "}\n"

              let test_code = fixture_test_source()

              let _ = write_file(fixture_dir <> "/gleam.toml", gleam_toml)
              let _ =
                write_file(fixture_dir <> "/src/fixture.gleam", src_fixture)
              let _ =
                write_file(
                  fixture_dir <> "/src/" <> gen_mod.path,
                  gen_mod.content,
                )
              let _ =
                write_file(fixture_dir <> "/test/fixture_test.gleam", test_code)

              Ok(fixture_dir)
            }
          }
        }
      }
  }
}

fn fixture_test_source() -> String {
  "import gleeunit
import gleeunit/should
import generated/schema_catalog
import json/blueprint/codec
import json/blueprint/number

pub fn main() {
  gleeunit.main()
}

pub type OrderStatus {
  Pending
  Processing
  ShippedQuoted
  DeliveredUnicode
}

pub type Order {
  Order(
    order_id: Int,
    items: List(#(String, Int)),
    note: codec.Optional(codec.Nullable(String)),
    active: Bool,
    status: OrderStatus,
  )
}

fn build_order_codec() -> codec.Codec(Order) {
  let assert Ok(status_c) =
    codec.string_enum([
      #(\"pending\", Pending),
      #(\"processing\", Processing),
      #(\"shipped\\n\\r\\f\\t\\\"quoted\\\"\", ShippedQuoted),
      #(\"delivered 🚀 fn\", DeliveredUnicode),
    ])

  let assert Ok(id_c) = codec.integer_between(1, 999_999)
  let items_c = codec.list(codec.pair(codec.string(), codec.int()))
  let note_c = codec.nullable(codec.string())

  let assert Ok(p1) =
    codec.combine(
      codec.required(\"order_id\", id_c),
      codec.required(\"items_\\\"list\\\"\", items_c),
    )
  let assert Ok(p2) =
    codec.combine(
      p1,
      codec.optional(\"customer\\n\\r\\f\\t\\\\note\", note_c),
    )
  let assert Ok(p3) =
    codec.combine(
      p2,
      codec.required(\"type\", codec.bool()),
    )
  let assert Ok(full_props) =
    codec.combine(
      p3,
      codec.required(\"status\", status_c),
    )

  codec.imap(
    codec.object(full_props),
    fn(raw: #(#(#(#(Int, List(#(String, Int))), codec.Optional(codec.Nullable(String))), Bool), OrderStatus)) {
      Order(raw.0.0.0.0, raw.0.0.0.1, raw.0.0.1, raw.0.1, raw.1)
    },
    fn(o: Order) {
      #(#(#(#(o.order_id, o.items), o.note), o.active), o.status)
    },
  )
}

pub type ApprovePayload {
  ApprovePayload(quantity: Int, ratio: number.Number)
}

pub type DeclinePayload {
  DeclinePayload(reason: String, code: Int)
}

pub type Decision {
  Approve(ApprovePayload)
  Decline(DeclinePayload)
}

fn build_decision_codec() -> codec.Codec(Decision) {
  let assert Ok(quantity_c) = codec.integer_between(1, 100)
  let ratio_c = codec.number()

  let assert Ok(approve_props) =
    codec.combine(
      codec.required(\"quantity\", quantity_c),
      codec.required(\"ratio\", ratio_c),
    )
  let approve_obj =
    codec.imap(
      codec.object(approve_props),
      fn(pair: #(Int, number.Number)) { ApprovePayload(pair.0, pair.1) },
      fn(a: ApprovePayload) { #(a.quantity, a.ratio) },
    )

  let assert Ok(decline_props) =
    codec.combine(
      codec.required(\"reason\", codec.string()),
      codec.required(\"code\", codec.int()),
    )
  let decline_obj =
    codec.imap(
      codec.object(decline_props),
      fn(pair: #(String, Int)) { DeclinePayload(pair.0, pair.1) },
      fn(d: DeclinePayload) { #(d.reason, d.code) },
    )

  let assert Ok(tagged_c) =
    codec.tagged(
      \"approve \\\"let\\\"\",
      approve_obj,
      \"decline \\n\\r\\f\\t\\\\import\",
      decline_obj,
    )

  codec.imap(
    tagged_c,
    fn(choice) {
      case choice {
        codec.Left(app) -> Approve(app)
        codec.Right(dec) -> Decline(dec)
      }
    },
    fn(d: Decision) {
      case d {
        Approve(app) -> codec.Left(app)
        Decline(dec) -> codec.Right(dec)
      }
    },
  )
}

pub fn order_schema_structural_identity_test() {
  let order_c = build_order_codec()
  let assert Ok(expected_schema) = codec.schema(order_c)
  let generated_schema = schema_catalog.order_schema()

  generated_schema
  |> should.equal(expected_schema)
}

pub fn decision_schema_structural_identity_test() {
  let decision_c = build_decision_codec()
  let assert Ok(expected_schema) = codec.schema(decision_c)
  let generated_schema = schema_catalog.decision_schema()

  generated_schema
  |> should.equal(expected_schema)
}
"
}
