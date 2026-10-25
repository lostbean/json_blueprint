% Native JSON representation and accessors for json/blueprint/internal/native.
-module(json_blueprint_native_ffi).
-export([
    parse/1,
    kind/1,
    string/1,
    boolean/1,
    is_null/1,
    keys/1,
    field/2,
    array_items/1,
    array_decode/3,
    number_input/1,
    integer/1,
    floating/1
]).

parse(Source) ->
    Decoders = #{
        object_start => fun(_) -> {#{}, none} end,
        object_push => fun object_push/3,
        object_finish => fun object_finish/2,
        array_start => fun(_) -> {[], none} end,
        array_push => fun array_push/2,
        array_finish => fun array_finish/2,
        float => fun(Token) -> {json_blueprint_decimal, Token} end
    },
    try json:decode(Source, nil, Decoders) of
        {Value, _, Rest} ->
            case whitespace(Rest) of
                false ->
                    {error, {syntax, <<"trailing content">>}};
                true ->
                    case Value of
                        {json_blueprint_parse_error, Error} -> {error, Error};
                        _ -> {ok, Value}
                    end
            end
    catch
        error:{invalid_byte, Byte} ->
            {error, {syntax, format({invalid_byte, Byte})}};
        error:{unexpected_sequence, Bytes} ->
            {error, {syntax, format({unexpected_sequence, Bytes})}};
        error:unexpected_end ->
            {error, {syntax, <<"unexpected end">>}}
    end.

% OTP's float path catches exceptions across downstream callbacks. Carry
% duplicate failures through container results instead of throwing them.
% Syntax validation therefore completes before a duplicate error is returned.
object_push(K, V, {Map, none}) ->
    Error =
        case maps:is_key(K, Map) of
            true -> {duplicate_key, K};
            false -> admission(V)
        end,
    case Error of
        none -> {Map#{K => V}, none};
        _ -> {#{}, Error}
    end;
object_push(_, _, {_, Error}) ->
    {#{}, Error}.
object_finish({Map, none}, Old) -> {Map, Old};
object_finish({_, Error}, Old) -> {{json_blueprint_parse_error, Error}, Old}.
array_push(V, {Items, none}) ->
    case admission(V) of
        none -> {[V | Items], none};
        Error -> {[], Error}
    end;
array_push(_, {_, Error}) ->
    {[], Error}.
array_finish({Items, none}, Old) -> {lists:reverse(Items), Old};
array_finish({_, Error}, Old) -> {{json_blueprint_parse_error, Error}, Old}.
admission({json_blueprint_parse_error, Error}) -> Error;
admission(_) -> none.

kind(null) -> null;
kind(true) -> bool;
kind(false) -> bool;
kind(X) when is_integer(X) -> number;
kind({json_blueprint_decimal, _}) -> number;
kind(X) when is_binary(X) -> string;
kind(X) when is_list(X) -> array;
kind(X) when is_map(X) -> object.
% Detach values that leave the native tree so a small retained result does
% not keep the complete source document alive.
string(X) when is_binary(X) -> {ok, binary:copy(X)};
string(_) -> {error, nil}.
boolean(true) -> {ok, true};
boolean(false) -> {ok, false};
boolean(_) -> {error, nil}.
is_null(X) -> X =:= null.
keys(X) when is_map(X) -> {ok, [binary:copy(K) || K <- maps:keys(X)]};
keys(_) -> {error, nil}.
field(X, K) when is_map(X) ->
    case maps:find(K, X) of
        {ok, V} -> {ok, V};
        error -> {error, nil}
    end;
field(_, _) ->
    {error, nil}.
array_items(X) when is_list(X) -> {ok, X};
array_items(_) -> {error, nil}.
array_decode(X, F, _) when is_list(X) -> array_loop(X, F, 0, []);
array_decode(_, _, Mismatch) -> {error, Mismatch}.
array_loop([], _, _, Done) ->
    {ok, lists:reverse(Done)};
array_loop([X | Xs], F, I, Done) ->
    case F(X, I) of
        {ok, V} -> array_loop(Xs, F, I + 1, [V | Done]);
        {error, _} = Error -> Error
    end.
number_input(X) when is_integer(X) -> {integer, X};
number_input({json_blueprint_decimal, Token}) -> {decimal, Token};
number_input(_) -> other.
integer(X) when
    is_integer(X),
    X > -1000000000000000000000000,
    X < 1000000000000000000000000
->
    {ok, X};
integer(_) ->
    {error, nil}.
floating(X) when is_integer(X) ->
    try
        {ok, erlang:float(X)}
    catch
        error:badarg -> {error, nil}
    end;
floating({json_blueprint_decimal, Token}) ->
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
floating(_) ->
    {error, nil}.
zero_coefficient(<<C, Rest/binary>>) when C == $-; C == $.; C == $0 -> zero_coefficient(Rest);
zero_coefficient(<<C, _/binary>>) when C == $e; C == $E -> true;
zero_coefficient(<<>>) -> true;
zero_coefficient(_) -> false.
whitespace(<<>>) -> true;
whitespace(<<C, Rest/binary>>) when C == 32; C == 9; C == 10; C == 13 -> whitespace(Rest);
whitespace(_) -> false.
format(Term) -> iolist_to_binary(io_lib:format("~p", [Term])).
