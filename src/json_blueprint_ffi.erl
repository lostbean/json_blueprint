-module(json_blueprint_ffi).
-export([null/0, utf8_byte_size_exceeds/2]).

null() -> null.

utf8_byte_size_exceeds(Source, Max) when is_binary(Source) ->
    byte_size(Source) > Max.
