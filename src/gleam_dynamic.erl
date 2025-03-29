%  Subset copied from the original and now deprecated decoder in gleam/dynamic in gleam_stdlib
% Migration to the new decoder is difficult at moment
% https://github.com/gleam-lang/stdlib/blob/v0.58.0/src/gleam_stdlib.erl

-module(gleam_dynamic).

-export([
    classify_dynamic/1, identity/1, decode_int/1, decode_bool/1, decode_map/1, decode_result/1,
    decode_float/1, decode_list/1, decode_option/2, decode_field/2, decode_bit_array/1,
    size_of_tuple/1, decode_tuple/1, decode_tuple2/1, decode_tuple3/1,
    decode_tuple4/1, decode_tuple5/1, decode_tuple6/1, tuple_get/2
]).

identity(X) -> X.

decode_error_msg(Expected, Data) when is_binary(Expected) ->
    decode_error(Expected, classify_dynamic(Data)).
decode_error(Expected, Got) when is_binary(Expected) andalso is_binary(Got) ->
    {error, [{decode_error, Expected, Got, []}]}.

classify_dynamic(nil) -> <<"Nil">>;
classify_dynamic(X) when is_boolean(X) -> <<"Bool">>;
classify_dynamic(X) when is_atom(X) -> <<"Atom">>;
classify_dynamic(X) when is_binary(X) -> <<"String">>;
classify_dynamic(X) when is_bitstring(X) -> <<"BitArray">>;
classify_dynamic(X) when is_integer(X) -> <<"Int">>;
classify_dynamic(X) when is_float(X) -> <<"Float">>;
classify_dynamic(X) when is_list(X) -> <<"List">>;
classify_dynamic(X) when is_map(X) -> <<"Dict">>;
classify_dynamic(X) when is_tuple(X) ->
    iolist_to_binary(["Tuple of ", integer_to_list(tuple_size(X)), " elements"]);
classify_dynamic(X) when
    is_function(X, 0) orelse is_function(X, 1) orelse is_function(X, 2) orelse
    is_function(X, 3) orelse is_function(X, 4) orelse is_function(X, 5) orelse
    is_function(X, 6) orelse is_function(X, 7) orelse is_function(X, 8) orelse
    is_function(X, 9) orelse is_function(X, 10) orelse is_function(X, 11) orelse
    is_function(X, 12) -> <<"Function">>;
classify_dynamic(_) -> <<"Some other type">>.

decode_map(Data) when is_map(Data) -> {ok, Data};
decode_map(Data) -> decode_error_msg(<<"Dict">>, Data).

decode_bit_array(Data) when is_bitstring(Data) -> {ok, Data};
decode_bit_array(Data) -> decode_error_msg(<<"BitArray">>, Data).

decode_int(Data) when is_integer(Data) -> {ok, Data};
decode_int(Data) -> decode_error_msg(<<"Int">>, Data).

decode_float(Data) when is_float(Data) -> {ok, Data};
decode_float(Data) -> decode_error_msg(<<"Float">>, Data).

decode_bool(Data) when is_boolean(Data) -> {ok, Data};
decode_bool(Data) -> decode_error_msg(<<"Bool">>, Data).

decode_list(Data) when is_list(Data) -> {ok, Data};
decode_list(Data) -> decode_error_msg(<<"List">>, Data).

decode_field(Data, Key) when is_map(Data) ->
    case Data of
        #{Key := Value} -> {ok, {some, Value}};
        _ ->
            {ok, none}
    end;
decode_field(Data, _) ->
    decode_error_msg(<<"Dict">>, Data).

size_of_tuple(Data) -> tuple_size(Data).

tuple_get(_tup, Index) when Index < 0 -> {error, nil};
tuple_get(Data, Index) when Index >= tuple_size(Data) -> {error, nil};
tuple_get(Data, Index) -> {ok, element(Index + 1, Data)}.

decode_tuple(Data) when is_tuple(Data) -> {ok, Data};
decode_tuple(Data) -> decode_error_msg(<<"Tuple">>, Data).

decode_tuple2({_,_} = A) -> {ok, A};
decode_tuple2([A,B]) -> {ok, {A,B}};
decode_tuple2(Data) -> decode_error_msg(<<"Tuple of 2 elements">>, Data).

decode_tuple3({_,_,_} = A) -> {ok, A};
decode_tuple3([A,B,C]) -> {ok, {A,B,C}};
decode_tuple3(Data) -> decode_error_msg(<<"Tuple of 3 elements">>, Data).

decode_tuple4({_,_,_,_} = A) -> {ok, A};
decode_tuple4([A,B,C,D]) -> {ok, {A,B,C,D}};
decode_tuple4(Data) -> decode_error_msg(<<"Tuple of 4 elements">>, Data).

decode_tuple5({_,_,_,_,_} = A) -> {ok, A};
decode_tuple5([A,B,C,D,E]) -> {ok, {A,B,C,D,E}};
decode_tuple5(Data) -> decode_error_msg(<<"Tuple of 5 elements">>, Data).

decode_tuple6({_,_,_,_,_,_} = A) -> {ok, A};
decode_tuple6([A,B,C,D,E,F]) -> {ok, {A,B,C,D,E,F}};
decode_tuple6(Data) -> decode_error_msg(<<"Tuple of 6 elements">>, Data).

decode_option(Term, F) ->
    Decode = fun(Inner) ->
        case F(Inner) of
            {ok, Decoded} -> {ok, {some, Decoded}};
            Error -> Error
        end
    end,
    case Term of
        undefined -> {ok, none};
        error -> {ok, none};
        null -> {ok, none};
        none -> {ok, none};
        nil -> {ok, none};
        {some, Inner} -> Decode(Inner);
        _ -> Decode(Term)
    end.

decode_result(Term) ->
    case Term of
        {ok, Inner} -> {ok, {ok, Inner}};
        ok -> {ok, {ok, nil}};
        {error, Inner} -> {ok, {error, Inner}};
        error -> {ok, {error, nil}};
        _ -> decode_error_msg(<<"Result">>, Term)
    end.
