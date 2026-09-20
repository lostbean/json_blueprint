import gleeunit/should
import json/blueprint/number
import json/blueprint/value

pub fn value_constructors_test() {
  value.null()
  |> should.equal(value.Null)

  value.bool(True)
  |> should.equal(value.Bool(True))

  value.bool(False)
  |> should.equal(value.Bool(False))

  value.string("test-string")
  |> should.equal(value.String("test-string"))

  let assert Ok(num) = number.from_int(42)
  value.number(num)
  |> should.equal(value.Number(num))

  value.array([value.string("item"), value.null()])
  |> should.equal(value.Array([value.String("item"), value.Null]))
}

pub fn value_object_key_policy_test() {
  value.object([], value.RejectDuplicates)
  |> should.equal(Ok(value.Object([])))

  value.object(
    [#("first", value.string("a")), #("second", value.string("b"))],
    value.RejectDuplicates,
  )
  |> should.equal(
    Ok(
      value.Object([
        #("first", value.String("a")),
        #("second", value.String("b")),
      ]),
    ),
  )

  value.object(
    [
      #("duplicate", value.string("first")),
      #("other", value.string("middle")),
      #("duplicate", value.string("second")),
    ],
    value.RejectDuplicates,
  )
  |> should.equal(Error(value.DuplicateObjectKey("duplicate")))
}
