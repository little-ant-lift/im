%%%-------------------------------------------------------------------
%%% @author WangChunye <>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <>
%%%-------------------------------------------------------------------
-module(msync_c2s_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_child/0]).

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
start_child() ->
    supervisor:start_child(?SERVER,[]).
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
    %% is it a good idea to hold a ets table by a supervisor?  maybe
    %% OK. there might be many msync_c2s worker to balance load in the
    %% future.
    catch msync_c2s_lib:create_tables(),
    msync_msg:init(),
    SupFlags = { one_for_one,
                 1,
                 5 },

    C2SGuard = {
      msync_c2s_guard,
      { msync_c2s_guard, start_link, []},
      permanent,
      5000,
      worker,
      [ msync_c2s_guard ]
     },
    C2S = {
      msync_c2s,
      { msync_c2s, start_link, []},
      permanent,
      infinity,
      worker,
      [ msync_c2s ]
     },

    {ok, {SupFlags, [C2SGuard, C2S]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
