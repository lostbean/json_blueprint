% THROWAWAY: narrow native data access for direct typed decoding.
-module(native_direct_ffi).
-export([keys/1, field/2, integer/1, floating/1, numeric/1, is_null/1, array_decode/3]).
keys(X) when is_map(X) -> {ok, maps:keys(X)};
keys(_) -> {error, nil}.
field(X, K) ->
    case maps:find(K, X) of
        {ok, V} -> {ok, V};
        error -> {error, nil}
    end.
integer(X) when is_integer(X), X > -1000000000000000000000000, X < 1000000000000000000000000 ->
    {ok, X};
integer(X) when is_float(X) ->
    try
        I = trunc(X),
        case I == X of
            true -> integer(I);
            false -> {error, nil}
        end
    catch
        _:_ -> {error, nil}
    end;
integer(_) ->
    {error, nil}.
floating(X) when is_float(X) -> {ok, X};
floating(X) when is_integer(X) ->
    try
        {ok, erlang:float(X)}
    catch
        _:_ -> {error, nil}
    end;
floating(_) ->
    {error, nil}.
numeric(X) -> is_number(X).
is_null(X) -> X == null.
array_decode(X, F, _E) when is_list(X) -> array_loop(X, F, 0, []);
array_decode(_, _, E) -> {error, E}.
array_loop([], _, _, Done) ->
    {ok, lists:reverse(Done)};
array_loop([X | Xs], F, I, Done) ->
    case F(X, I) of
        {ok, V} -> array_loop(Xs, F, I + 1, [V | Done]);
        {error, _} = Error -> Error
    end.
