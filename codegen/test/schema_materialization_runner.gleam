import gleam/io
import json/blueprint/codegen/internal/schema_materialize
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
  "import gleam/option.{type Option}
import gleeunit
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
    note: Option(Option(String)),
    active: Bool,
    status: OrderStatus,
  )
}

fn build_order_codec() -> codec.Codec(Order) {
  let status_c =
    codec.string_enum([
      #(\"pending\", Pending),
      #(\"processing\", Processing),
      #(\"shipped\\n\\r\\f\\t\\\"quoted\\\"\", ShippedQuoted),
      #(\"delivered 🚀 fn\", DeliveredUnicode),
    ])
  let items_c = codec.list(codec.pair(codec.string(), codec.int()))
  use order_id <- codec.field(
    \"order_id\",
    codec.integer_between(1, 999_999),
    fn(o: Order) { o.order_id },
  )
  use items <- codec.field(\"items_\\\"list\\\"\", items_c, fn(o: Order) { o.items })
  use note <- codec.optional_field(
    \"customer\\n\\r\\f\\t\\\\note\",
    codec.nullable(codec.string()),
    fn(o: Order) { o.note },
  )
  use active <- codec.field(\"type\", codec.bool(), fn(o: Order) { o.active })
  use status <- codec.field(\"status\", status_c, fn(o: Order) { o.status })
  codec.success(Order(order_id:, items:, note:, active:, status:))
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
  Defer
}

fn build_decision_codec() -> codec.Codec(Decision) {
  let approve = {
    use quantity <- codec.field(
      \"quantity\",
      codec.integer_between(1, 100),
      fn(a: ApprovePayload) { a.quantity },
    )
    use ratio <- codec.field(\"ratio\", codec.number(), fn(a: ApprovePayload) {
      a.ratio
    })
    codec.success(ApprovePayload(quantity:, ratio:))
  }
  let decline = {
    use reason <- codec.field(\"reason\", codec.string(), fn(d: DeclinePayload) {
      d.reason
    })
    use code <- codec.field(\"code\", codec.int(), fn(d: DeclinePayload) {
      d.code
    })
    codec.success(DeclinePayload(reason:, code:))
  }
  codec.union({
    use approve <- codec.variant(\"approve \\\"let\\\"\", approve, Approve)
    use decline <- codec.variant(\"decline \\n\\r\\f\\t\\\\import\", decline, Decline)
    use defer <- codec.unit_variant(\"defer\", Defer)
    codec.match(fn(decision) {
      case decision {
        Approve(payload) -> approve(payload)
        Decline(payload) -> decline(payload)
        Defer -> defer
      }
    })
  })
}

pub fn order_schema_structural_identity_test() {
  let assert Ok(expected_schema) = codec.schema(build_order_codec())
  schema_catalog.order_schema()
  |> should.equal(expected_schema)
}

pub fn decision_schema_structural_identity_test() {
  let assert Ok(expected_schema) = codec.schema(build_decision_codec())
  schema_catalog.decision_schema()
  |> should.equal(expected_schema)
}
"
}
