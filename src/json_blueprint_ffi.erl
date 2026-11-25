-module(json_blueprint_ffi).
-export([coerce/1, null/0, utf8_byte_size_exceeds/2]).

coerce(X) -> X.

null() -> null.

utf8_byte_size_exceeds(Source, Max) when is_binary(Source) ->
    byte_size(Source) > Max.
