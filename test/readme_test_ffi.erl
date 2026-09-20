-module(readme_test_ffi).
-export([read_file_to_string/1]).

read_file_to_string(Path) ->
    case file:read_file(Path) of
        {ok, Binary} -> {ok, Binary};
        {error, Reason} -> {error, list_to_binary(atom_to_list(Reason))}
    end.
