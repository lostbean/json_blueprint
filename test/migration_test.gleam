import gleeunit/should
import json/blueprint as legacy
import json/blueprint/codec
import json/blueprint/migration
import json/blueprint/number
import json/blueprint/value

pub type LegacyPerson {
  LegacyPerson(name: String, age: Int)
}

pub type LegacyMessage {
  LegacyMessage(msg_type: String, data: String)
}

fn int_num(n: Int) -> number.Number {
  let assert Ok(num) = number.from_int(n)
  num
}

pub fn legacy_migration_contract_test() {
  let legacy_person_decoder =
    legacy.decode2(
      LegacyPerson,
      legacy.field("name", legacy.string()),
      legacy.field("age", legacy.int()),
    )

  let person_encoder = fn(p: LegacyPerson) {
    Ok(
      value.Object([
        #("name", value.String(p.name)),
        #("age", value.Number(int_num(p.age))),
      ]),
    )
  }

  let adapted = migration.adapt(legacy_person_decoder, person_encoder)

  // 1. Schema unavailable
  codec.schema(adapted)
  |> should.equal(Error(codec.UnknownSchema))

  // 2. Exact roundtrip through adapted codec
  let alice = LegacyPerson("Alice", 30)
  let assert Ok(encoded) = codec.encode(adapted, alice)
  codec.decode(adapted, encoded)
  |> should.equal(Ok(alice))

  // 3. 1.7.1 permissive extra fields acceptance preserved
  let input_with_extra =
    value.Object([
      #("name", value.String("Bob")),
      #("age", value.Number(int_num(25))),
      #("extra_field", value.String("ignored_by_1_7_1")),
    ])
  codec.decode(adapted, input_with_extra)
  |> should.equal(Ok(LegacyPerson("Bob", 25)))

  // 4. Missing required field rejected
  let input_missing_age = value.Object([#("name", value.String("Charlie"))])
  codec.decode(adapted, input_missing_age)
  |> should.equal(
    Error(
      codec.CannotDecode(codec.CustomDecodeReason(
        "json_blueprint 1.7.1 rejected the Value",
      )),
    ),
  )

  // 5. Legacy type/data envelope preserved
  let legacy_msg_decoder =
    legacy.decode2(
      LegacyMessage,
      legacy.field("type", legacy.string()),
      legacy.field("data", legacy.string()),
    )

  let msg_encoder = fn(m: LegacyMessage) {
    Ok(
      value.Object([
        #("type", value.String(m.msg_type)),
        #("data", value.String(m.data)),
      ]),
    )
  }

  let adapted_msg = migration.adapt(legacy_msg_decoder, msg_encoder)
  let msg = LegacyMessage("greeting", "hello world")
  let assert Ok(encoded_msg) = codec.encode(adapted_msg, msg)
  codec.decode(adapted_msg, encoded_msg)
  |> should.equal(Ok(msg))
}
