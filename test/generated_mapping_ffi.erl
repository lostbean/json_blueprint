% test-only per-process mapping event trace.
-module(generated_mapping_ffi).
-export([reset/0, mark/1, trace/0]).
reset() ->
    put(generated_mapping_trace, <<>>),
    nil.
mark(Label) ->
    put(generated_mapping_trace, <<(trace())/binary, Label/binary, ";">>),
    nil.
trace() ->
    case get(generated_mapping_trace) of
        undefined -> <<>>;
        Value -> Value
    end.
