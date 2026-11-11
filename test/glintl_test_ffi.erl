-module(glintl_test_ffi).
-export([on_erlang/0, with_tz/2]).

%% Some behaviour differs by target, as JavaScript uses `Intl`.
on_erlang() -> true.

%% Runs `F` with the `TZ` setting set to `Value`, then puts it back.
with_tz(Value, F) ->
    Old = os:getenv("TZ"),
    os:putenv("TZ", unicode:characters_to_list(Value)),
    try F() after
        case Old of
            false -> os:unsetenv("TZ");
            _ -> os:putenv("TZ", Old)
        end
    end.
