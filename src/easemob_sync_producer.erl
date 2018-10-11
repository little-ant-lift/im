%%%-------------------------------------------------------------------
%%% @author clanchun <clanchun@gmail.com>
%%% @copyright (C) 2017, clanchun
%%% @doc Full sync producer
%%%
%%% @end
%%% Created : 13 Sep 2017 by clanchun <clanchun@gmail.com>
%%%-------------------------------------------------------------------
-module(easemob_sync_producer).

-behaviour(gen_server).
-behaviour(brod_group_subscriber).

%% API
-export([start_link/6]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% brod_group_subscriber callbacks
-export([init/2,
         handle_message/4
        ]).

-include_lib("brod/include/brod.hrl").
-include("logger.hrl").

-define(SERVER, ?MODULE).

-record(state, {client_id,
                endpoint,
                group_id,
                data_source,
                topic,
                group_config,
                consumer_config,
                subscriber,
                status = stopped %% started | stopped | canceled
               }).

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
start_link(ProducerName, ClientID, Topic,
           {DataSourceClientID,
            DataSourceEndpoint,
            DataSourceTopic,
            DataSourceGroupID
           },
           GroupConfig, ConsumerConfig) ->
    gen_server:start_link({local, ProducerName}, ?MODULE,
                          [ClientID, Topic,
                           {DataSourceClientID,
                            DataSourceEndpoint,
                            DataSourceTopic,
                            DataSourceGroupID
                           },
                           GroupConfig, ConsumerConfig], []).

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
init([ClientID, Topic,
      {DSClientID, DSEndpoint, _DSTopic, _DSGroupID} = DataSourceConfig,
      GroupConfig, ConsumerConfig]) ->
    process_flag(trap_exit, true),
    ok = brod:start_client(DSEndpoint, DSClientID, []),
    {ok, #state{client_id = ClientID,
                topic = Topic,
                data_source = DataSourceConfig,
                group_config = GroupConfig,
                consumer_config = ConsumerConfig
               }}.

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
handle_cast({kafka_message, DataTopic, Partition, Offset, Value},
            #state{client_id = ClientID,
                   topic = DestTopic,
                   subscriber = Subscriber} = State) ->
    handle_message(ClientID, Subscriber, DataTopic, Partition, Offset, Value, DestTopic),
    {noreply, State};

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
handle_info(<<"start">>, #state{client_id = CI,
                                data_source = {ClientID,
                                               _Endpoint,
                                               Topic,
                                               GroupID
                                              },
                                group_config = GroupConfig,
                                consumer_config = ConsumerConfig
                               } = State) ->
    {ok, Subscriber} = brod:start_link_group_subscriber(
                         ClientID, GroupID, [Topic], GroupConfig,
                         ConsumerConfig, ?MODULE, self()),
    ?INFO_MSG("producer ~p started~n", [CI]),
    {noreply, State#state{status = started,
                          subscriber = Subscriber
                         }};

handle_info(<<"cancel">>, #state{client_id = ClientID,
                                 subscriber = Subscriber} = State) ->
    brod_group_subscriber:stop(Subscriber),
    ?INFO_MSG("producer ~p canceled~n", [ClientID]),
    {noreply, State#state{subscriber = undefined, status = canceled}};

handle_info(<<"continue">>, #state{client_id = CI,
                                   data_source = {ClientID,
                                                  _Endpoint,
                                                  Topic,
                                                  GroupID
                                                 },
                                   group_config = GroupConfig,
                                   consumer_config = ConsumerConfig
                                  } = State) ->
    {ok, Subscriber} = brod:start_link_group_subscriber(
                         ClientID, GroupID, [Topic], GroupConfig,
                         ConsumerConfig, ?MODULE, self()),
    ?INFO_MSG("producer ~p continued~n", [CI]),
    {noreply, State#state{status = continued,
                          subscriber = Subscriber
                         }};

handle_info(<<"pause">>, #state{client_id = ClientID,
                                subscriber = Subscriber} = State) ->
    brod_group_subscriber:stop(Subscriber),
    ?INFO_MSG("producer ~p paused~n", [ClientID]),
    {noreply, State#state{subscriber = undefined, status = paused}};

handle_info({'EXIT', _SubscriberPid, normal}, State) ->
    {noreply, State};

handle_info(Msg, State) ->
    ?INFO_MSG("producer unknown msg: ~p, state: ~p~n", [Msg, State]),
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

init(_GroupID, HandlerName) ->
    {ok, HandlerName}.

%% @doc Handle one message (not message-set).
handle_message(Topic, Partition,
               #kafka_message{offset = Offset, value = Value},
               HandlerName) ->
    gen_server:cast(HandlerName, {kafka_message, Topic, Partition, Offset, Value}),
    {ok, HandlerName}.


%%%===================================================================
%%% Internal functions
%%%===================================================================
handle_message(ClientID, Subscriber, DataTopic, Partition, Offset, Value, DestTopic) ->
    try get_user(Value) of
        ignore ->
            ignore;
        {ok, User} ->
            try
                ?INFO_MSG("producing for user: ~p topic: ~p~n", [User, DestTopic]),
                Fun = producer_fun(ClientID),
                case easemob_sync_lib:Fun(ClientID, DestTopic, User) of
                    ignored ->
                        ReportType = report_type(ClientID, ignored),
                        easemob_sync_manager:report(ReportType, {1, [User]});
                    ok ->
                        ReportType = report_type(ClientID, success),
                        easemob_sync_manager:report(ReportType, 1)
                end
            catch
                Class: Reason ->
                    RT = report_type(ClientID, failure),
                    easemob_sync_manager:report(RT, {1, [User]}),
                    ?ERROR_MSG("produce data error, topic: ~p, user: ~p "
                               "class: ~p, reason: ~p, stack: ~p~n",
                               [DestTopic, User, Class, Reason, erlang:get_stacktrace()])
            end
    catch
        Class: Reason ->
            ?ERROR_MSG("fetch user error, client id: ~p, value: ~p, "
                       "class: ~p, reason: ~p, stack: ~p~n",
                       [ClientID, Value, Class, Reason, erlang:get_stacktrace()])
    end,
    brod_group_subscriber:ack(Subscriber, DataTopic, Partition, Offset).

get_user(Data) ->
    Json = jsx:decode(Data),
    case proplists:get_value(<<"dataType">>, Json) of
        <<"user_entities">> ->
            Org = proplists:get_value(<<"orgName">>, Json),
            App = proplists:get_value(<<"appName">>, Json),
            Name = proplists:get_value(<<"name">>, Json),
            {ok, <<Org/binary, "#", App/binary, "_", Name/binary>>};
        _ ->
            ignore
    end.

producer_fun(sync_message_full) ->
    produce_message_full;
producer_fun(sync_roster_full) ->
    produce_roster_full;
producer_fun(sync_privacy_full) ->
    produce_privacy_full.

report_type(sync_message_full, success) ->
    pms;
report_type(sync_message_full, failure) ->
    pmf;
report_type(sync_message_full, ignored) ->
    pmi;
report_type(sync_roster_full, success) ->
    prs;
report_type(sync_roster_full, failure) ->
    prf;
report_type(sync_roster_full, ignored) ->
    pri;
report_type(sync_privacy_full, success) ->
    pps;
report_type(sync_privacy_full, failure) ->
    ppf;
report_type(sync_privacy_full, ignored) ->
    ppi.
