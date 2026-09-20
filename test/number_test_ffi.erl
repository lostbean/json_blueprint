-module(number_test_ffi).
-export([
    float_from_bits/1,
    float_from_hex/1,
    float_to_bits_hex/1,
    call_from_int_raw/2
]).

float_from_bits(Bits) when is_integer(Bits) ->
    <<Value:64/float-big>> = <<Bits:64/unsigned-big>>,
    Value.

float_from_hex(Hex) when is_binary(Hex) ->
    Bits = binary_to_integer(Hex, 16),
    <<Value:64/float-big>> = <<Bits:64/unsigned-big>>,
    Value.

float_to_bits_hex(Value) when is_float(Value) ->
    <<Bits:64/unsigned-big>> = <<Value:64/float-big>>,
    binary:encode_hex(<<Bits:64/unsigned-big>>, lowercase).

call_from_int_raw(FromIntFn, Kind) ->
    case Kind of
        <<"fractional">> -> FromIntFn(1.5);
        <<"nan">> -> FromIntFn(nan)
    end.
