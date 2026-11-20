-module(examples_copy_cost_ffi).
-export([flat_size_bytes/1]).

%% Bytes a copy of Term to another process takes: a message, a spawn
%% argument or a child specification copies the term without sharing.
flat_size_bytes(Term) ->
    erts_debug:flat_size(Term) * erlang:system_info(wordsize).
