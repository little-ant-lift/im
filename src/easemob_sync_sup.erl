%%%-------------------------------------------------------------------
%%% @author clanchun <clanchun@gmail.com>
%%% @copyright (C) 2017, clanchun
%%% @doc
%%%
%%% @end
%%% Created : 13 Sep 2017 by clanchun <clanchun@gmail.com>
%%%-------------------------------------------------------------------
-module(easemob_sync_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart intensity, and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    Children = init_sync_manager() ++ init_producer_specs()
        ++ init_consumer_specs(),
    {ok, {{one_for_one, 1, 5}, Children}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
init_sync_manager() ->
    Spec =
        {easemob_sync_manager,
         {easemob_sync_manager, start_link, []},
         permanent,
         5000,
         worker,
         [easemob_sync_manager]
        },
    [Spec].

init_producer_specs() ->
    Clients = application:get_env(msync, data_sync_producer_clients, []),
    do_init_producer_specs(Clients).

do_init_producer_specs([]) ->
    [];
do_init_producer_specs([Client | T]) ->
    {ok, Opts} = application:get_env(msync, Client),
    Topic = proplists:get_value(topic, Opts),
    ClientID = proplists:get_value(client_id, Opts),
    DataSourceConfig = proplists:get_value(data_source, Opts),
    DataSourceClientID = proplists:get_value(client_id, DataSourceConfig),
    DataSourceHost = proplists:get_value(host, DataSourceConfig),
    DataSourcePort = proplists:get_value(port, DataSourceConfig),
    DataSourceTopic = proplists:get_value(topic, DataSourceConfig),
    DataSourceGroupID = proplists:get_value(group_id, DataSourceConfig),
    GroupConfig = get_group_config(),
    ConsumerConfig = get_consumer_config(),
    Spec =
        {Client,
         {easemob_sync_producer, start_link, [Client, ClientID, Topic,
                                              {DataSourceClientID,
                                               [{DataSourceHost, DataSourcePort}],
                                               DataSourceTopic,
                                               DataSourceGroupID
                                              },
                                              GroupConfig,
                                              ConsumerConfig]},
         permanent,
         5000,
         worker,
         [easemob_sync_producer]
        },
    [Spec | do_init_producer_specs(T)].

init_consumer_specs() ->
    Clients = application:get_env(msync, data_sync_consumer_clients, []),
    do_init_consumer_specs(Clients).

do_init_consumer_specs([]) ->
    [];
do_init_consumer_specs([Client | T]) ->
    {ok, Opts} = application:get_env(msync, Client),
    Host = proplists:get_value(host, Opts),
    Port = proplists:get_value(port, Opts),
    EndPoint = [{Host, Port}],
    ClientID = proplists:get_value(client_id, Opts),
    GroupID = proplists:get_value(group_id, Opts),
    Topic = proplists:get_value(topic, Opts),
    GroupConfig = get_group_config(),
    ConsumerConfig = get_consumer_config(),
    CallbackModule = easemob_sync_consumer,

    Spec =
        {Client,
         {easemob_sync_consumer, start_link,
          [Client, EndPoint, ClientID, GroupID, Topic,
           GroupConfig, ConsumerConfig, CallbackModule]},
         permanent,
         5000,
         worker,
         [easemob_sync_consumer]
        },
    [Spec | do_init_consumer_specs(T)].

get_group_config() ->
    application:get_env(msync, data_sync_group_config, []).

get_consumer_config() ->
    application:get_env(msync, data_sync_consumer_config, []).

