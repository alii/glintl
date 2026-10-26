-module(glintl_conformance_ffi).
-export([read_line/0]).

%% Reads a line from standard input as UTF-8, without its newline.
read_line() ->
    ok = io:setopts(standard_io, [binary, {encoding, unicode}]),
    case io:get_line("") of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line -> {ok, string:trim(Line, trailing, "\n")}
    end.
