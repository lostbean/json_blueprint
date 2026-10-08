%% Adapted from the retained 2026-10-08 object-validation allocation probe.
-module(schema_allocation_probe).
-export([consume/1, run/1, invoke/1]).

consume(Value) ->
    put(schema_benchmark_sink, Value),
    nil.

%% Only this non-tail wrapper is memory-traced. All untraced descendants accrue here.
invoke(Work) ->
    Work(),
    ok.

run(Input) ->
    Cases =
        case os:getenv("BENCH_REVERSE") of
            "1" -> lists:reverse(Input);
            _ -> Input
        end,
    Filter = os:getenv("ALLOCATION_CASE", ""),
    lists:foreach(
        fun({workload, Name, Operation, Iterations, Prepare}) ->
            Key = binary_to_list(<<Name/binary, "/", Operation/binary>>),
            case Filter == "" orelse Filter == Key of
                true -> measure(Name, Operation, Iterations, Prepare);
                false -> ok
            end
        end,
        Cases
    ),
    nil.

repeat(0, _) ->
    ok;
repeat(N, Work) ->
    Work(),
    repeat(N - 1, Work).

traced_repeat(0, _) ->
    ok;
traced_repeat(N, Work) ->
    invoke(Work),
    traced_repeat(N - 1, Work).

snapshot() ->
    maps:from_list(
        process_info(self(), [memory, total_heap_size, heap_size, stack_size, reductions])
    ).

worker(Parent, Iterations, Prepare) ->
    Work = Prepare(),
    repeat(5, Work),
    erase(schema_benchmark_sink),
    RootsWords = erts_debug:size(Work),
    erlang:garbage_collect(),
    erlang:garbage_collect(),
    Before = snapshot(),
    Parent ! {ready, self(), Before, RootsWords},
    receive
        go -> ok
    end,
    Start = erlang:monotonic_time(nanosecond),
    traced_repeat(Iterations, Work),
    Stop = erlang:monotonic_time(nanosecond),
    After = snapshot(),
    RetainedWords = erts_debug:size({Work, get(schema_benchmark_sink)}) - RootsWords - 3,
    Parent ! {done, self(), Before, After, Start, Stop, RetainedWords},
    hold(Parent, Work).

hold(Parent, Work) ->
    receive
        after_gc ->
            erlang:garbage_collect(),
            erlang:garbage_collect(),
            Parent ! {after_gc, self(), snapshot()},
            hold(Parent, Work);
        stop ->
            ok
    end.

measure(Name, Operation, Iterations, Prepare) ->
    Parent = self(),
    Pid = spawn_link(fun() -> worker(Parent, Iterations, Prepare) end),
    receive
        {ready, Pid, _, _} -> ok
    end,
    Session = trace:session_create(allocation_experiment, self(), []),
    1 = trace:function(Session, {?MODULE, invoke, 1}, true, [call_memory]),
    1 = trace:process(Session, Pid, true, [call, garbage_collection, monotonic_timestamp]),
    Pid ! go,
    {Before, After, Start, Stop, RetainedWords, Events0} = collect(Pid, []),
    trace:process(Session, Pid, false, [call, garbage_collection, monotonic_timestamp]),
    Ref = trace:delivered(Session, Pid),
    Events = drain(Pid, Ref, Events0),
    {call_memory, Counters} = trace:info(Session, {?MODULE, invoke, 1}, call_memory),
    {Pid, Iterations, Words} = lists:keyfind(Pid, 1, Counters),
    trace:session_destroy(Session),
    Pid ! after_gc,
    Post =
        receive
            {after_gc, Pid, Snapshot} -> Snapshot
        end,
    Pid ! stop,
    Relevant = [E || E = {_, _, Time} <- Events, Time >= Start, Time =< Stop],
    GC = gc_metrics(Relevant),
    WordBytes = erlang:system_info(wordsize),
    Capacity =
        lists:max([
            maps:get(total_heap_size, Before),
            maps:get(total_heap_size, After),
            maps:get(total_heap_size, Post)
            | [
                proplists:get_value(heap_block_size, Info, 0) +
                    proplists:get_value(old_heap_block_size, Info, 0)
             || {_, Info, _} <- Relevant
            ]
        ]) * WordBytes,
    Result = #{
        name => Name,
        operation => Operation,
        iterations => Iterations,
        allocated_heap_bytes => Words * WordBytes,
        allocated_heap_bytes_per_op => Words * WordBytes / Iterations,
        retained_result_heap_bytes => RetainedWords * WordBytes,
        before_heap_capacity_bytes => maps:get(total_heap_size, Before) * WordBytes,
        observed_peak_heap_capacity_bytes => Capacity,
        after_gc_heap_capacity_bytes => maps:get(total_heap_size, Post) * WordBytes,
        before_process_bytes => maps:get(memory, Before),
        after_gc_process_bytes => maps:get(memory, Post),
        elapsed_ns => Stop - Start,
        gc_minor => maps:get(minor, GC),
        gc_major => maps:get(major, GC),
        gc_elapsed_ns => maps:get(elapsed_ns, GC),
        word_bytes => WordBytes
    },
    io:format("~s~n", [json:encode(Result)]).

collect(Pid, Events) ->
    receive
        {trace_ts, Pid, Tag, Info, Time} ->
            collect(Pid, [{Tag, Info, Time} | Events]);
        {done, Pid, Before, After, Start, Stop, RetainedWords} ->
            {Before, After, Start, Stop, RetainedWords, Events}
    end.

drain(Pid, Ref, Events) ->
    receive
        {trace_ts, Pid, Tag, Info, Time} -> drain(Pid, Ref, [{Tag, Info, Time} | Events]);
        {trace_delivered, Pid, Ref} -> lists:reverse(Events)
    end.

gc_metrics(Events) ->
    {Minor, Major, Ns, _} = lists:foldl(
        fun
            ({gc_minor_start, _, T}, {A, B, C, _}) ->
                {A + 1, B, C, T};
            ({gc_major_start, _, T}, {A, B, C, _}) ->
                {A, B + 1, C, T};
            ({gc_minor_end, _, T}, {A, B, C, Start}) when is_integer(Start) ->
                {A, B, C + T - Start, none};
            ({gc_major_end, _, T}, {A, B, C, Start}) when is_integer(Start) ->
                {A, B, C + T - Start, none};
            (_, State) ->
                State
        end,
        {0, 0, 0, none},
        Events
    ),
    #{minor => Minor, major => Major, elapsed_ns => Ns}.
