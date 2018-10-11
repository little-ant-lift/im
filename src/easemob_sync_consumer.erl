%%%-------------------------------------------------------------------
%%% @author clanchun <clanchun@gmail.com>
%%% @copyright (C) 2017, clanchun
%%% @doc
%%%
%%% @end
%%% Created : 13 Sep 2017 by clanchun <clanchun@gmail.com>
%%%-------------------------------------------------------------------
-module(easemob_sync_consumer).

-behaviour(brod_group_subscriber).
-behaviour(gen_server).

%% API
-export([start_link/8]).

%% behabviour callbacks
-export([init/2,
         handle_message/4
        ]).

-include_lib("brod/include/brod.hrl").
-include("logger.hrl").

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          client_id,
          endpoint,
          group_id,
          topic,
          group_config,
          consumer_config,
          callback_module,
          subscriber,
          status %% stopped | started
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
start_link(HandlerName, EndPoint, ClientID, GroupID, Topic,
           GroupConfig, ConsumerConfig, CallBackModule) ->
    gen_server:start_link({local, HandlerName}, ?MODULE,
                         [EndPoint, ClientID, GroupID, Topic,
                          GroupConfig, ConsumerConfig, CallBackModule],
                          []).

%%%===================================================================
%%% brod_group_subscriber callbacks
%%%===================================================================

init(_GroupID, HandlerName) ->
    {ok, HandlerName}.

%% @doc Handle one message (not message-set).
handle_message(Topic, Partition,
               #kafka_message{offset = Offset, value = Value},
               HandlerName) ->
    gen_server:cast(HandlerName, {kafka_message, Topic, Partition, Offset, Value}),
    {ok, HandlerName}.

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
init([EndPoint, ClientID, GroupID, Topic, GroupConfig,
      ConsumerConfig, CallBackModule]) ->
    process_flag(trap_exit, true),
    ok = brod:start_client(EndPoint, ClientID, []),
    {ok, #state{endpoint = EndPoint,
                client_id = ClientID,
                group_id = GroupID,
                topic = Topic,
                group_config = GroupConfig,
                consumer_config = ConsumerConfig,
                callback_module = CallBackModule
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
handle_cast({kafka_message, Topic, Partition, Offset, Value},
            #state{client_id = ClientID, subscriber = Subscriber} = State) ->
    handle_message(ClientID, Subscriber, Topic, Partition, Offset, Value),
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
handle_info(<<"start">>, #state{
                            client_id = ClientID,
                            group_id = GroupID,
                            topic = Topic,
                            group_config = GroupConfig,
                            consumer_config = ConsumerConfig,
                            callback_module = CallbackModule} = State) ->
    {ok, Subscriber} = brod:start_link_group_subscriber(
                         ClientID, GroupID, [Topic], GroupConfig,
                         ConsumerConfig, CallbackModule, self()),
    ?INFO_MSG("consumer ~p started~n", [ClientID]),
    {noreply, State#state{subscriber = Subscriber, status = started}};

handle_info(<<"stop">>, #state{client_id = ClientID,
                               subscriber = Subscriber} = State) ->
    brod_group_subscriber:stop(Subscriber),
    ?INFO_MSG("consumer ~p stopped~n", [ClientID]),
    {noreply, State#state{subscriber = undefined, status = stopped}};

handle_info({'EXIT', _SubscriberPid, normal}, State) ->
    {noreply, State};

handle_info(Msg, State) ->
    ?INFO_MSG("consumer unknown msg: ~p, state: ~p~n", [Msg, State]),
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

handle_message(ClientID, Subscriber, Topic, Partition, Offset, Value) ->
    try
        Data = binary_to_term(Value),
        ConsumerFun = consumer_fun(ClientID),
        ?INFO_MSG("consuming from topic: ~p, data: ~p~n", [Topic, Data]),
        easemob_sync_lib:ConsumerFun(Data),
        case report_type(ClientID, success) of
            none ->
                ignore;
            ReportType ->
                easemob_sync_manager:report(ReportType, 1)
        end
    catch
        Class: Reason ->
            case report_type(ClientID, failure) of
                none ->
                    ignore;
                RT ->
                    easemob_sync_manager:report(RT, 1)
            end,
            ?ERROR_MSG("consume data error, topic: ~p, value: ~p, "
                       "class: ~p, reason: ~p, stack: ~p~n",
                       [Topic, Value, Class, Reason, erlang:get_stacktrace()])
    end,
    brod_group_subscriber:ack(Subscriber, Topic, Partition, Offset).

consumer_fun(sync_message_full_consumer_client) ->
    consume_message_full;
consumer_fun(sync_message_incr_consumer_client) ->
    consume_message_incr;
consumer_fun(sync_roster_full_consumer_client) ->
    consume_roster_full;
consumer_fun(sync_roster_incr_consumer_client) ->
    consume_roster_incr;
consumer_fun(sync_privacy_full_consumer_client) ->
    consume_privacy_full;
consumer_fun(sync_privacy_incr_consumer_client) ->
    consume_privacy_incr.

report_type(sync_message_full_consumer_client, success) ->
    cms;
report_type(sync_message_full_consumer_client, failure) ->
    cmf;
report_type(sync_roster_full_consumer_client, success) ->
    crs;
report_type(sync_roster_full_consumer_client, failure) ->
    crf;
report_type(sync_privacy_full_consumer_client, success) ->
    cps;
report_type(sync_privacy_full_consumer_client, failure) ->
    cpf;
report_type(_, _) ->
    none.

