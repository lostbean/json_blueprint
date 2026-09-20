import gleam/string
import gleeunit/should
import json/blueprint/number

@external(erlang, "number_test_ffi", "float_from_hex")
@external(javascript, "./number_test_ffi.mjs", "float_from_hex")
fn float_from_hex(hex: String) -> Float

@external(erlang, "number_test_ffi", "float_to_bits_hex")
@external(javascript, "./number_test_ffi.mjs", "float_to_bits_hex")
fn float_to_bits_hex(value: Float) -> String

@external(erlang, "number_test_ffi", "call_from_int_raw")
@external(javascript, "./number_test_ffi.mjs", "call_from_int_raw")
fn call_from_int_raw(
  from_int_fn: fn(Int) -> Result(number.Number, number.IntegerConstructionError),
  kind: String,
) -> Result(number.Number, number.IntegerConstructionError)

fn default_limits() -> number.NumberLimits {
  let assert Ok(limits) = number.number_limits(64, 32, 1200)
  limits
}

fn default_projection_limit() -> number.IntegerProjectionLimit {
  let assert Ok(limit) = number.integer_projection_limit(24)
  limit
}

@target(erlang)
fn assert_pow2_53_int_projection(
  num: number.Number,
  limit: number.IntegerProjectionLimit,
) {
  number.to_int_exact(num, limit)
  |> should.equal(Ok(9_007_199_254_740_992))
}

@target(javascript)
fn assert_pow2_53_int_projection(
  num: number.Number,
  limit: number.IntegerProjectionLimit,
) {
  number.to_int_exact(num, limit)
  |> should.equal(Error(number.UnsupportedNativeInteger))
}

@target(erlang)
fn assert_pow2_53_p1_int_projection(
  num: number.Number,
  limit: number.IntegerProjectionLimit,
) {
  number.to_int_exact(num, limit)
  |> should.equal(Ok(9_007_199_254_740_993))
}

@target(javascript)
fn assert_pow2_53_p1_int_projection(
  num: number.Number,
  limit: number.IntegerProjectionLimit,
) {
  number.to_int_exact(num, limit)
  |> should.equal(Error(number.UnsupportedNativeInteger))
}

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

  let assert Ok(def_limits) = number.number_limits(100, 100, 100)
  number.parse_number(def_limits, "1.2.3")
  |> should.equal(Error(number.InvalidSyntax))
}

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

pub fn limits_construction_errors_test() {
  number.number_limits(0, 1, 0)
  |> should.equal(Error(number.TokenLimitMustBePositive))

  number.number_limits(1, 0, 0)
  |> should.equal(Error(number.SignificandLimitMustBePositive))

  number.number_limits(1, 1, -1)
  |> should.equal(Error(number.ExponentLimitMustBeNonnegative))

  number.integer_projection_limit(0)
  |> should.equal(Error(number.IntegerDigitLimitMustBePositive))
}

pub fn parse_syntax_and_resource_errors_test() {
  let limits = default_limits()

  // 16 rejected tokens from the 62-case oracle suite
  number.parse_number(limits, "+1")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, "01")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, "1.")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, ".1")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, "1e")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, "1e+")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, "--1")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, "1.2.3")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, string.repeat("9", 33) <> "e+")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, "١")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, " 1")
  |> should.equal(Error(number.InvalidSyntax))

  number.parse_number(limits, string.repeat("9", 33))
  |> should.equal(Error(number.TooManySignificandDigits))

  number.parse_number(limits, string.repeat("9", 33) <> "e1")
  |> should.equal(Error(number.TooManySignificandDigits))

  number.parse_number(limits, string.repeat("9", 65))
  |> should.equal(Error(number.TokenTooLong))

  number.parse_number(limits, "1e1201")
  |> should.equal(Error(number.ExponentOutOfRange))

  number.parse_number(limits, "0e1266")
  |> should.equal(Error(number.ExponentOutOfRange))
}

pub fn parse_accepted_numbers_test() {
  let limits = default_limits()
  let proj_limit = default_projection_limit()

  // 23 accepted tokens from oracle suite: check parse, canonical text, integrality, int & float projections

  // "-0" -> canonical "0", integer, int 0, float 0.0
  let assert Ok(neg_zero) = number.parse_number(limits, "-0")
  number.number_text(neg_zero) |> should.equal("0")
  number.is_integer(neg_zero) |> should.equal(True)
  number.to_int_exact(neg_zero, proj_limit) |> should.equal(Ok(0))
  number.to_float_exact(neg_zero) |> should.equal(Ok(0.0))

  // "0" -> canonical "0", integer, int 0, float 0.0
  let assert Ok(zero) = number.parse_number(limits, "0")
  number.number_text(zero) |> should.equal("0")
  number.is_integer(zero) |> should.equal(True)
  number.to_int_exact(zero, proj_limit) |> should.equal(Ok(0))
  number.to_float_exact(zero) |> should.equal(Ok(0.0))

  // "1" -> canonical "1", integer, int 1, float 1.0
  let assert Ok(one) = number.parse_number(limits, "1")
  number.number_text(one) |> should.equal("1")
  number.is_integer(one) |> should.equal(True)
  number.to_int_exact(one, proj_limit) |> should.equal(Ok(1))
  number.to_float_exact(one) |> should.equal(Ok(1.0))

  // "1.0" -> canonical "1", integer, int 1, float 1.0
  let assert Ok(one_p_zero) = number.parse_number(limits, "1.0")
  number.number_text(one_p_zero) |> should.equal("1")
  number.is_integer(one_p_zero) |> should.equal(True)
  number.to_int_exact(one_p_zero, proj_limit) |> should.equal(Ok(1))
  number.to_float_exact(one_p_zero) |> should.equal(Ok(1.0))

  // "10e-1" -> canonical "1", integer, int 1, float 1.0
  let assert Ok(ten_e_m1) = number.parse_number(limits, "10e-1")
  number.number_text(ten_e_m1) |> should.equal("1")
  number.is_integer(ten_e_m1) |> should.equal(True)
  number.to_int_exact(ten_e_m1, proj_limit) |> should.equal(Ok(1))
  number.to_float_exact(ten_e_m1) |> should.equal(Ok(1.0))

  // "100e-2" -> canonical "1", integer, int 1, float 1.0
  let assert Ok(hundred_e_m2) = number.parse_number(limits, "100e-2")
  number.number_text(hundred_e_m2) |> should.equal("1")
  number.is_integer(hundred_e_m2) |> should.equal(True)
  number.to_int_exact(hundred_e_m2, proj_limit) |> should.equal(Ok(1))
  number.to_float_exact(hundred_e_m2) |> should.equal(Ok(1.0))

  // "123.45" -> canonical "1.2345e2", non-integer, fractional, float inexact
  let assert Ok(dec123) = number.parse_number(limits, "123.45")
  number.number_text(dec123) |> should.equal("1.2345e2")
  number.is_integer(dec123) |> should.equal(False)
  number.to_int_exact(dec123, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(dec123)
  |> should.equal(Error(number.FloatInexact))

  // "1.2300e2" -> canonical "1.23e2", integer, int 123, float 123.0
  let assert Ok(num123) = number.parse_number(limits, "1.2300e2")
  number.number_text(num123) |> should.equal("1.23e2")
  number.is_integer(num123) |> should.equal(True)
  number.to_int_exact(num123, proj_limit) |> should.equal(Ok(123))
  number.to_float_exact(num123) |> should.equal(Ok(123.0))

  // "123.45e1201" -> canonical "1.2345e1203", integer, int digit limit exceeded, float overflow
  let assert Ok(large_exp) = number.parse_number(limits, "123.45e1201")
  number.number_text(large_exp) |> should.equal("1.2345e1203")
  number.is_integer(large_exp) |> should.equal(True)
  number.to_int_exact(large_exp, proj_limit)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
  number.to_float_exact(large_exp)
  |> should.equal(Error(number.FloatOverflow))

  // "100e-1202" -> canonical "1e-1200", non-integer, fractional, float underflow
  let assert Ok(tiny_exp) = number.parse_number(limits, "100e-1202")
  number.number_text(tiny_exp) |> should.equal("1e-1200")
  number.is_integer(tiny_exp) |> should.equal(False)
  number.to_int_exact(tiny_exp, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(tiny_exp)
  |> should.equal(Error(number.FloatUnderflow))

  // "0.5" -> canonical "5e-1", non-integer, fractional, float 0.5 (exact binary64)
  let assert Ok(half) = number.parse_number(limits, "0.5")
  number.number_text(half) |> should.equal("5e-1")
  number.is_integer(half) |> should.equal(False)
  number.to_int_exact(half, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(half) |> should.equal(Ok(0.5))

  // "0.1" -> canonical "1e-1", non-integer, fractional, float inexact
  let assert Ok(tenth) = number.parse_number(limits, "0.1")
  number.number_text(tenth) |> should.equal("1e-1")
  number.is_integer(tenth) |> should.equal(False)
  number.to_int_exact(tenth, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(tenth)
  |> should.equal(Error(number.FloatInexact))

  // "0.125" -> canonical "1.25e-1", non-integer, fractional, float 0.125 (exact binary64)
  let assert Ok(eighth) = number.parse_number(limits, "0.125")
  number.number_text(eighth) |> should.equal("1.25e-1")
  number.is_integer(eighth) |> should.equal(False)
  number.to_int_exact(eighth, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(eighth) |> should.equal(Ok(0.125))

  // "9007199254740992" (2^53) -> exact integer, exact float
  let assert Ok(pow2_53) = number.parse_number(limits, "9007199254740992")
  number.number_text(pow2_53) |> should.equal("9.007199254740992e15")
  number.is_integer(pow2_53) |> should.equal(True)
  assert_pow2_53_int_projection(pow2_53, proj_limit)
  number.to_float_exact(pow2_53)
  |> should.equal(Ok(9_007_199_254_740_992.0))

  // "9007199254740993" (2^53 + 1) -> exact integer, inexact float
  let assert Ok(pow2_53_p1) = number.parse_number(limits, "9007199254740993")
  number.number_text(pow2_53_p1) |> should.equal("9.007199254740993e15")
  number.is_integer(pow2_53_p1) |> should.equal(True)
  assert_pow2_53_p1_int_projection(pow2_53_p1, proj_limit)
  number.to_float_exact(pow2_53_p1)
  |> should.equal(Error(number.FloatInexact))

  // "123456789012345678901234567890" (30 digits) -> digit limit exceeded (limit is 24), float inexact
  let assert Ok(long_int) =
    number.parse_number(limits, "123456789012345678901234567890")
  number.number_text(long_int)
  |> should.equal("1.2345678901234567890123456789e29")
  number.is_integer(long_int) |> should.equal(True)
  number.to_int_exact(long_int, proj_limit)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
  number.to_float_exact(long_int)
  |> should.equal(Error(number.FloatInexact))

  // "1e400" -> integer, digit limit exceeded, float overflow
  let assert Ok(huge) = number.parse_number(limits, "1e400")
  number.number_text(huge) |> should.equal("1e400")
  number.is_integer(huge) |> should.equal(True)
  number.to_int_exact(huge, proj_limit)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
  number.to_float_exact(huge)
  |> should.equal(Error(number.FloatOverflow))

  // "1e-400" -> non-integer, fractional, float underflow
  let assert Ok(tiny) = number.parse_number(limits, "1e-400")
  number.number_text(tiny) |> should.equal("1e-400")
  number.is_integer(tiny) |> should.equal(False)
  number.to_int_exact(tiny, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(tiny)
  |> should.equal(Error(number.FloatUnderflow))

  // "1e-324" -> non-integer, fractional, float underflow
  let assert Ok(subnorm_dec) = number.parse_number(limits, "1e-324")
  number.number_text(subnorm_dec) |> should.equal("1e-324")
  number.is_integer(subnorm_dec) |> should.equal(False)
  number.to_int_exact(subnorm_dec, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(subnorm_dec)
  |> should.equal(Error(number.FloatUnderflow))

  // "1.7976931348623157e308" (max finite float) -> float exact, mathematically an integer
  let assert Ok(max_float_dec) =
    number.parse_number(limits, "1.7976931348623157e308")
  number.number_text(max_float_dec) |> should.equal("1.7976931348623157e308")
  number.is_integer(max_float_dec) |> should.equal(True)
  number.to_int_exact(max_float_dec, proj_limit)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
  number.to_float_exact(max_float_dec)
  |> should.equal(Error(number.FloatInexact))

  // "1.7976931348623159e308" -> float overflow, mathematically an integer
  let assert Ok(over_max_float) =
    number.parse_number(limits, "1.7976931348623159e308")
  number.number_text(over_max_float)
  |> should.equal("1.7976931348623159e308")
  number.is_integer(over_max_float) |> should.equal(True)
  number.to_int_exact(over_max_float, proj_limit)
  |> should.equal(Error(number.IntegerDigitLimitExceeded))
  number.to_float_exact(over_max_float)
  |> should.equal(Error(number.FloatOverflow))

  // "-0.5" -> canonical "-5e-1", float -0.5
  let assert Ok(neg_half) = number.parse_number(limits, "-0.5")
  number.number_text(neg_half) |> should.equal("-5e-1")
  number.is_integer(neg_half) |> should.equal(False)
  number.to_int_exact(neg_half, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(neg_half) |> should.equal(Ok(-0.5))

  // "-123.45" -> canonical "-1.2345e2", float inexact
  let assert Ok(neg_dec) = number.parse_number(limits, "-123.45")
  number.number_text(neg_dec) |> should.equal("-1.2345e2")
  number.is_integer(neg_dec) |> should.equal(False)
  number.to_int_exact(neg_dec, proj_limit)
  |> should.equal(Error(number.FractionalInteger))
  number.to_float_exact(neg_dec)
  |> should.equal(Error(number.FloatInexact))
}

pub fn compare_cases_test() {
  let limits = default_limits()
  let parse = fn(tok) {
    let assert Ok(n) = number.parse_number(limits, tok)
    n
  }

  // 11 comparison pairs from oracle suite
  number.compare(parse("1"), parse("1.0"))
  |> should.equal(number.EqualTo)

  number.compare(parse("-0"), parse("0"))
  |> should.equal(number.EqualTo)

  number.compare(parse("9007199254740993"), parse("9007199254740992"))
  |> should.equal(number.GreaterThan)

  number.compare(parse("-2"), parse("-10"))
  |> should.equal(number.GreaterThan)

  number.compare(parse("-1.01"), parse("-1.001"))
  |> should.equal(number.LessThan)

  number.compare(parse("-1"), parse("1"))
  |> should.equal(number.LessThan)

  number.compare(parse("1"), parse("0.99"))
  |> should.equal(number.GreaterThan)

  number.compare(parse("1.20"), parse("12e-1"))
  |> should.equal(number.EqualTo)

  number.compare(parse("1.01"), parse("1.001"))
  |> should.equal(number.GreaterThan)

  number.compare(parse("1e3"), parse("9.99e2"))
  |> should.equal(number.GreaterThan)

  number.compare(parse("0.001"), parse("0.01"))
  |> should.equal(number.LessThan)
}

pub fn from_float_exact_cases_test() {
  // 7 float fixtures from oracle suite + nonfinite check

  // 1. Positive Zero (0x0000000000000000)
  let pos_zero_f = float_from_hex("0000000000000000")
  let assert Ok(pos_zero_num) = number.from_float_exact(pos_zero_f)
  number.number_text(pos_zero_num) |> should.equal("0")
  let assert Ok(pos_zero_rt) = number.to_float_exact(pos_zero_num)
  float_to_bits_hex(pos_zero_rt) |> should.equal("0000000000000000")

  // 2. Negative Zero (0x8000000000000000) -> forgets sign, canonical "0", roundtrip bits 0x0000000000000000
  let neg_zero_f = float_from_hex("8000000000000000")
  let assert Ok(neg_zero_num) = number.from_float_exact(neg_zero_f)
  number.number_text(neg_zero_num) |> should.equal("0")
  let assert Ok(neg_zero_rt) = number.to_float_exact(neg_zero_num)
  float_to_bits_hex(neg_zero_rt) |> should.equal("0000000000000000")

  // 3. Half (0x3fe0000000000000, 0.5) -> canonical "5e-1", roundtrip bits 0x3fe0000000000000
  let half_f = float_from_hex("3fe0000000000000")
  let assert Ok(half_num) = number.from_float_exact(half_f)
  number.number_text(half_num) |> should.equal("5e-1")
  let assert Ok(half_rt) = number.to_float_exact(half_num)
  float_to_bits_hex(half_rt) |> should.equal("3fe0000000000000")

  // 4. Tenth (0x3fb999999999999a) -> exact binary rational decimal, roundtrip bits 0x3fb999999999999a
  let tenth_f = float_from_hex("3fb999999999999a")
  let assert Ok(tenth_num) = number.from_float_exact(tenth_f)
  number.number_text(tenth_num)
  |> should.equal("1.000000000000000055511151231257827021181583404541015625e-1")
  let assert Ok(tenth_rt) = number.to_float_exact(tenth_num)
  float_to_bits_hex(tenth_rt) |> should.equal("3fb999999999999a")

  // 5. Minimum Subnormal (0x0000000000000001, 5e-324) -> exact subnormal decimal, roundtrip bits 0x0000000000000001
  let subnorm_f = float_from_hex("0000000000000001")
  let assert Ok(subnorm_num) = number.from_float_exact(subnorm_f)
  number.number_text(subnorm_num)
  |> should.equal(
    "4.940656458412465441765687928682213723650598026143247644255856825006755072702087518652998363616359923797965646954457177309266567103559397963987747960107818781263007131903114045278458171678489821036887186360569987307230500063874091535649843873124733972731696151400317153853980741262385655911710266585566867681870395603106249319452715914924553293054565444011274801297099995419319894090804165633245247571478690147267801593552386115501348035264934720193790268107107491703332226844753335720832431936092382893458368060106011506169809753078342277318329247904982524730776375927247874656084778203734469699533647017972677717585125660551199131504891101451037862738167250955837389733598993664809941164205702637090279242767544565229087538682506419718265533447265625e-324",
  )
  let assert Ok(subnorm_rt) = number.to_float_exact(subnorm_num)
  float_to_bits_hex(subnorm_rt) |> should.equal("0000000000000001")

  // 6. Maximum Finite (0x7fefffffffffffff) -> exact binary64 max decimal, roundtrip bits 0x7fefffffffffffff
  let max_f = float_from_hex("7fefffffffffffff")
  let assert Ok(max_num) = number.from_float_exact(max_f)
  number.number_text(max_num)
  |> should.equal(
    "1.79769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368e308",
  )
  let assert Ok(max_rt) = number.to_float_exact(max_num)
  float_to_bits_hex(max_rt) |> should.equal("7fefffffffffffff")

  // 7. Negative Tenth (0xbfb999999999999a) -> negative exact decimal, roundtrip bits 0xbfb999999999999a
  let neg_tenth_f = float_from_hex("bfb999999999999a")
  let assert Ok(neg_tenth_num) = number.from_float_exact(neg_tenth_f)
  number.number_text(neg_tenth_num)
  |> should.equal(
    "-1.000000000000000055511151231257827021181583404541015625e-1",
  )
  let assert Ok(neg_tenth_rt) = number.to_float_exact(neg_tenth_num)
  float_to_bits_hex(neg_tenth_rt) |> should.equal("bfb999999999999a")
}

pub fn from_int_cases_test() {
  let proj_limit = default_projection_limit()

  // 0 -> canonical "0", int 0
  let assert Ok(zero) = number.from_int(0)
  number.number_text(zero) |> should.equal("0")
  number.to_int_exact(zero, proj_limit) |> should.equal(Ok(0))

  // 12 -> canonical "1.2e1", int 12
  let assert Ok(twelve) = number.from_int(12)
  number.number_text(twelve) |> should.equal("1.2e1")
  number.to_int_exact(twelve, proj_limit) |> should.equal(Ok(12))

  // 120 -> canonical "1.2e2", int 120
  let assert Ok(one_twenty) = number.from_int(120)
  number.number_text(one_twenty) |> should.equal("1.2e2")
  number.to_int_exact(one_twenty, proj_limit) |> should.equal(Ok(120))

  // -120 -> canonical "-1.2e2", int -120
  let assert Ok(neg_one_twenty) = number.from_int(-120)
  number.number_text(neg_one_twenty) |> should.equal("-1.2e2")
  number.to_int_exact(neg_one_twenty, proj_limit) |> should.equal(Ok(-120))
}

@target(erlang)
pub fn from_int_large_case_test() {
  let proj_limit = default_projection_limit()
  // 9_007_199_254_740_993 -> canonical "9.007199254740993e15", int 9_007_199_254_740_993
  let assert Ok(large_int) = number.from_int(9_007_199_254_740_993)
  number.number_text(large_int) |> should.equal("9.007199254740993e15")
  number.to_int_exact(large_int, proj_limit)
  |> should.equal(Ok(9_007_199_254_740_993))
}

@target(javascript)
pub fn from_int_large_case_test() {
  let proj_limit = default_projection_limit()
  // On JS, the maximum safe native integer is 9_007_199_254_740_991 (2^53 - 1)
  let assert Ok(max_safe) = number.from_int(9_007_199_254_740_991)
  number.number_text(max_safe) |> should.equal("9.007199254740991e15")
  number.to_int_exact(max_safe, proj_limit)
  |> should.equal(Ok(9_007_199_254_740_991))
}

@target(javascript)
pub fn from_int_js_adversarial_guard_test() {
  call_from_int_raw(number.from_int, "nan")
  |> should.equal(Error(number.NonFiniteInteger))

  call_from_int_raw(number.from_int, "infinity")
  |> should.equal(Error(number.NonFiniteInteger))

  call_from_int_raw(number.from_int, "neg_infinity")
  |> should.equal(Error(number.NonFiniteInteger))

  call_from_int_raw(number.from_int, "fractional")
  |> should.equal(Error(number.NonIntegerValue))

  call_from_int_raw(number.from_int, "unsafe_int")
  |> should.equal(Error(number.UnsafeNativeInteger))

  // In JS, 9007199254740993 rounds to 9007199254740992 before construction;
  // it must be rejected with UnsafeNativeInteger, not silently accepted.
  call_from_int_raw(number.from_int, "rounded_before_construction")
  |> should.equal(Error(number.UnsafeNativeInteger))

  call_from_int_raw(number.from_int, "neg_unsafe_int")
  |> should.equal(Error(number.UnsafeNativeInteger))

  call_from_int_raw(number.from_int, "max_safe")
  |> should.be_ok

  call_from_int_raw(number.from_int, "min_safe")
  |> should.be_ok
}

@target(erlang)
pub fn from_int_erlang_adversarial_guard_test() {
  call_from_int_raw(number.from_int, "nan")
  |> should.equal(Error(number.NonFiniteInteger))

  call_from_int_raw(number.from_int, "fractional")
  |> should.equal(Error(number.NonIntegerValue))
}
