-module(schema_bench_probe).
-export([consume/1, run/1]).
consume(Value) ->
    put(schema_benchmark_sink, Value),
    nil.
repeat(0, _) ->
    ok;
repeat(N, Work) ->
    Work(),
    repeat(N - 1, Work).
run(Input) ->
    Cases =
        case os:getenv("BENCH_REVERSE") of
            "1" -> lists:reverse(Input);
            _ -> Input
        end,
    lists:foreach(
        fun({workload, Name, Operation, MinimumIterations, Prepare}) ->
            Work = Prepare(),
            repeat(50, Work),
            PilotStart = erlang:monotonic_time(nanosecond),
            repeat(50, Work),
            PilotNs = max(1, erlang:monotonic_time(nanosecond) - PilotStart),
            Iterations = min(2000000, max(MinimumIterations, ceil(150000000 * 50 / PilotNs))),
            erlang:garbage_collect(),
            Start = erlang:monotonic_time(nanosecond),
            repeat(Iterations, Work),
            Ns = erlang:monotonic_time(nanosecond) - Start,
            io:format("~s~n", [
                json:encode(#{
                    name => Name,
                    operation => Operation,
                    iterations => Iterations,
                    elapsed_ns => Ns,
                    ns_per_op => Ns / Iterations
                })
            ])
        end,
        Cases
    ),
    nil.
