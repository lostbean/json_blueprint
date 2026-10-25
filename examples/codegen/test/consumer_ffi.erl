-module(consumer_ffi).
-export([read_file/1]).
read_file(Path) ->
    case file:read_file(Path) of
        {ok, Text} -> {ok, Text};
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.
