-module(module_docs_test_ffi).
-export([public_sources/0]).

%% Every module under src/ that is not internal, with its source text.
public_sources() ->
    Paths = filelib:wildcard("src/**/*.gleam"),
    Public = [P || P <- Paths, string:find(P, "/internal/") =:= nomatch],
    [{list_to_binary(P), read(P)} || P <- lists:sort(Public)].

read(Path) ->
    {ok, Binary} = file:read_file(Path),
    Binary.
