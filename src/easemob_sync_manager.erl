%%%-------------------------------------------------------------------
%%% @author clanchun <clanchun@gmail.com>
%%% @copyright (C) 2017, clanchun
%%% @doc
%%%
%%% @end
%%% Created : 17 Oct 2017 by clanchun <clanchun@gmail.com>
%%%-------------------------------------------------------------------
-module(easemob_sync_manager).

-behaviour(gen_server).

%% API
-export([start_link/0]).

-export([join_cluster/2,
         leave_cluster/2
        ]).

-export([start_producer/0,
         cancel_producer/0,
         pause_producer/0,
         continue_producer/0,
         start_full_consumer/0,
         stop_full_consumer/0,
         start_incr_consumer/0,
         stop_incr_consumer/0
        ]).

-export([report/2,
         get_report/1,
         get_failure_ignored_users/0,
         reset_counters/0
        ]).

-export([handle_cmd/2]).

-export([make_cmd/3,
         make_user/1
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(task, {job_id,
               type,
               command,
               total,
               from,
               to,
               appkey,
               desc,
               start_time,
               status,
               error
              }).

-record(state, {host,
                port,
                nodes = [],
                message_task,
                roster_task,
                privacy_task,
                full_consumer_status,
                incr_consumer_status,
                pms = 0,
                pmf = 0,
                pmi = 0,
                prs = 0,
                prf = 0,
                pri = 0,
                pps = 0,
                ppf = 0,
                ppi = 0,
                cms = 0,
                cmf = 0,
                crs = 0,
                crf = 0,
                cps = 0,
                cpf = 0
               }).

-define(CMD_FETCHER, cmd_fetcher).
-define(SYNC_COUNTER, sync_counter).
-define(STATUS_REPORTER, status_reporter).

-include("logger.hrl").

%% sync counter keys
-define(PMS, <<"im:sync:producer:message:success">>).
-define(PMF, <<"im:sync:producer:message:failure">>).
-define(PMI, <<"im:sync:producer:message:ignored">>).
-define(PRS, <<"im:sync:producer:roster:success">>).
-define(PRF, <<"im:sync:producer:roster:failure">>).
-define(PRI, <<"im:sync:producer:roster:ignored">>).
-define(PPS, <<"im:sync:producer:privacy:success">>).
-define(PPF, <<"im:sync:producer:privacy:failure">>).
-define(PPI, <<"im:sync:producer:privacy:ignored">>).

-define(CMS, <<"im:sync:consumer:message:success">>).
-define(CMF, <<"im:sync:consumer:message:failure">>).
-define(CRS, <<"im:sync:consumer:roster:success">>).
-define(CRF, <<"im:sync:consumer:roster:failure">>).
-define(CPS, <<"im:sync:consumer:privacy:success">>).
-define(CPF, <<"im:sync:consumer:privacy:failure">>).

-define(PMFL, <<"im:sync:producer:message:failure-list">>).
-define(PMIL, <<"im:sync:producer:message:ignored-list">>).
-define(PRFL, <<"im:sync:producer:roster:failure-list">>).
-define(PRIL, <<"im:sync:producer:roster:ignored-list">>).
-define(PPFL, <<"im:sync:producer:privacy:failure-list">>).
-define(PPIL, <<"im:sync:producer:privacy:ignored-list">>).

-define(CMD_KEY, <<"data-sync-cmd">>).
-define(MESSAGE_REPORT_KEY, <<"com.easemob.yun.migration.status.message">>).
-define(ROSTER_REPORT_KEY, <<"com.easemob.yun.migration.status.roster">>).
-define(PRIVACY_REPORT_KEY, <<"com.easemob.yun.migration.status.privacy">>).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

join_cluster(MasterNode, Node) ->
    gen_server:call({?SERVER, MasterNode}, {join_cluster, Node}).

leave_cluster(MasterNode, Node) ->
    gen_server:call({?SERVER, MasterNode}, {leave_cluster, Node}).

start_producer() ->
    handle_cmd(producer, <<"start">>).

cancel_producer() ->
    handle_cmd(producer, <<"cancel">>).

pause_producer() ->
    handle_cmd(producer, <<"pause">>).

continue_producer() ->
    handle_cmd(producer, <<"continue">>).

start_full_consumer() ->
    handle_cmd(full_consumer, <<"start">>).

stop_full_consumer() ->
    handle_cmd(full_consumer, <<"stop">>).

start_incr_consumer() ->
    handle_cmd(incr_consumer, <<"start">>).

stop_incr_consumer() ->
    handle_cmd(incr_consumer, <<"stop">>).

handle_cmd(Type, Command) ->
    gen_server:call(?SERVER, {handle_cmd, Type, Command}).

report(Type, Num) ->
    gen_server:cast(?SERVER, {incr, Type, Num}).

get_report(Type) ->
    gen_server:call(?SERVER, {get_report, Type}).

get_failure_ignored_users() ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    Res = eredis:qp(Client, [[lrange, ?PMFL, 0, -1],
                             [lrange, ?PMIL, 0, -1],
                             [lrange, ?PRFL, 0, -1],
                             [lrange, ?PRIL, 0, -1],
                             [lrange, ?PPFL, 0, -1],
                             [lrange, ?PPIL, 0, -1]]),
    Users = lists:map(fun ({ok, undefined}) ->
                              [];
                          ({ok, L}) ->
                              L;
                          (_) ->
                              []
                      end, Res),
    lists:zip([message_failure, message_ignored,
               roster_failure, roster_ignored,
               privacy_failure, privacy_ignored],
              Users).

reset_counters() ->
    gen_server:cast(?SERVER, reset_counters).

make_cmd(Id, Type, Cmd) ->
    gen_server:call(?SERVER, {make_cmd, Id, Type, Cmd}).

make_user(User) ->
    Data = [{<<"dataType">>, <<"user_entities">>},
            {<<"orgName">>, <<"easemob-demo">>},
            {<<"appName">>, <<"chatdemoui">>},
            {<<"name">>, User}],
    jsx:encode(Data).

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
    process_flag(trap_exit, true),
    case application:get_env(msync, sync_endpoint) of
        {ok, [{host, Host}, {port, Port}]} ->
            cuesport:start_link(?CMD_FETCHER, 5,
                                [eredis, eredis_client, eredis_parser],
                                {eredis, start_link, [Host, Port]}),
            cuesport:start_link(?SYNC_COUNTER, 5,
                                [eredis, eredis_client, eredis_parser],
                                {eredis, start_link, [Host, Port]}),
            cuesport:start_link(?STATUS_REPORTER, 5,
                                [eredis, eredis_client, eredis_parser],
                                {eredis, start_link, [Host, Port]}),
            case application:get_env(msync, is_sync_master, false) of
                true ->
                    self() ! fetch_cmd,
                    self() ! report_status,
                    {ok, #state{host = Host,
                                port = Port,
                                nodes = [node()]
                               }};
                false ->
                    {ok, #state{nodes = [node()]}}
            end;
        _ ->
            {ok, #state{}}
    end.

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
handle_call({join_cluster, Node}, _From, #state{nodes = Nodes} = State) ->
    case lists:member(Node, Nodes) of
        true ->
            {reply, already_joined, State};
        false ->
            {reply, joined, State#state{nodes = [Node | Nodes]}}
    end;

handle_call({leave_cluster, Node}, _From, #state{nodes = Nodes} = State) ->
    {reply, left, State#state{nodes = Nodes -- [Node]}};

handle_call({handle_cmd, producer, Command}, _From, #state{nodes = Nodes} = State) ->
    lists:foreach(fun (Node) ->
                          {sync_message_full_producer, Node} ! Command,
                          {sync_roster_full_producer, Node} ! Command,
                          {sync_privacy_full_producer, Node} ! Command
                  end, Nodes),
    Status = transfer_status(Command),
    ?INFO_MSG("all producers ~p~n", [Status]),
    {reply, Status, State#state{message_task = #task{type = <<"message">>,
                                                     status = Status},
                                roster_task = #task{type = <<"roster">>,
                                                    status = Status},
                                privacy_task = #task{type = <<"privacy">>,
                                                     status = Status}
                               }};

handle_call({handle_cmd, full_consumer, Command}, _From, #state{nodes = Nodes} = State) ->
    lists:foreach(fun (Node) ->
                          {sync_message_full_consumer, Node} ! Command,
                          {sync_roster_full_consumer, Node} ! Command,
                          {sync_privacy_full_consumer, Node} ! Command
                  end, Nodes),
    Status = transfer_status(Command),
    ?INFO_MSG("all full consumers ~p~n", [Status]),
    {reply, Status, State#state{full_consumer_status = Status}};

handle_call({handle_cmd, incr_consumer, Command}, _From, #state{nodes = Nodes} = State) ->
    lists:foreach(fun (Node) ->
                          {sync_message_incr_consumer, Node} ! Command,
                          {sync_roster_incr_consumer, Node} ! Command,
                          {sync_privacy_incr_consumer, Node} ! Command
                  end, Nodes),
    Status = transfer_status(Command),
    ?INFO_MSG("all incr consumers ~p~n", [Status]),
    {reply, Status, State#state{incr_consumer_status = Status}};

handle_call({get_report, producer}, _From, #state{
                                              message_task = MessageTask,
                                              roster_task = RosterTask,
                                              privacy_task = PrivacyTask
                                             } = State) ->
    MessageReport = get_producer_status(MessageTask),
    RosterReport = get_producer_status(RosterTask),
    PrivacyReport = get_producer_status(PrivacyTask),
    {reply, {MessageReport, RosterReport, PrivacyReport}, State};

handle_call({get_report, consumer}, _From, #state{
                                              full_consumer_status  = FullStatus,
                                              incr_consumer_status = IncrStatus
                                             } = State) ->
    Result = [{full_status, FullStatus}, {incr_status, IncrStatus}]
        ++ get_consumer_status(),
    {reply, Result, State};

handle_call({make_cmd, Id, Type, Cmd}, _From, State) ->
    J = jsx:encode([{<<"jobId">>, Id},
                    {<<"type">>, atom_to_binary(Type, utf8)},
                    {<<"command">>, atom_to_binary(Cmd, utf8)},
                    {<<"total">>, 100},
                    {<<"from">>, <<"a">>},
                    {<<"to">>, <<"b">>},
                    {<<"appkey">>, <<"abc#def">>},
                    {<<"description">>, <<"hello">>}
                   ]),
    Client = cuesport:get_worker(?CMD_FETCHER),
    eredis:q(Client, [rpush, cmd_key(), J]),
    {reply, Cmd, State}.

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
handle_cast({incr, pms, N}, #state{pms = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(pms)]),
    {noreply, State#state{pms = M + N}};
handle_cast({incr, pmf, {N, Users}}, #state{pmf = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(pmf)]),
    eredis:q(Client, [lpush, user_list_key(pmf)] ++ Users),
    {noreply, State#state{pmf = M + N}};
handle_cast({incr, pmi, {N, Users}}, #state{pmi = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(pmi)]),
    eredis:q(Client, [lpush, user_list_key(pmi)] ++ Users),
    {noreply, State#state{pmi = M + N}};
handle_cast({incr, prs, N}, #state{prs = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(prs)]),
    {noreply, State#state{prs = M + N}};
handle_cast({incr, prf, {N, Users}}, #state{prf = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(prf)]),
    eredis:q(Client, [lpush, user_list_key(prf)] ++ Users),
    {noreply, State#state{prf = M + N}};
handle_cast({incr, pri, {N, Users}}, #state{pri = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(pri)]),
    eredis:q(Client, [lpush, user_list_key(pri)] ++ Users),
    {noreply, State#state{pri = M + N}};
handle_cast({incr, pps, N}, #state{pps = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(pps)]),
    {noreply, State#state{pps = M + N}};
handle_cast({incr, ppf, {N, Users}}, #state{ppf = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(ppf)]),
    eredis:q(Client, [lpush, user_list_key(ppf)] ++ Users),
    {noreply, State#state{ppf = M + N}};
handle_cast({incr, ppi, {N, Users}}, #state{ppi = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(ppi)]),
    eredis:q(Client, [lpush, user_list_key(ppi)] ++ Users),
    {noreply, State#state{ppi = M + N}};

handle_cast({incr, cms, N}, #state{cms = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(cms)]),
    {noreply, State#state{cms = M + N}};
handle_cast({incr, cmf, N}, #state{cmf = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(cmf)]),
    {noreply, State#state{cmf = M + N}};
handle_cast({incr, crs, N}, #state{crs = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(crs)]),
    {noreply, State#state{crs = M + N}};
handle_cast({incr, crf, N}, #state{crf = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(crf)]),
    {noreply, State#state{cmf = M + N}};
handle_cast({incr, cps, N}, #state{cps = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(cps)]),
    {noreply, State#state{cps = M + N}};
handle_cast({incr, cpf, N}, #state{cpf = M} = State) ->
    Client = cuesport:get_worker(?SYNC_COUNTER),
    eredis:q(Client, [incr, counter_key(cpf)]),
    {noreply, State#state{cpf = M + N}};

handle_cast(reset_counters, State) ->
    Client = cuesport:get_worker(?STATUS_REPORTER),
    eredis:qp(Client, [[del, ?PMS],
                       [del, ?PMF],
                       [del, ?PMI],
                       [del, ?PRS],
                       [del, ?PRF],
                       [del, ?PRI],
                       [del, ?PPS],
                       [del, ?PPF],
                       [del, ?PPI],
                       [del, ?CMS],
                       [del, ?CMF],
                       [del, ?CRS],
                       [del, ?CRF],
                       [del, ?CPS],
                       [del, ?CPF],
                       [del, ?PMFL],
                       [del, ?PMIL],
                       [del, ?PRFL],
                       [del, ?PRIL],
                       [del, ?PPFL],
                       [del, ?PPIL]
                      ]),
    {noreply, State#state{pms = 0,
                            pmf = 0,
                            pmi = 0,
                            prs = 0,
                            prf = 0,
                            pri = 0,
                            pps = 0,
                            ppf = 0,
                            ppi = 0,
                            cms = 0,
                            cmf = 0,
                            crs = 0,
                            crf = 0,
                            cps = 0,
                            cpf = 0}};

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
handle_info(fetch_cmd, State) ->
    Client = cuesport:get_worker(?CMD_FETCHER),
    case get_cmd(Client) of
        {ok, undefined} ->
            erlang:send_after(5000, self(), fetch_cmd),
            {noreply, State};
        {ok, TaskData} ->
            case check_task(TaskData) of
                {ok, Task} ->
                    ?INFO_MSG("fetched new task: ~p~n", [Task]),
                    NewState = handle_task(Task, State),
                    erlang:send_after(5000, self(), fetch_cmd),
                    {noreply, NewState};
                {error, Reason, Task} ->
                    ?ERROR_MSG("wrong task: ~p, due to: ~p~n", [Task, Reason]),
                    erlang:send_after(5000, self(), fetch_cmd),
                    {noreply, State}
            end;
        {error, Reason} ->
            ?ERROR_MSG("fetch task error, reason: ~p~n", [Reason]),
            {noreply, State}
    end;

handle_info(report_status, #state{message_task = MessageTask,
                                  roster_task = RosterTask,
                                  privacy_task = PrivacyTask
                                 } = State) ->
    report_status(MessageTask),
    report_status(RosterTask),
    report_status(PrivacyTask),
    erlang:send_after(5000, self(), report_status),
    {noreply, State};

handle_info({cmd, Type, Command}, State) ->
    try
        case Type of
            <<"message">> ->
                sync_message_full_producer ! Command;
            <<"roster">> ->
                sync_roster_full_producer ! Command;
            <<"privacy">> ->
                sync_privacy_full_producer ! Command
        end
    catch
        Class: Reason ->
            ?ERROR_MSG("handle cmd: ~p error, type: ~p class: ~p, reason: ~p, stack: ~p~n",
                       [Command, Type, Class, Reason, erlang:get_stacktrace()])
    end,
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

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
terminate(_Reason, _State) ->
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
get_cmd(Client) ->
    eredis:q(Client, [lpop, cmd_key()]).

check_task(Data) ->
    try parse_task(Data) of
        #task{type = Type, command = Command} = Task ->
            case Type of
                _ when Type == <<"message">>;
                       Type == <<"roster">>;
                       Type == <<"privacy">> ->
                    case Command of
                        _ when Command == <<"start">>;
                               Command == <<"cancel">>;
                               Command == <<"pause">>;
                               Command == <<"continue">> ->
                            {ok, Task};
                        _ ->
                            {error, unknown_command, Task}
                    end;
                _ ->
                    {error, unknown_type, Task}
            end
    catch
        _: _ ->
            {error, parse_error, Data}
    end.

parse_task(Data) ->
    DecodedData = jsx:decode(Data),
    JobID = proplists:get_value(<<"jobId">>, DecodedData),
    Type = proplists:get_value(<<"type">>, DecodedData),
    Command = proplists:get_value(<<"command">>, DecodedData),
    Total = proplists:get_value(<<"total">>, DecodedData, -1),
    From = proplists:get_value(<<"from">>, DecodedData),
    To = proplists:get_value(<<"to">>, DecodedData),
    AppKey = proplists:get_value(<<"appkey">>, DecodedData),
    Desc = proplists:get_value(<<"description">>, DecodedData),
    #task{job_id = JobID,
          type = Type,
          command = Command,
          total = Total,
          from = From,
          to = To,
          appkey = AppKey,
          desc = Desc
         }.

handle_task(#task{type = Type, command = Command} = Task,
            #state{message_task = MessageTask,
                   roster_task = RosterTask,
                   privacy_task = PrivacyTask,
                   nodes = Nodes
                  } = State) ->
    Status = transfer_status(Command),
    case check_status(Type, Status, MessageTask, RosterTask, PrivacyTask) of
        false ->
            ?INFO_MSG("ignore due to status conflict, task: ~p~n", [Task]),
            State;
        true ->
            try handle_cmd(Type, Command, Nodes) of
                ok ->
                    NewTask = Task#task{
                                start_time = time_compat:erlang_system_time(seconds),
                                status = Status,
                                error = normal,
                                desc = <<"task ", (atom_to_binary(Status, utf8))/binary>>
                               },
                    NewState =
                        case Type of
                            <<"message">> ->
                                State#state{message_task = NewTask};
                            <<"roster">> ->
                                State#state{roster_task = NewTask};
                            <<"privacy">> ->
                                State#state{privacy_task = NewTask}
                        end,
                    report_status(NewTask),
                    case Command of
                        <<"cancel">> ->
                            reset_counters();
                        _ ->
                            ignore
                    end,
                    NewState
            catch
                Class: Reason ->
                    ?ERROR_MSG("handle task error, class: ~p, reason: ~p, stack: ~p~n",
                               [Task, Class, Reason, erlang:get_stacktrace()]),
                    ErrorTask = Task#task{
                                  start_time = time_compat:erlang_system_time(seconds),
                                  status = error,
                                  error = Reason,
                                  desc = <<"task error">>
                                 },
                    report_status(ErrorTask),
                    State
            end
    end.

check_status(<<"message">>, _Status, undefined, _, _) ->
    true;
check_status(<<"message">>, Status, MessageTask, _, _) ->
    MessageTask#task.status =/= Status;
check_status(<<"roster">>, _Status, _, undefined, _) ->
    true;
check_status(<<"roster">>, Status, _, RosterTask, _) ->
    RosterTask#task.status =/= Status;
check_status(<<"privacy">>, _Status, _, _, undefined) ->
    true;
check_status(<<"privacy">>, Status, _, _, PrivacyTask) ->
    PrivacyTask#task.status =/= Status.

report_status(undefined) ->
    ignore;
report_status(Task) ->
    Report = get_producer_status(Task),
    Client = cuesport:get_worker(?STATUS_REPORTER),
    ReportKey =
        case Task#task.type of
            <<"message">> ->
                message_report_key();
            <<"roster">> ->
                roster_report_key();
            <<"privacy">> ->
                privacy_report_key()
        end,
    eredis:q(Client, [set, ReportKey, jsx:encode(Report)]).

get_producer_status(undefined) ->
    no_task;
get_producer_status(#task{job_id = JobID,
                          type = Type,
                          total = Total,
                          start_time = StartTime,
                          status = Status,
                          error = Error
                         }) ->
    Client = cuesport:get_worker(?STATUS_REPORTER),
    Counters =
        case Type of
            <<"message">> ->
                eredis:qp(Client, [[get, ?PMS],
                                   [get, ?PMF],
                                   [get, ?PMI]]);
            <<"roster">> ->
                eredis:qp(Client, [[get, ?PRS],
                                   [get, ?PRF],
                                   [get, ?PRI]]);
            <<"privacy">> ->
                eredis:qp(Client, [[get, ?PPS],
                                   [get, ?PPF],
                                   [get, ?PPI]])
        end,
    CounterReport = lists:zip([success, failure, ignored], transfer_counter(Counters)),
    Report = [{jobId, JobID},
              {type, Type},
              {status, Status},
              {error, Error},
              {timestamp, time_compat:erlang_system_time(seconds)},
              {startTime, StartTime},
              {total, Total},
              {description, <<"task ", (atom_to_binary(Status, utf8))/binary>>}] ++ CounterReport,

    Report.

get_consumer_status() ->
    Client = cuesport:get_worker(?STATUS_REPORTER),
    Counters = eredis:qp(Client, [[get, ?CMS],
                                  [get, ?CMF],
                                  [get, ?CRS],
                                  [get, ?CRF],
                                  [get, ?CPS],
                                  [get, ?CPF]]),
    NewCounters = transfer_counter(Counters),
    lists:zip([cms, cmf, crs, crf, cps, cpf], NewCounters).

transfer_counter(Counters) ->
    lists:map(fun ({ok, undefined}) ->
                      0;
                  ({ok, Bin}) ->
                      binary_to_integer(Bin);
                  ({error, Reason}) ->
                      ?ERROR_MSG("get sync counter error, reason: ~p~n", [Reason]),
                      0
              end, Counters).

handle_cmd(Type, Command, Nodes) ->
    [{?SERVER, Node} ! {cmd, Type, Command} || Node <- Nodes],
    ok.

transfer_status(<<"start">>) ->
    started;
transfer_status(<<"cancel">>) ->
    canceled;
transfer_status(<<"pause">>) ->
    paused;
transfer_status(<<"continue">>) ->
    continued;
transfer_status(<<"stop">>) ->
    stopped;
transfer_status(_) ->
    unkown_command.

counter_key(pms) ->
    ?PMS;
counter_key(pmf) ->
    ?PMF;
counter_key(pmi) ->
    ?PMI;
counter_key(prs) ->
    ?PRS;
counter_key(prf) ->
    ?PRF;
counter_key(pri) ->
    ?PRI;
counter_key(pps) ->
    ?PPS;
counter_key(ppf) ->
    ?PPF;
counter_key(ppi) ->
    ?PPI;
counter_key(cms) ->
    ?CMS;
counter_key(cmf) ->
    ?CMF;
counter_key(crs) ->
    ?CRS;
counter_key(crf) ->
    ?CRF;
counter_key(cps) ->
    ?CPS;
counter_key(cpf) ->
    ?CPF.

user_list_key(pmf) ->
    ?PMFL;
user_list_key(pmi) ->
    ?PMIL;
user_list_key(prf) ->
    ?PRFL;
user_list_key(pri) ->
    ?PRIL;
user_list_key(ppf) ->
    ?PPFL;
user_list_key(ppi) ->
    ?PPIL.

cmd_key() ->
    application:get_env(msync, data_sync_cmd_key, ?CMD_KEY).

message_report_key() ->
    application:get_env(msync, data_sync_message_report_key, ?MESSAGE_REPORT_KEY).

roster_report_key() ->
    application:get_env(msync, data_sync_roster_report_key, ?ROSTER_REPORT_KEY).

privacy_report_key() ->
    application:get_env(msync, data_sync_privacy_report_key, ?PRIVACY_REPORT_KEY).
