% THROWAWAY: lexical resource admission over original bytes, before native tree allocation.
% This is not a JSON grammar parser. OTP rejects malformed syntax after admission.
-module(native_bounded_ffi).
-export([admit/4]).
admit(Source, MaxDepth, MaxElements, Check) ->
    Pattern = binary:compile_pattern([<<34>>, <<92>>]),
    scan(Source, 0, 0, {MaxDepth, MaxElements, Check, Pattern}).
scan(<<>>, _, _, _) ->
    {ok, nil};
scan(<<C, Rest/binary>>, Depth, Count, Check) when C == ${; C == $[ ->
    case count(Count, Check) of
        {error, _} = Error ->
            Error;
        Next ->
            case Depth >= depth_limit(Check) of
                true -> {error, depth_limit_exceeded};
                false -> scan(Rest, Depth + 1, Next, Check)
            end
    end;
scan(<<C, Rest/binary>>, Depth, Count, Check) when C == $}; C == $] ->
    scan(Rest, max(0, Depth - 1), Count, Check);
scan(<<$", Rest/binary>>, Depth, Count, Check) ->
    After = string_end(Rest, string_pattern(Check)),
    case skip_space(After) of
        <<$:, More/binary>> -> scan(More, Depth, Count, Check);
        _ -> counted_scan(After, Depth, Count, Check)
    end;
scan(<<"true", Rest/binary>>, Depth, Count, Check) ->
    counted_scan(Rest, Depth, Count, Check);
scan(<<"false", Rest/binary>>, Depth, Count, Check) ->
    counted_scan(Rest, Depth, Count, Check);
scan(<<"null", Rest/binary>>, Depth, Count, Check) ->
    counted_scan(Rest, Depth, Count, Check);
scan(<<C, _/binary>> = Bytes, Depth, Count, Check) when C == $-; C >= $0, C =< $9 ->
    case count(Count, Check) of
        {error, _} = Error ->
            Error;
        Next ->
            case number_span(Bytes, 0) of
                too_long ->
                    {error, {numeric, token_too_long}};
                {Length, Rest} ->
                    Token = binary:part(Bytes, 0, Length),
                    Checked =
                        case small_integer(Token) of
                            true -> {ok, nil};
                            false -> check_number(Token, Check)
                        end,
                    case Checked of
                        {ok, nil} -> scan(Rest, Depth, Next, Check);
                        {error, E} -> {error, {numeric, E}}
                    end
            end
    end;
scan(<<_, Rest/binary>>, Depth, Count, Check) ->
    scan(Rest, Depth, Count, Check).
count(N, {_, Max, _, _}) when N >= Max -> {error, element_limit_exceeded};
count(N, _) -> N + 1.
depth_limit({Max, _, _, _}) -> Max.
check_number(Token, {_, _, Check, _}) -> Check(Token).
string_pattern({_, _, _, Pattern}) -> Pattern.
counted_scan(Rest, Depth, Count, Check) ->
    case count(Count, Check) of
        {error, _} = Error -> Error;
        Next -> scan(Rest, Depth, Next, Check)
    end.
% Delegate runs of ordinary string bytes to the native binary search.
% The matcher is compiled once per admission and carried in the scan context.
% Escaped bytes are skipped together; an unterminated string stays for OTP
% to reject after this resource-only scan.
string_end(Bytes, Pattern) ->
    case binary:match(Bytes, Pattern) of
        nomatch ->
            <<>>;
        {At, 1} ->
            <<_:At/binary, C, Rest/binary>> = Bytes,
            case {C, Rest} of
                {34, _} -> Rest;
                {92, <<_, More/binary>>} -> string_end(More, Pattern);
                {92, <<>>} -> <<>>
            end
    end.

skip_space(<<C, Rest/binary>>) when C == 32; C == 9; C == 10; C == 13 -> skip_space(Rest);
skip_space(Rest) -> Rest.
number_span(_, N) when N > 1024 -> too_long;
number_span(<<C, Rest/binary>>, N) when
    C >= $0, C =< $9; C == $-; C == $+; C == $.; C == $e; C == $E
->
    number_span(Rest, N + 1);
number_span(Rest, N) ->
    {N, Rest}.
small_integer(<<$-, Rest/binary>>) -> small_unsigned(Rest);
small_integer(Rest) -> small_unsigned(Rest).
small_unsigned(<<$0>>) -> true;
small_unsigned(<<C, Rest/binary>>) when C >= $1, C =< $9 -> small_digits(Rest, 1);
small_unsigned(_) -> false.
small_digits(_, N) when N > 15 -> false;
small_digits(<<>>, _) -> true;
small_digits(<<C, Rest/binary>>, N) when C >= $0, C =< $9 -> small_digits(Rest, N + 1);
small_digits(_, _) -> false.
