%%%-------------------------------------------------------------------
%%% @author zou <>
%%% @copyright (C) 2016, zou
%%% @doc
%%%
%%% @end
%%% Created :  1 Dec 2016 by zou <>
%%%-------------------------------------------------------------------
-module(easemob_message_limit_queue_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_workers/1, stop_workers/1, start/0, stop/0]).
%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-define(SUP, msync_sup).

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

start_workers(ChildSpecs) ->
    lists:foreach(fun(Spec) ->
                          supervisor:start_child(?SERVER, Spec)
                  end, ChildSpecs).

stop_workers(Workers) ->
    lists:foreach(fun(Worker) ->
                          supervisor:terminate_child(?SERVER, Worker),
                          supervisor:delete_child(?SERVER, Worker)
                  end, Workers).

start() ->
    ChildSpec =
        {?SERVER,
         {?SERVER, start_link, []},
         permanent,
         infinity,
         supervisor,
         [?SERVER]
        },
    supervisor:start_child(?SUP, ChildSpec).

stop() ->
    supervisor:terminate_child(?SUP, ?SERVER),
    supervisor:delete_child(?SUP, ?SERVER).
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
    ChildSpec = mod_message_limit:init_spec(),
    SupFlags = {one_for_one, 10*length(ChildSpec), 1},
    {ok, {SupFlags, ChildSpec}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
