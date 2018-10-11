%% @author Mochi Media <dev@mochimedia.com>
%% @copyright 2010 Mochi Media <dev@mochimedia.com>

%% @doc msync.

-module(msync).
-author("Mochi Media <dev@mochimedia.com>").
-export([start/0, stop/0]).

%% ensure_started(App) ->
%%     case application:start(App) of
%%         ok ->
%%             ok;
%%         {error, {already_started, App}} ->
%%             ok
%%     end.


%% @spec start() -> ok
%% @doc Start the msync server.
start() ->
    %% msync_deps:ensure(),
    %% ensure_started(crypto),
    application:ensure_all_started(msync).



%% @spec stop() -> ok
%% @doc Stop the msync server.
stop() ->
    application:stop(msync).
