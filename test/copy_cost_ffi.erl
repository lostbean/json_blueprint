-module(copy_cost_ffi).
-export([flat_size_words/1, shared_size_words/1, external_bytes/1,
         reference_words/0]).

%% Words a copy to another process takes: sharing is not preserved.
flat_size_words(Term) -> erts_debug:flat_size(Term).

%% Words the term takes in the heap that built it, counting shared parts once.
shared_size_words(Term) -> erts_debug:size(Term).

external_bytes(Term) -> byte_size(term_to_binary(Term)).

%% Words one reference takes in a copy.
reference_words() -> erts_debug:flat_size(make_ref()).
