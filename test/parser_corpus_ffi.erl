-module(parser_corpus_ffi).
-export([read_cases/0]).

read_cases() ->
    Path = os:getenv("BLUEPRINT_PARSER_CORPUS"),
    {ok, Names} = file:list_dir(Path),
    [
        {unicode:characters_to_binary(Name), read(filename:join(Path, Name))}
     || Name <- lists:sort(Names), filename:extension(Name) =:= ".json"
    ].

read(Path) ->
    {ok, Bytes} = file:read_file(Path),
    Bytes.
