-module(codec_test_ffi).
-export([panic_message/1]).

%% The message of the panic that `Run` raises, or `{error, nil}`.
panic_message(Run) ->
    try Run() of
        _ -> {error, nil}
    catch
        error:#{gleam_error := panic, message := Message} -> {ok, Message}
    end.
