-module(copy_cost_ffi).
-export([
    flat_size_words/1,
    shared_size_words/1,
    external_bytes/1,
    reference_words/0,
    round_trip/1,
    through_process/1
]).

%% Words a copy to another process takes: sharing is not preserved.
flat_size_words(Term) -> erts_debug:flat_size(Term).

%% Words the term takes in the heap that built it, counting shared parts once.
shared_size_words(Term) -> erts_debug:size(Term).

external_bytes(Term) -> byte_size(term_to_binary(Term)).

%% Words one reference takes in a copy.
reference_words() -> erts_debug:flat_size(make_ref()).

%% The term after an external-format round trip, as a stored codec would be.
round_trip(Term) -> binary_to_term(term_to_binary(Term)).

%% The term as another process received it.
through_process(Term) ->
    Self = self(),
    Pid = spawn(fun() ->
        receive
            {term, Received} -> Self ! {back, Received}
        end
    end),
    Pid ! {term, Term},
    receive
        {back, Back} -> Back
    end.
