-module(file_test_ffi).
-export([write_file/2, make_directory/1]).

write_file(Path, Content) ->
    case filelib:ensure_dir(Path) of
        ok ->
            case file:write_file(Path, Content) of
                ok -> {ok, nil};
                {error, Reason} -> {error, list_to_binary(atom_to_list(Reason))}
            end;
        {error, Reason} ->
            {error, list_to_binary(atom_to_list(Reason))}
    end.

make_directory(Path) ->
    case filelib:ensure_path(Path) of
        ok -> {ok, nil};
        {error, Reason} -> {error, list_to_binary(atom_to_list(Reason))}
    end.
