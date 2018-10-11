-module(msync_client_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

-export([start_client/1,
         stop_client/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%% ===================================================================
%% API functions
%% ===================================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_client(Sock) ->
    supervisor:start_child(?MODULE, [Sock]).

stop_client(Pid) ->
    supervisor:terminate_child(?MODULE, Pid).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok,
     {{simple_one_for_one, 10, 10},
      [
       {undefined,
        {msync_socket_client, start_link, []},
        temporary,
        brutal_kill,
        worker,
        [msync_socket_client]
       }
      ]
     }
    }.

