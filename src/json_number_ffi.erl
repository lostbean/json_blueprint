-module(json_number_ffi).
-export([
    byte_length/1,
    byte_codes/1,
    ascii_string/1,
    integer_to_string/1,
    integer_divide/2,
    integer_remainder/2,
    float_parts/1,
    parse_float_candidate/1
]).

byte_length(Value) when is_binary(Value) -> byte_size(Value).

byte_codes(Value) when is_binary(Value) -> binary_to_list(Value).

ascii_string(Bytes) when is_list(Bytes) -> list_to_binary(Bytes).

integer_to_string(Value) when is_integer(Value) -> integer_to_binary(Value).

integer_divide(Dividend, Divisor) when is_integer(Dividend), is_integer(Divisor), Divisor =/= 0 ->
    Dividend div Divisor.

integer_remainder(Dividend, Divisor) when is_integer(Dividend), is_integer(Divisor), Divisor =/= 0 ->
    Dividend rem Divisor.

float_parts(Value) when is_float(Value) ->
    <<Sign:1, Exponent:11, Fraction:52>> = <<Value:64/float-big>>,
    case Exponent of
        16#7ff -> non_finite_parts;
        0 when Fraction =:= 0 -> {finite_parts, Sign =:= 1, 0, 0};
        0 -> {finite_parts, Sign =:= 1, Fraction, -1074};
        _ -> {finite_parts, Sign =:= 1, (1 bsl 52) bor Fraction, Exponent - 1023 - 52}
    end.

parse_float_candidate(Token) when is_binary(Token) ->
    case re:run(
        Token,
        <<"^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$">>,
        [{capture, none}]
    ) of
        nomatch -> candidate_invalid;
        match ->
            FloatToken = ensure_float_lexeme(Token),
            try list_to_float(binary_to_list(FloatToken)) of
                Value ->
                    case float_parts(Value) of
                        non_finite_parts -> candidate_overflow;
                        _ -> {candidate_value, Value}
                    end
            catch
                error:badarg -> candidate_overflow;
                _:_ -> candidate_overflow
            end
    end.

ensure_float_lexeme(Token) ->
    case binary:match(Token, <<".">>) of
        {_, 1} -> Token;
        nomatch -> insert_decimal_point(Token)
    end.

insert_decimal_point(Token) ->
    case binary:match(Token, <<"e">>) of
        {Position, 1} -> insert_before(Token, Position, <<".0">>);
        nomatch ->
            case binary:match(Token, <<"E">>) of
                {Position, 1} -> insert_before(Token, Position, <<".0">>);
                nomatch -> <<Token/binary, ".0">>
            end
    end.

insert_before(Token, Position, Inserted) ->
    <<Mantissa:Position/binary, Exponent/binary>> = Token,
    <<Mantissa/binary, Inserted/binary, Exponent/binary>>.
