% THROWAWAY: OTP grammar with exact-number and duplicate-key admission hooks.
% Errors are returned as sentinels, not thrown: OTP float_decode catches callback exceptions.
-module(native_exact_ffi).
-export([parse/3, as_number/1]).
parse(Source, Exact, ParseNumber) ->
    Number = fun(Token) ->
        case ParseNumber(Token) of
            {ok, N} -> {native_number, N};
            {error, E} -> {native_admission_error, {numeric, E}}
        end
    end,
    Base = #{
        object_start => fun(_) -> {#{}, none} end,
        object_push => fun object_push/3,
        object_finish => fun object_finish/2,
        array_start => fun(_) -> {[], none} end,
        array_push => fun array_push/2,
        array_finish => fun array_finish/2
    },
    Decoders =
        case Exact of
            true -> Base#{integer => Number, float => Number};
            false -> Base
        end,
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
as_number({native_number, N}) -> {ok, N};
as_number(_) -> {error, nil}.
whitespace(<<>>) -> true;
whitespace(<<C, Rest/binary>>) when C == 32; C == 9; C == 10; C == 13 -> whitespace(Rest);
whitespace(_) -> false.
format(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
