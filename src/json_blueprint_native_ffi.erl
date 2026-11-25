% Native JSON representation and accessors for json/blueprint/internal/native.
-module(json_blueprint_native_ffi).
-export([
    parse/1,
    parse_bounded/3,
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
    decode(Source, nil, Decoders, fun(_) -> none end).

% The decoder accumulator carries the nesting depth and the number of values
% seen so far, so both bounds are checked in the callbacks that already run for
% every container and member. A container's accumulator is
% {Items, Error, Depth, Count}; Count excludes the root value.
parse_bounded(Source, MaxDepth, MaxValues) ->
    Decoders = #{
        object_start => fun(Outer) -> open(#{}, Outer, MaxDepth) end,
        object_push => fun(K, V, Acc) -> bounded_object_push(K, V, Acc, MaxValues) end,
        object_finish => fun close_object/2,
        array_start => fun(Outer) -> open([], Outer, MaxDepth) end,
        array_push => fun(V, Acc) -> bounded_array_push(V, Acc, MaxValues) end,
        array_finish => fun close_array/2,
        float => fun(Token) -> {json_blueprint_decimal, Token} end
    },
    Root = {root, none, 0, 0},
    decode(Source, Root, Decoders, fun({root, none, 0, Count}) ->
        case Count + 1 > MaxValues of
            true -> value_limit;
            false -> none
        end
    end).

decode(Source, Acc, Decoders, Refusal) ->
    try json:decode(Source, Acc, Decoders) of
        {Value, Final, Rest} ->
            case whitespace(Rest) of
                false ->
                    {error, {syntax, <<"trailing content">>}};
                true ->
                    case Value of
                        {json_blueprint_parse_error, Error} ->
                            {error, Error};
                        _ ->
                            case Refusal(Final) of
                                none -> {ok, Value};
                                Error -> {error, Error}
                            end
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

% A container opened inside a refused one stays refused, so nothing more is
% retained once a bound is exceeded.
open(Empty, {_, none, Depth, Count}, MaxDepth) when Depth < MaxDepth ->
    {Empty, none, Depth + 1, Count};
open(Empty, {_, none, Depth, Count}, _) ->
    {Empty, depth_limit, Depth + 1, Count};
open(Empty, {_, Error, Depth, Count}, _) ->
    {Empty, Error, Depth + 1, Count}.
% The root is one more value, so the last admitted member has Count + 2 =<
% MaxValues. These repeat object_push/3 and array_push/2 on the wider
% accumulator, because rebuilding the narrow one per member doubled the cost.
bounded_object_push(K, V, {Map, none, Depth, Count}, MaxValues) when Count + 2 =< MaxValues ->
    case maps:is_key(K, Map) of
        true ->
            {#{}, {duplicate_key, K}, Depth, Count};
        false ->
            case V of
                {json_blueprint_parse_error, Error} -> {#{}, Error, Depth, Count};
                _ -> {Map#{K => V}, none, Depth, Count + 1}
            end
    end;
bounded_object_push(_, _, {_, none, Depth, Count}, _) ->
    {#{}, value_limit, Depth, Count};
bounded_object_push(_, _, Refused, _) ->
    Refused.
bounded_array_push({json_blueprint_parse_error, Error}, {_, none, Depth, Count}, _) ->
    {[], Error, Depth, Count};
bounded_array_push(V, {Items, none, Depth, Count}, MaxValues) when Count + 2 =< MaxValues ->
    {[V | Items], none, Depth, Count + 1};
bounded_array_push(_, {_, none, Depth, Count}, _) ->
    {[], value_limit, Depth, Count};
bounded_array_push(_, Refused, _) ->
    Refused.
close_object({Map, none, _, Count}, Outer) ->
    {Map, setelement(4, Outer, Count)};
close_object({_, Error, _, Count}, Outer) ->
    {{json_blueprint_parse_error, Error}, setelement(4, Outer, Count)}.
close_array({Items, none, _, Count}, Outer) ->
    {lists:reverse(Items), setelement(4, Outer, Count)};
close_array({_, Error, _, Count}, Outer) ->
    {{json_blueprint_parse_error, Error}, setelement(4, Outer, Count)}.

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
