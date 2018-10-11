%% @author Mochi Media <dev@mochimedia.com>
%% @copyright 2010 Mochi Media <dev@mochimedia.com>

%% @doc Supervisor for the msync application.

-module(msync_sup).
-author("Mochi Media <dev@mochimedia.com>").
-include("logger.hrl").
-behaviour(supervisor).

%% External exports
-export([start_link/0, upgrade/0]).

%% supervisor callbacks
-export([init/1]).

%% @spec start_link() -> ServerRet
%% @doc API for starting the supervisor.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @spec upgrade() -> ok
%% @doc Add processes if necessary.
upgrade() ->
    {ok, {_, Specs}} = init([]),

    Old = sets:from_list(
            [Name || {Name, _, _, _} <- supervisor:which_children(?MODULE)]),
    New = sets:from_list([Name || {Name, _, _, _, _, _} <- Specs]),
    Kill = sets:subtract(Old, New),

    sets:fold(fun (Id, ok) ->
                      supervisor:terminate_child(?MODULE, Id),
                      supervisor:delete_child(?MODULE, Id),
                      ok
              end, ok, Kill),

    [supervisor:start_child(?MODULE, Spec) || Spec <- Specs],
    ok.

%% @spec init([]) -> SupervisorTree
%% @doc supervisor callback.
init([]) ->
    Processes = [
                 user_sup(),
                 web_specs(),
                 media_server_sup(),
                 c2s_license(),
                 health_server(),
                 etcd_client(),
                 easemob_message_limit_queue_sup(),
                 client_sup(),
                 listener_sup(),
                 old_c2s_sup(),
                 sync_sup()
                ],
    Strategy = {one_for_one, 10, 10},
    {ok,
     {Strategy, lists:flatten(Processes)}}.

user_sup() ->
	{ok, Config} = application:get_env(user),
	?INFO_MSG("MSYNC user config ~p~n", [Config]),
	PoolSize = proplists:get_value(pool_size, Config),
	Servers = proplists:get_value(servers, Config),
	Bypassed = proplists:get_value(bypassed, Config, false),
	{msync_user,
	 {msync_user, start_link, [PoolSize, Servers, Bypassed]},
	 permanent,
	 1000,
	 supervisor,
	 [msync_user]
	}.

web_specs() ->
    Mod = msync_web,
    {ok, Port} = application:get_env(msync, web_port),
    WebConfig = [{ip, {0,0,0,0}},
                 {port, Port},
                 {docroot, msync_deps:local_path(["priv", "www"])}],
    {Mod,
     {Mod, start, [WebConfig]},
     permanent, 5000, worker, dynamic}.

listener_sup() ->
    {ok, Port} = application:get_env(msync, port),
    AcceptorNum = application:get_env(msync, acceptors, 32),
    ?INFO_MSG("MSYNC SERVER LISTENIN ON PORT ~p~n",[Port]),
    {
      msync_server,
      {msync_server, start_link, [[{acceptor_pool_size, AcceptorNum}]]},
      permanent,
      1000,
      worker,
      [msync_server]
    }.

client_sup() ->
    {msync_client_sup,
     {msync_client_sup, start_link, []},
     permanent,
     1000,
     supervisor,
     [msync_client_sup]
    }.

old_c2s_sup() ->
    {msync_c2s_sup,
     { msync_c2s_sup, start_link, []},
     permanent,
     1000,
     supervisor,
     [ msync_c2s_sup ]
    }.

sync_sup() ->
    {easemob_sync_sup,
     {easemob_sync_sup, start_link, []},
     permanent,
     1000,
     supervisor,
     [easemob_sync_sup]
    }.

c2s_license() ->
    {
      ejabberd_license,
      { ejabberd_license, start_link, [] },
      permanent,
      1000,
      worker,
      [ ejabberd_license ]
     }.

%% thrift_sup() ->
%%     _ThriftSup = {
%%       msync_thrift_sup,
%%       { msync_thrift_sup, start_link, []},
%%       permanent,
%%       1000,
%%       supervisor,
%%       [ media_server_sup ]
%%      }.

media_server_sup() ->
    _MediaServerSup = {
      media_server_sup,
      { media_server_sup, start_link, []},
      permanent,
      1000,
      supervisor,
      [ media_server_sup ]
     }.

health_server() ->
	{
	 health_monitor,
	 {health_monitor, start_link, []},
	 permanent,
	 infinity,
	 worker,
	 [health_monitor]
	}.

etcd_client() ->
    {msync_etcd_client,
     {msync_etcd_client, start_link, []},
     permanent,
     infinity,
     worker,
     [msync_etcd_client]
    }.

easemob_message_limit_queue_sup() ->
    {easemob_message_limit_queue_sup,
     {easemob_message_limit_queue_sup, start_link, []},
     permanent,
     infinity,
     supervisor,
     [easemob_message_limit_queue_sup]
    }.
