-module(bounded_parsing_test_ffi).
-export([flat_size_words/1, shares_input/1]).

flat_size_words(Term) -> erts_debug:flat_size(Term).

%% True when a parsed string is a view into a larger binary.
shares_input(Text) when is_binary(Text) ->
    binary:referenced_byte_size(Text) > byte_size(Text).
