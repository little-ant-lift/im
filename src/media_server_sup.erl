-module(media_server_sup).

-behaviour(supervisor).

-export([start_link/0,
         start_child/0,
         init/1]).


start_link()->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).
start_child()->
    supervisor:start_child(?MODULE, []).

init([])->
    SupFlags = { one_for_one, 5, 10 },
    ChildDesc = {media_server, {media_server, start_link, []},
                 permanent, 5000, worker, [media_server]},
    {ok, {SupFlags, [ChildDesc]}}.
