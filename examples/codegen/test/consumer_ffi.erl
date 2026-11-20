-module(consumer_ffi).
-export([read_file/1, write_file/2, flat_size_bytes/1]).
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

%% Bytes a copy of Term to another process takes: sharing is not preserved.
flat_size_bytes(Term) -> erts_debug:flat_size(Term) * erlang:system_info(wordsize).
