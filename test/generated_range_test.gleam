// Generated integer helpers preserve exact projection and range errors.
import gleam/list
import gleeunit/should
import json/blueprint/codec
import json/blueprint/internal/generated
import json/blueprint/value

fn compare(
  minimum: Int,
  maximum: Int,
  text: String,
) -> Result(Int, codec.DecodeError) {
  let assert Ok(raw) = value.parse_native(text, value.default_limits())
  let actual = generated.decode_strict_integer_between(minimum, maximum, raw)
  actual
  |> should.equal(codec.decode_json(
    codec.integer_between(minimum, maximum),
    text,
  ))
  actual
}

pub fn strict_integer_range_fast_and_fallback_test() {
  list.each([#(-10, 10), #(-10, -1), #(1, 10), #(0, 0)], fn(bounds) {
    list.each(
      [
        "-11",
        "-10",
        "-1",
        "0",
        "1",
        "10",
        "11",
        "1.0",
        "-1e1",
        "1e2",
        "-0",
        "1.00000000000000001",
        "100.5",
        "-100.5",
        "100000000000000000000000000000000000000000000000000",
        "-100000000000000000000000000000000000000000000000000",
        "1e400",
        "true",
        "null",
        "\"1\"",
      ],
      fn(text) {
        let _ = compare(bounds.0, bounds.1, text)
        Nil
      },
    )
  })
  compare(-10, 10, "100.5")
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedInt)))
  compare(-10, 10, "-100.5")
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedInt)))
  compare(-10, 10, "1e400")
  |> should.equal(
    Error(codec.DecodeError([], codec.IntegerOutsideRange(-10, 10))),
  )
}

@target(erlang)
pub fn strict_integer_range_wider_than_default_projection_test() {
  let maximum = 1_000_000_000_000_000_000_000_000_000_000
  let item = 12_345_678_901_234_567_890_123_456
  compare(-maximum, maximum, "12345678901234567890123456")
  |> should.equal(Ok(item))
  compare(-maximum, maximum, "-12345678901234567890123456")
  |> should.equal(Ok(-item))
  compare(-maximum, maximum, "12345678901234567890123456.0")
  |> should.equal(Ok(item))
  compare(-maximum, maximum, "12345678901234567890123456.1")
  |> should.equal(Error(codec.DecodeError([], codec.ExpectedInt)))
  compare(-maximum, maximum, "1e31")
  |> should.equal(
    Error(codec.DecodeError([], codec.IntegerOutsideRange(-maximum, maximum))),
  )
}
