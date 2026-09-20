-module(number_test_ffi).
-export([
    float_from_bits/1,
    float_to_bits_hex/1
]).

float_from_bits(Bits) when is_integer(Bits) ->
    <<Value:64/float-big>> = <<Bits:64/unsigned-big>>,
    Value.

float_to_bits_hex(Value) when is_float(Value) ->
    <<Bits:64/unsigned-big>> = <<Value:64/float-big>>,
    binary:encode_hex(<<Bits:64/unsigned-big>>, lowercase).
