%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <>
%%%-------------------------------------------------------------------
-module(msync_c2s).
-include("logger.hrl").
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).


%% internal export functions
-export([worker_entry_point/2, guard_entry_point/1]).
-define(SERVER, ?MODULE).

-record(state, { workers = #{} }).

%%%===================================================================
%% % API
%% %===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    %% process_flag(trap_exit, true),
    catch shaper:init(),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(Info, State) ->
    spawn_opt(?MODULE, worker_entry_point,[self(), Info], application:get_env(msync,worker_spawn_options,[])),
    {noreply, State }.

worker_entry_point(Pid, Info) ->
    WorkerPid = self(),
    spawn(?MODULE, guard_entry_point, [WorkerPid]),
    msync_c2s_handler:handle(Pid, Info).

guard_entry_point(WorkerPid) ->
    msync_c2s_guard:inc(),
    erlang:monitor(process, WorkerPid),
    Limit = application:get_env(msync, realtime_limit, 60000),
    receive
        {'DOWN', _MonitorRef, _Type, WorkerPid, _Info} ->
            %% io:format("worker is done ~p~n", [WorkerPid])
            ok
    after Limit ->
            ?WARNING_MSG("killing lazy worker ~p: ~p~n",[WorkerPid, erlang:process_info(WorkerPid, current_stacktrace)]),
            exit(WorkerPid, kill)
    end,
    msync_c2s_guard:dec().


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(Reason, _State) ->
    ?INFO_MSG("MSYNC C2S IS TERMINATING: REASON=~p~n",[Reason]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
