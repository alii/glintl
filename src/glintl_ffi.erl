-module(glintl_ffi).
-export([local_time_zone/0]).

%% The computer's time zone name: from `TZ`, or else where `/etc/localtime`
%% links to, or else `/etc/timezone`.
local_time_zone() ->
    case os:getenv("TZ") of
        Unset when Unset =:= false; Unset =:= "" -> from_files();
        [$: | Name] -> from_name(Name);
        Name -> from_name(Name)
    end.

from_files() ->
    case file:read_link("/etc/localtime") of
        {ok, Target} -> from_name(Target);
        {error, _} ->
            case file:read_file("/etc/timezone") of
                {ok, Contents} -> {ok, string:trim(Contents)};
                {error, _} -> {error, nil}
            end
    end.

%% A name, or a path like `/usr/share/zoneinfo/Europe/London`.
from_name(Name) ->
    case string:split(Name, "zoneinfo/", trailing) of
        [_, Zone] -> {ok, unicode:characters_to_binary(Zone)};
        [Zone] -> {ok, unicode:characters_to_binary(Zone)}
    end.
