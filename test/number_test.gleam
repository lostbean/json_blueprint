@target(erlang)
import gleeunit/should
@target(erlang)
import json/blueprint/number

@target(erlang)
pub fn exact_number_kernel_test() {
  let assert Ok(limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(int_limit) = number.integer_projection_limit(50)

  let assert Ok(num1) = number.parse_number(limits, "1.2300e2")
  number.number_text(num1)
  |> should.equal("1.23e2")

  let assert Ok(num2) = number.parse_number(limits, "123")
  number.compare(num1, num2)
  |> should.equal(number.EqualTo)

  number.to_int_exact(num1, int_limit)
  |> should.equal(Ok(123))
}

@target(erlang)
pub fn number_resource_limits_test() {
  let assert Ok(short_token_limits) = number.number_limits(5, 100, 1000)
  number.parse_number(short_token_limits, "123456")
  |> should.equal(Error(number.TokenTooLong))

  let assert Ok(few_digits_limits) = number.number_limits(100, 3, 1000)
  number.parse_number(few_digits_limits, "1234")
  |> should.equal(Error(number.TooManySignificandDigits))

  let assert Ok(small_exp_limits) = number.number_limits(100, 100, 5)
  number.parse_number(small_exp_limits, "1e10")
  |> should.equal(Error(number.ExponentOutOfRange))

  let assert Ok(default_limits) = number.number_limits(100, 100, 100)
  number.parse_number(default_limits, "1.2.3")
  |> should.equal(Error(number.InvalidSyntax))
}

@target(erlang)
pub fn integer_projection_limits_test() {
  let assert Ok(limits) = number.number_limits(1024, 100, 1000)
  let assert Ok(digit_limit) = number.integer_projection_limit(2)

  let assert Ok(fractional) = number.parse_number(limits, "1.23")
  number.to_int_exact(fractional, digit_limit)
  |> should.equal(Error(number.FractionalInteger))

  let assert Ok(too_large) = number.parse_number(limits, "123")
  number.to_int_exact(too_large, digit_limit)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
}
