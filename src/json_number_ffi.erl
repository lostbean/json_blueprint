-module(json_number_ffi).
-export([
    byte_length/1,
    byte_codes/1,
    ascii_string/1,
    integer_to_string/1,
    validate_native_int/4,
    integer_divide/2,
    integer_remainder/2,
    float_parts/1,
    parse_float_candidate/4,
    float_to_decimal/2,
    decimal_equals_binary/4,
    project_native_int/3
]).

byte_length(Value) when is_binary(Value) -> byte_size(Value).

byte_codes(Value) when is_binary(Value) -> binary_to_list(Value).

ascii_string(Bytes) when is_list(Bytes) -> list_to_binary(Bytes).

integer_to_string(Value) when is_integer(Value) -> integer_to_binary(Value).

validate_native_int(Value, _OnNonFinite, _OnFractional, _OnUnsupported) when is_integer(Value) ->
    {ok, integer_to_binary(Value)};
validate_native_int(Value, _OnNonFinite, OnFractional, _OnUnsupported) when is_float(Value) ->
    {error, OnFractional};
validate_native_int(Value, OnNonFinite, _OnFractional, _OnUnsupported) when
    Value =:= nan; Value =:= infinity; Value =:= neg_infinity
->
    {error, OnNonFinite};
validate_native_int(_Value, _OnNonFinite, OnFractional, _OnUnsupported) ->
    {error, OnFractional}.

integer_divide(Dividend, Divisor) when is_integer(Dividend), is_integer(Divisor), Divisor =/= 0 ->
    Dividend div Divisor.

integer_remainder(Dividend, Divisor) when
    is_integer(Dividend), is_integer(Divisor), Divisor =/= 0
->
    Dividend rem Divisor.

float_parts(Value) when is_float(Value) ->
    <<Sign:1, Exponent:11, Fraction:52>> = <<Value:64/float-big>>,
    case Exponent of
        16#7ff -> {error, nil};
        0 when Fraction =:= 0 -> {ok, {Sign =:= 1, 0, 0}};
        0 -> {ok, {Sign =:= 1, Fraction, -1074}};
        _ -> {ok, {Sign =:= 1, (1 bsl 52) bor Fraction, Exponent - 1023 - 52}}
    end.

parse_float_candidate(Token, OnValue, OnOverflow, OnInvalid) when is_binary(Token) ->
    case
        re:run(
            Token,
            <<"^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$">>,
            [{capture, none}]
        )
    of
        nomatch ->
            OnInvalid;
        match ->
            FloatToken = ensure_float_lexeme(Token),
            try list_to_float(binary_to_list(FloatToken)) of
                Value ->
                    case float_parts(Value) of
                        {error, _} -> OnOverflow;
                        _ -> OnValue(Value)
                    end
            catch
                error:badarg -> OnOverflow;
                _:_ -> OnOverflow
            end
    end.

ensure_float_lexeme(Token) ->
    case binary:match(Token, <<".">>) of
        {_, 1} -> Token;
        nomatch -> insert_decimal_point(Token)
    end.

insert_decimal_point(Token) ->
    case binary:match(Token, <<"e">>) of
        {Position, 1} ->
            insert_before(Token, Position, <<".0">>);
        nomatch ->
            case binary:match(Token, <<"E">>) of
                {Position, 1} -> insert_before(Token, Position, <<".0">>);
                nomatch -> <<Token/binary, ".0">>
            end
    end.

insert_before(Token, Position, Inserted) ->
    <<Mantissa:Position/binary, Exponent/binary>> = Token,
    <<Mantissa/binary, Inserted/binary, Exponent/binary>>.

float_to_decimal(Significand, Exponent2) ->
    {Coeff, Exp10} =
        if
            Exponent2 >= 0 ->
                {Significand * integer_power(2, Exponent2), 0};
            true ->
                {Significand * integer_power(5, -Exponent2), Exponent2}
        end,
    Digits = binary_to_list(integer_to_binary(Coeff)),
    {Digits, Exp10}.

decimal_equals_binary(DecDigits, DecExp, BinSig, BinExp) ->
    DecStr = list_to_binary(DecDigits),
    DecSignificand = binary_to_integer(DecStr),
    {NormBinSig, NormBinExp} = remove_binary_trailing_zeroes(BinSig, BinExp),
    case {DecExp >= 0, NormBinExp >= 0} of
        {true, true} ->
            DecSignificand * integer_power(10, DecExp) =:=
                NormBinSig * integer_power(2, NormBinExp);
        {true, false} ->
            false;
        {false, true} ->
            false;
        {false, false} ->
            DecDenomExp = -DecExp,
            BinDenomExp = -NormBinExp,
            DecSignificand * integer_power(2, BinDenomExp) =:=
                NormBinSig * integer_power(2, DecDenomExp) * integer_power(5, DecDenomExp)
    end.

remove_binary_trailing_zeroes(Significand, Exponent2) ->
    case Significand rem 2 of
        0 when Significand > 0 ->
            remove_binary_trailing_zeroes(Significand div 2, Exponent2 + 1);
        _ ->
            {Significand, Exponent2}
    end.

integer_power(_Base, Exponent) when Exponent =< 0 -> 1;
integer_power(Base, Exponent) ->
    case Exponent rem 2 of
        0 ->
            Half = integer_power(Base, Exponent div 2),
            Half * Half;
        _ ->
            Base * integer_power(Base, Exponent - 1)
    end.

project_native_int(Negative, Digits, Exponent10) ->
    DecStr = list_to_binary(Digits),
    Coeff = binary_to_integer(DecStr),
    Val = Coeff * integer_power(10, Exponent10),
    SignedVal =
        case Negative of
            true -> -Val;
            false -> Val
        end,
    {ok, SignedVal}.
