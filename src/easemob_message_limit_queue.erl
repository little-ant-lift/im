%%%-------------------------------------------------------------------
%%% @author zou <>
%%% @copyright (C) 2016, zou
%%% @doc
%%%
%%% @end
%%% Created : 23 Nov 2016 by zou <>
%%%-------------------------------------------------------------------
-module(easemob_message_limit_queue).

-behaviour(gen_server).

%% API
-export([start_link/6,
         refresh/1,
         set_read/2,
         calc_rate/2,
         add_retry/2,
         get_queue_speed/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([queue_new/4,
         queue_push_msg/3,
         queue_pop_msg/1,
         queue_ack_msg/3,
         queue_length/1,
         push_message/6]).

-include("logger.hrl").
-include("jlib.hrl").
-include("pb_msync.hrl").

-define(SERVER, ?MODULE).
-define(SPEED_DEFAULT, 5000).
-define(SLEEP_DEFAULT, 1000).
-define(TOPIC_PREFIX_DEFAULT, <<"im:msg:limit">>).
-define(REFRESH_INTERVAL_DEFAULT, 60000).
-define(UP_MSG_SPEED_KEY, <<"up_msg_speed">>).
-define(TYPE_CHATROOM, <<"chatroom">>).
-define(TYPE_GROUP, <<"group">>).
-record(state, {
          queue_id,
          queue,
          speed,
          shaper,
          sleep_time,
          read,
          host,
          refresh_interval,
          consume_type,
          rate_list = [],
          stat_expire_time = 1000,
          stat_table,
          stat_queue_length = 0,
          stat_queue = queue:new(),
          retry_queue = queue:new()
}).

-record(stat,{
          groupid,
          cnt = 0
}).

-record(retry_info,{
          args,
          cnt = 0,
          start_time = 0
}).

-define(EMPTY_QUEUE, {[],[]}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Name, Host, QueueId, Queue, ConsumeType, Opts) ->
    gen_server:start_link({local, Name}, ?MODULE, [Host, QueueId, Queue, ConsumeType, Opts], []).

refresh(Name) ->
    case get_pid_by_queue_name(Name) of
        Pid when is_pid(Pid) ->
            gen_server:cast(Pid, refresh);
        _ ->
            noproc
    end.

set_read(Name, IsRead) when is_boolean(IsRead) ->
    case get_pid_by_queue_name(Name) of
        Pid when is_pid(Pid) ->
            gen_server:call(Pid, {set_read, IsRead});
        _ ->
            noproc
    end.

get_queue_speed(QueueId) ->
    Opts = mod_message_limit:get_module_opts_from_env(),
    get_queue_speed(QueueId, Opts).
get_queue_speed(QueueId, SpeedDefault) when is_integer(SpeedDefault) ->
    max(1,app_config:get_message_queue_speed(QueueId, SpeedDefault));
get_queue_speed(QueueId, Opts) when is_list(Opts) ->
    SpeedDefault = proplists:get_value(speed, Opts, ?SPEED_DEFAULT),
    get_queue_speed(QueueId, SpeedDefault).

add_retry(Pid, Args) ->
    gen_server:cast(Pid, {add_retry, Args}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([Host, QueueId, Queue, ConsumeType, Opts]) ->
    ?INFO_MSG("start easemob_message_limit_queue with:~p", [Opts]),
    Speed = get_queue_speed(QueueId, Opts),
    SleepTime = proplists:get_value(sleep_time, Opts, ?SLEEP_DEFAULT),
    Read = proplists:get_value(read, Opts, true),
    Shaper = shaper:new2(Speed),
    RefreshInterval = proplists:get_value(refresh_interval, Opts, ?REFRESH_INTERVAL_DEFAULT),
    RateList = proplists:get_value(rate_list, Opts, []),
    StatExpireTime = proplists:get_value(statistics_expire_time, Opts, 1000),
    erlang:send_after(0, self(), auto_refresh),
    case Read of
        true ->
            self() ! loop;
        false ->
            ignore
    end,
    {ok, #state{
            queue_id = QueueId,
            queue = Queue,
            speed = Speed,
            shaper = Shaper,
            sleep_time = SleepTime,
            read = Read,
            host = Host,
            consume_type = ConsumeType,
            refresh_interval = RefreshInterval,
            stat_table = ets:new(none, [{keypos,#stat.groupid},set]),
            rate_list = RateList,
            stat_expire_time = StatExpireTime
           }}.

handle_call({set_read, IsRead}, _From, State) ->
    ?INFO_MSG("set_read:queue_id=~p,is_read=~p", [State#state.queue_id, IsRead]),
    {reply, ok, State#state{read=IsRead}};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(refresh, State) ->
    NewState = do_refresh(State),
    {noreply, NewState};
handle_cast({add_retry, Args}, State) ->
    Queue = State#state.retry_queue,
    Retry = #retry_info{
               args = Args,
               start_time = p1_time_compat:system_time(seconds),
               cnt = 0
              },
    NewQueue = queue:in(Retry, Queue),
    NewState = State#state{retry_queue = NewQueue },
    {noreply, NewState};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(loop, #state{read = Read, retry_queue = ?EMPTY_QUEUE,
                         shaper = Shaper, sleep_time=SleepTime} = StateInit) ->
    maybe_print_speed(StateInit),
    Now = p1_time_compat:system_time(milli_seconds),
    State = statistics_expire(StateInit, Now),
    {SleepTimeReal,NewState} =
        try 
            case Read of
                false ->
                    {SleepTime, State};
                _ ->
                    case do_read_and_consume(State) of
                        queue_empty ->
                            {SleepTime, State};
                        {consumed, GroupId} ->
                            State1 = statistics_add(State, GroupId, Now),
                            {NewShaper, Pause} = shaper:update(Shaper, 1),
                            {max(0,Pause), State1#state{shaper = NewShaper}};
                        {error, _Reason} ->
                            {SleepTime, State}
                    end
            end
        catch
            Class:Exception ->
            ?ERROR_MSG("error to loop:~p ~p stacktrace:~p",
                       [Class, Exception, erlang:get_stacktrace()]),
            {SleepTime, State}
        end,
    if
        SleepTimeReal > 0 ->
            erlang:send_after(SleepTimeReal, self(), loop);
        true ->
            self() ! loop
    end,
    {noreply, NewState};
handle_info(loop, State) ->
    {SleepTime, NewState} = do_retry(State),
    if
        SleepTime > 0 ->
            erlang:send_after(SleepTime, self(), loop);
        true ->
            self() ! loop
    end,
    {noreply, NewState};
handle_info(auto_refresh, State) ->
    erlang:send_after(State#state.refresh_interval, self(), auto_refresh),
    NewState = do_refresh(State),
    {noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
maybe_print_speed(NewState) ->
    utils:do_with_interval(
      fun() ->
              Speed = easemob_shaper:speed(NewState#state.shaper),
              Speed > 1 andalso ?INFO_MSG("Queue:~p,speed:~p/~p",
                                          [NewState#state.queue_id, Speed, NewState#state.speed])
      end, shaper_speed, 3000).
do_read_and_consume(#state{queue=Queue} = State) ->
    case read_message(Queue) of
        queue_empty ->
            queue_empty;
        {error, Reason} ->
            {error, Reason};
        {ok, Msg, Partition, Offset} ->
            case consume_message(State, Msg) of
                {ok, GroupId} ->
                    queue_ack_msg(Queue, Partition, Offset),
                    {consumed, GroupId};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

read_message(Queue) ->
    try
        queue_pop_msg(Queue)
    catch
        Class:Exception ->
            ?ERROR_MSG("error to read msg:~p ~p stacktrace:~p queue:~p",
                       [Class, Exception, erlang:get_stacktrace(), Queue]),
            {error, {Class,Exception}}
    end.

route_message(FromJID, ToJID, Meta, _Domain, Speed, Priority) when is_integer(Speed) ->
    Self = self(),
    spawn(fun() ->
                  Res = do_route_message(FromJID, ToJID, Meta, Speed, Priority),
                  handle_route_message_res(Res, Self, FromJID, ToJID, Meta, Speed, Priority)
          end),
    ok.

do_route_message(FromJID, ToJID, Meta, _Speed, _Priority) ->
    case mod_message_limit:maybe_queue_to_down(FromJID, ToJID, Meta) of
        queue -> ok;
        {error, Reason} -> {error, Reason};
        skip ->
            process_muc_queue:route(FromJID, FromJID, ToJID, Meta)
    end.

handle_route_message_res(ok, _Self, _FromJID, _ToJID, _Meta, _Speed, _Priority) ->
    ok;
handle_route_message_res(Res, Self, FromJID, ToJID, Meta, Speed, Priority) ->
    MsgId = msync_msg:get_meta_id(Meta),
    FromBin = msync_msg:pb_jid_to_binary(FromJID),
    ToBin = msync_msg:pb_jid_to_binary(ToJID),
    IsRetryRes = is_retry_res(Res),
    case IsRetryRes of
        true ->
            easemob_message_limit_queue:add_retry(Self, [FromJID, ToJID, Meta, Speed, Priority]);
        false ->
            skip
    end,
    ?INFO_MSG("error to route:From=~p, To=~p, msg_id=~p, res=~p, is_retry=~p",
              [ FromBin, ToBin, MsgId, Res, IsRetryRes]),
    ok.

is_retry_res({error, <<"db error">>}) ->
    true;
is_retry_res({error, db_error}) ->
    true;
is_retry_res(_) ->
    false.

parse_msg(Msg) ->
    try
        <<Len:16,Para:Len/binary-unit:8,MetaBin/binary>> = Msg,
        MsgData = jsx:decode(Para),
        Priority = proplists:get_value(<<"prio">>, MsgData),
        Meta = msync_msg:decode_meta(MetaBin),
        FromJID = msync_msg:get_meta_from(Meta),
        ToJID = msync_msg:get_meta_to(Meta),
        {packet, FromJID, ToJID, Meta, Priority}
    catch
        Class:Exception ->
            ?ERROR_MSG("error to parse msg:~p ~p stacktrace:~p msg:~p",
                       [Class, Exception, erlang:get_stacktrace(), Msg]),
            {error, {Class,Exception}}
    end.

push_message(Queue, _FromJID, ToJID, Meta, _Domain, Priority) ->
    try
        MetaBin = msync_msg:encode_meta(Meta),
        To = msync_msg:pb_jid_to_binary(ToJID),
        Para = [{<<"prio">>,Priority}],
        ParaBin = jsx:encode(Para),
        ParaBinSize = byte_size(ParaBin),
        Data = <<ParaBinSize:16,ParaBin/binary,MetaBin/binary>>,
        Result = queue_push_msg(Queue, To, Data),
        MsgId = msync_msg:get_meta_id(Meta),
        ?INFO_MSG("queue_push_msg:result=~p,msgid=~p,Queue=~p",
                  [Result, MsgId,Queue]),
        Result
    catch
        Class:Exception ->
            ?ERROR_MSG("push msg error:"
                       "Class:~p Exception:~p stacktrace:~p meta:~p",
                       [Class, Exception, erlang:get_stacktrace(), Meta]),
            {error, {Class, Exception}}
    end.

do_refresh(State) ->
    try
        State1 = do_refresh_speed(State),
        do_refresh_ratelist(State1)
    catch
        Class:Exception ->
            ?ERROR_MSG("do_refresh error:"
                       "Class:~p Exception:~p stacktrace:~p",
                       [Class, Exception, erlang:get_stacktrace()]),
            State
    end.

do_refresh_speed(State) ->
    Speed = get_queue_speed(State#state.queue_id, State#state.speed),
    change_read_speed(State, Speed).

do_refresh_ratelist(State) ->
    Opts = mod_message_limit:get_module_opts_from_env(),
    RateList = proplists:get_value(rate_list, Opts, []),
    if
        RateList /= State#state.rate_list ->
            State#state{rate_list=RateList};
        true ->
            State
    end.
    

change_read_speed(State, Speed) ->
    if
        State#state.speed /= Speed ->
            ?INFO_MSG("change_read_speed:speed=~p",[Speed]),
            Shaper = shaper:new2(Speed),
            State#state{speed = Speed,
                        shaper = Shaper};
        true ->
            State
    end.

calc_rate([{From,Rate1},{To,Rate2}|Rest],Len) ->
    if
        Len < From ->
            0;
        Len < To ->
            Rate1 + (Rate2 - Rate1) * (Len - From) div (To - From);
        true ->
            calc_rate([{To,Rate2}|Rest], Len)
    end;
calc_rate([{From, Rate}], Len) ->
    if
        Len < From ->
            0;
        true ->
            Rate
    end;
calc_rate([], _Len) ->
    0.

get_pid_by_queue_name(QueueName) ->
    case whereis(QueueName) of
        Pid when is_pid(Pid) ->
            Pid;
        _ ->
            undefined
    end.

statistics_expire(#state{stat_queue = Queue,
                                stat_expire_time = ExpireTime,
                                stat_table = Tab} = State, Now) ->
    case queue:out(Queue) of
        {empty, _} ->
            State;
        {{value, {_Key, Time}}, _} when Time + ExpireTime > Now->
            State;
        {{value, {Key, Time}}, QueueNew} ->
            ?DEBUG("expire: key=~p, time=~p, ExpireTime=~p, now=~p", [Key, Time, ExpireTime, Now]),
            case ets:update_counter(Tab, Key, -1, #stat{}) of
                NewValue when NewValue =< 0 ->
                    ?DEBUG("expire remove: key=~p", [Key]),
                    ets:delete(Tab, Key);
                _ ->
                    ok
            end,
            StateNew = State#state{stat_queue = QueueNew,
                                   stat_queue_length = State#state.stat_queue_length - 1},
            statistics_expire(StateNew, Now)
    end.

statistics_add(State, <<>>, _) ->
    State;
statistics_add(#state{stat_queue = Queue,
                      stat_table = Tab} = State, Key, Now) ->
    ?DEBUG("add: key=~p, time=~p", [Key, Now]),
    QueueNew = queue:in({Key, Now}, Queue),
    ets:update_counter(Tab, Key, 1, #stat{}),
    State#state{stat_queue=QueueNew,
                stat_queue_length = State#state.stat_queue_length + 1}.

statistics_get(#state{stat_table = Tab}, Key) ->
    case ets:lookup(Tab, Key) of
        [#stat{cnt = Cnt}] ->
            Cnt;
        [] ->
            0
    end.

statistics_drop_rate(#state{rate_list=RateList, stat_expire_time=StatExpireTime}=State, Key) ->
    Cnt = statistics_get(State, Key)+1,
    Speed = Cnt * 1000 div StatExpireTime,
    Rate = calc_rate(RateList, Speed),
    case rand:uniform(200) of
        1 ->
            ?INFO_MSG("get rate: queue_id=~p, key=~p,cnt=~p,speed=~p,rate=~p,len=~p", [State#state.queue_id, Key, Cnt, Speed, Rate, State#state.stat_queue_length]);
        _ ->
            skip
    end,
    {Rate, Speed}.


do_retry(#state{retry_queue=Queue}=State) ->
    {{value, #retry_info{
                args = [_FromJID, _ToJID, Meta|_] = Args,
                start_time = StartTime
               }=Retry}, NewQueue} = queue:out(Queue),
    Now = p1_time_compat:system_time(seconds),
    MsgId = msync_msg:get_meta_id(Meta),
    Res = (catch erlang:apply(fun do_route_message/5, Args)),
    IsRetryRes = is_retry_res(Res),
    ExpireTime = application:get_env(msync, message_limit_retry_expire_seconds, 60),
    case Res of
        _ when IsRetryRes andalso abs(Now-StartTime) =< ExpireTime ->
            NewRetry = Retry#retry_info{
                         cnt = Retry#retry_info.cnt + 1},
            NewQueue1 = queue:in_r(NewRetry, NewQueue),
            ?INFO_MSG("retry continue:msgid=~p,retry=~p",[MsgId, Retry]),
            Sleep = application:get_env(msync, message_limit_retry_sleep, 500),
            {Sleep, State#state{retry_queue = NewQueue1}};
        ok ->
            ?INFO_MSG("retry ok:msgid=~p,retry=~p,",[MsgId, Retry]),
            {0, State#state{retry_queue = NewQueue}};
        Other ->
            ?ERROR_MSG("retry fail:msgid=~p,retry=~p, other=~p",[MsgId, Retry, Other]),
            {0, State#state{retry_queue = NewQueue}}
    end.

%%%===================================================================
%%% Message Queue
%%%===================================================================
queue_new(redis, Client, Id, Opts) ->
    QueueKey = Client,
    TopicPrefix = proplists:get_value(redis_topic_prefix, Opts, ?TOPIC_PREFIX_DEFAULT),
    IdStr = integer_to_binary(Id),
    Topic = <<TopicPrefix/binary,IdStr/binary>>,
    {redis, QueueKey, Topic};
queue_new(kafka, Client, Id, _Opts) ->
    {ok, Topic} = easemob_kafka:get_topic_name(Client, Id),
    {kafka, Client, Topic}.


queue_pop_msg({redis, QueueKey, Topic}) ->
    case easemob_redis:q(QueueKey, ["LPOP", Topic]) of
        {ok, undefined} ->
            queue_empty;
        {ok, Msg} ->
            {ok, Msg, 0, 0};
        {error, Reason} ->
            {error, Reason}
    end;
queue_pop_msg({kafka, Client, Topic}) ->
    case easemob_kafka:consume_async(Client, Topic) of
        {ok, undefined} ->
            queue_empty;
        {ok, Msg, Partition, Offset} ->
            {ok, Msg, Partition, Offset};
        {error, Reason} ->
            {error, Reason}
    end.

queue_ack_msg({redis, _QueueKey, _Topic}, _, _) ->
    ok;
queue_ack_msg({kafka, Client, Topic}, Partition, Offset) ->
    case easemob_kafka:ack(Client, Topic, Partition, Offset) of
        ok -> ok;
        {error, Reason} ->
            {error, Reason}
    end.

queue_push_msg({redis, QueueKey, Topic}, _Key, Data) ->
    case easemob_redis:q(QueueKey, ["RPUSH", Topic, Data]) of
        {ok, _} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end;
queue_push_msg({kafka, Client, Topic}, Key, Data) ->
    easemob_kafka:produce_sync(Client, Topic, fun partition_by_key/4, Key, Data).


queue_length({redis, QueueKey, Topic}) ->
    case  easemob_redis:q(QueueKey, ["LLEN", Topic]) of
        {ok, Len} ->
            binary_to_integer(Len);
        {error, Reason} ->
            {error, Reason}
    end;
queue_length({kafka, Client, Topic}) ->
    case easemob_kafka:queue_length(Client, Topic) of
        {ok, Len} ->
            Len;
        {error, Reason} ->
            {error, Reason}
    end.


partition_by_key(_Topic, PartitionsCount, Key, _Value) ->
    {ok, erlang:phash2(Key, PartitionsCount)}.

%%%===================================================================
%%% Consume Functions
%%%===================================================================

consume_message(#state{host=Host}=State, Msg) ->
    case parse_msg(Msg) of
        {error, _Reason} ->
            {ok, <<>>};
        {packet, FromJID, ToJID, Meta, <<"low">>} ->
            GroupId = msync_msg:pb_jid_to_long_username(ToJID),
            {DropRate, Speed} = statistics_drop_rate(State, GroupId),
            case trigger_drop(DropRate, 100) of
                true ->
                    MsgId = msync_msg:get_meta_id(Meta),
                    spawn(fun() ->
                                  ?INFO_MSG("drop msg:msgid=~p, groupid=~p,rate=~p/100",
                                            [MsgId, GroupId, DropRate])
                          end),
                    ?DEBUG("drop low message:~p,rate=~p", [{FromJID, ToJID,Meta}, DropRate]),
                    {ok, <<>>};%if drop, do not statistics this
                false ->
                    ?DEBUG("route low message:~p,rate=~p", [{FromJID, ToJID,Meta}, DropRate]),
                    case route_message(FromJID, ToJID, Meta, Host, Speed, <<"low">>) of
                        {error, Reason} ->
                            {error, Reason};
                        ok ->
                            {ok, GroupId}
                    end
            end;
        {packet, FromJID, ToJID, Packet, _} ->
            ?DEBUG("route normal message:~p", [{FromJID, ToJID,Packet}]),
            case route_message(FromJID, ToJID, Packet, Host, 0, <<"normal">>) of
                {error, Reason} ->
                    {error, Reason};
                ok ->
                    {ok,<<>>}
            end
    end.

trigger_drop(Rate, Max) ->
    rand:uniform(Max) =< Rate.
