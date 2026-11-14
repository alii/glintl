-module(glintl_bench_ffi).
-export([measure/1]).

%% Runs F in a fresh process. Returns the bytes it allocated on the heap,
%% the microseconds it took and its reductions.
measure(F) ->
    Self = self(),
    Pid = spawn(fun() ->
        erlang:garbage_collect(),
        {_, Before, _} = erlang:statistics(garbage_collection),
        {reductions, R0} = process_info(self(), reductions),
        T0 = erlang:monotonic_time(microsecond),
        F(),
        T1 = erlang:monotonic_time(microsecond),
        {reductions, R1} = process_info(self(), reductions),
        erlang:garbage_collect(),
        {_, After, _} = erlang:statistics(garbage_collection),
        {memory, Left} = process_info(self(), memory),
        Self ! {self(), (After - Before) * erlang:system_info(wordsize) + Left, T1 - T0, R1 - R0}
    end),
    receive {Pid, Bytes, Micros, Reductions} -> {Bytes, Micros, Reductions} end.
