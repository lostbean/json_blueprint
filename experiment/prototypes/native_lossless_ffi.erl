% THROWAWAY: OTP grammar with exact integers, deferred decimal tokens and duplicate rejection.
% Errors are returned as sentinels, not thrown: OTP float_decode catches callback exceptions.
-module(native_lossless_ffi).
-export([parse/1, number_input/1, native_float/1]).
parse(Source) ->
    Base = #{
        object_start => fun(_) -> {#{}, none} end,
        object_push => fun object_push/3,
        object_finish => fun object_finish/2,
        array_start => fun(_) -> {[], none} end,
        array_push => fun array_push/2,
        array_finish => fun array_finish/2
    },
    Decoders = Base#{float => fun(Token) -> {native_decimal, Token} end},
    try json:decode(Source, nil, Decoders) of
        {Value, _, Rest} ->
            case whitespace(Rest) of
                false ->
                    {error, {native_syntax, <<"trailing content">>}};
                true ->
                    case Value of
                        {native_admission_error, E} -> {error, E};
                        _ -> {ok, Value}
                    end
            end
    catch
        error:{invalid_byte, Byte} ->
            {error, {native_syntax, format({invalid_byte, Byte})}};
        error:{unexpected_sequence, Bytes} ->
            {error, {native_syntax, format({unexpected_sequence, Bytes})}};
        error:unexpected_end ->
            {error, {native_syntax, <<"unexpected end">>}}
    end.
object_push(K, V, {Map, Previous}) ->
    Error =
        case Previous of
            none ->
                case maps:is_key(K, Map) of
                    true -> {duplicate_key, K};
                    false -> admission(V)
                end;
            _ ->
                Previous
        end,
    case Error of
        none -> {Map#{K => V}, none};
        _ -> {Map#{K => nil}, Error}
    end.
object_finish({Map, none}, Old) -> {Map, Old};
object_finish({_, Error}, Old) -> {{native_admission_error, Error}, Old}.
array_push(V, {Items, none}) ->
    case admission(V) of
        none -> {[V | Items], none};
        Error -> {[], Error}
    end;
array_push(_, {_, Error}) ->
    {[], Error}.
array_finish({Items, none}, Old) -> {lists:reverse(Items), Old};
array_finish({_, Error}, Old) -> {{native_admission_error, Error}, Old}.
admission({native_admission_error, Error}) -> Error;
admission(_) -> none.
number_input(X) when is_integer(X) -> {integer, X};
number_input({native_decimal, Token}) -> {decimal, Token};
number_input(_) -> not_number.
native_float(X) when is_integer(X) ->
    try
        {ok, erlang:float(X)}
    catch
        error:badarg -> {error, nil}
    end;
native_float({native_decimal, Token}) ->
    % Strict Number normalizes mathematical zero, but preserves signed
    % underflow of nonzero coefficients. Inspect only the coefficient.
    case zero_coefficient(Token) of
        true ->
            {ok, 0.0};
        false ->
            try
                {ok, binary_to_float(Token)}
            catch
                error:badarg -> {error, nil}
            end
    end;
native_float(_) ->
    {error, nil}.
zero_coefficient(<<C, Rest/binary>>) when C == $-; C == $.; C == $0 -> zero_coefficient(Rest);
zero_coefficient(<<C, _/binary>>) when C == $e; C == $E -> true;
zero_coefficient(<<>>) -> true;
zero_coefficient(_) -> false.
whitespace(<<>>) -> true;
whitespace(<<C, Rest/binary>>) when C == 32; C == 9; C == 10; C == 13 -> whitespace(Rest);
whitespace(_) -> false.
format(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
