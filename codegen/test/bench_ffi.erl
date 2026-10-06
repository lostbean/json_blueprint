-module(bench_ffi).
-export([monotonic_nanos/0, target_runtime/0, consume/1, consumed_count/0]).

monotonic_nanos() ->
    erlang:monotonic_time(nanosecond).

target_runtime() ->
    Otp = list_to_binary(erlang:system_info(otp_release)),
    <<"Erlang/OTP ", Otp/binary>>.

consume(Value) ->
    Count =
        case get(blueprint_benchmark_sink) of
            {_, PreviousCount} -> PreviousCount + 1;
            undefined -> 1
        end,
    put(blueprint_benchmark_sink, {Value, Count}),
    nil.

consumed_count() ->
    case get(blueprint_benchmark_sink) of
        {_, Count} -> Count;
        undefined -> 0
    end.
