-module(json_blueprint_ffi).
-export([null/0, utf8_byte_size_exceeds/2, copy_string/1]).

null() -> null.

utf8_byte_size_exceeds(Source, Max) when is_binary(Source) ->
    byte_size(Source) > Max.

%% A string parsed from a larger input would otherwise keep that whole input
%% alive as a sub-binary.
copy_string(Text) when is_binary(Text) -> binary:copy(Text).
