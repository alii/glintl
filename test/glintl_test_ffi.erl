-module(glintl_test_ffi).
-export([on_erlang/0]).

%% Some behaviour differs by target, as JavaScript uses `Intl`.
on_erlang() -> true.
