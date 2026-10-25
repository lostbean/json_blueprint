-module(parser_benchmark_ffi).
-export([setting/1, read_text/1]).

setting(Name) ->
    list_to_binary(os:getenv(binary_to_list(Name))).

read_text(Path) ->
    {ok, Text} = file:read_file(Path),
    Text.
