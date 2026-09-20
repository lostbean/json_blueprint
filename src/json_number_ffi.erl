-module(json_number_ffi).
-export([
    byte_length/1,
    byte_codes/1,
    ascii_string/1,
    integer_to_string/1,
    integer_divide/2,
    integer_remainder/2
]).

byte_length(Value) when is_binary(Value) -> byte_size(Value).

byte_codes(Value) when is_binary(Value) -> binary_to_list(Value).

ascii_string(Bytes) when is_list(Bytes) -> list_to_binary(Bytes).

integer_to_string(Value) when is_integer(Value) -> integer_to_binary(Value).

integer_divide(Dividend, Divisor) when is_integer(Dividend), is_integer(Divisor), Divisor =/= 0 ->
    Dividend div Divisor.

integer_remainder(Dividend, Divisor) when is_integer(Dividend), is_integer(Divisor), Divisor =/= 0 ->
    Dividend rem Divisor.
