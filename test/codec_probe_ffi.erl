-module(codec_probe_ffi).
-export([log/1, take/0, panic_message/1, stash/1, unstash/0]).

%% The callback trace of the current process, oldest first.
log(Entry) ->
    Trace =
        case get(codec_probe_trace) of
            undefined -> [];
            Found -> Found
        end,
    put(codec_probe_trace, [Entry | Trace]),
    nil.

take() ->
    Trace =
        case get(codec_probe_trace) of
            undefined -> [];
            Found -> Found
        end,
    put(codec_probe_trace, []),
    lists:reverse(Trace).

panic_message(Run) ->
    try Run() of
        Result -> {ok, Result}
    catch
        error:#{gleam_error := panic, message := Message} -> {error, Message}
    end.

%% Carries a value out of a union block, to build a union around another
%% union's tagging function.
stash(Item) ->
    put(codec_probe_stash, Item),
    nil.

unstash() -> get(codec_probe_stash).
