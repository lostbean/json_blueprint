-module(schema_generate_ffi).
-export([read_file/1, write_file/2, output_directory/0, monotonic_nanos/0, consume/1]).
read_file(Path) ->
    case file:read_file(Path) of
        {ok, Text} -> {ok, Text};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.
write_file(Path, Content) ->
    case filelib:ensure_dir(Path) of
        ok ->
            case file:write_file(Path, Content) of
                ok -> {ok, nil};
                {error, Reason} -> {error, atom_to_binary(Reason)}
            end;
        {error, Reason} ->
            {error, atom_to_binary(Reason)}
    end.
output_directory() -> list_to_binary(os:getenv("SCHEMA_OUTPUT", "../src")).

monotonic_nanos() -> erlang:monotonic_time(nanosecond).
consume(Value) ->
    put(generation_bench_sink, Value),
    nil.
