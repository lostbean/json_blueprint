-module(bench_ffi).
-export([monotonic_nanos/0, target_runtime/0]).

monotonic_nanos() ->
    erlang:monotonic_time(nanosecond).

target_runtime() ->
    Otp = list_to_binary(erlang:system_info(otp_release)),
    <<"Erlang/OTP ", Otp/binary>>.
