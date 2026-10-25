% THROWAWAY: measure memory and callback parity for selective typed decoding.
-module(selective_ffi).
-export([reset/0, log/1, entries/0, snapshot/0]).
reset() ->
    put(selective_calls, []),
    nil.
log(X) ->
    put(selective_calls, [X | entries()]),
    nil.
entries() ->
    case get(selective_calls) of
        undefined -> [];
        X -> X
    end.
snapshot() ->
    erlang:garbage_collect(),
    {memory, M} = process_info(self(), memory),
    T = erlang:memory(total),
    iolist_to_binary(io_lib:format("{\"process_bytes\":~p,\"vm_bytes\":~p}", [M, T])).
