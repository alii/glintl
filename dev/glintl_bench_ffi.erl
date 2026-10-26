-module(glintl_bench_ffi).
-export([measure/1]).

%% Runs F in a fresh process. Returns the bytes it allocated on the heap
%% and the microseconds it took.
measure(F) ->
    Self = self(),
    Pid = spawn(fun() ->
        erlang:garbage_collect(),
        {_, Before, _} = erlang:statistics(garbage_collection),
        T0 = erlang:monotonic_time(microsecond),
        F(),
        T1 = erlang:monotonic_time(microsecond),
        erlang:garbage_collect(),
        {_, After, _} = erlang:statistics(garbage_collection),
        {memory, Left} = process_info(self(), memory),
        Self ! {self(), (After - Before) * erlang:system_info(wordsize) + Left, T1 - T0}
    end),
    receive {Pid, Bytes, Micros} -> {Bytes, Micros} end.
