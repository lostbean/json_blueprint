% THROWAWAY: numeric-projection mismatch diagnostics.
-module(native_numeric_probe_ffi).
-export([debug/1]).
debug(Value) ->
    io:format("~p~n", [Value]),
    nil.
