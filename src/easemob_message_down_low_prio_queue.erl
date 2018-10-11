%%%-------------------------------------------------------------------
%%% @author zou <>
%%% @copyright (C) 2016, zou
%%% @doc
%%%
%%% @end
%%% Created : 10 Jul 2016 by zou <>
%%%-------------------------------------------------------------------
-module(easemob_message_down_low_prio_queue).

-behaviour(gen_server).

%% API
-export([start_link/6,
         refresh/1,
         set_read/2,
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
         push_message/4]).

-include("logger.hrl").
-include("jlib.hrl").
-include("pb_msync.hrl").

-define(SERVER, ?MODULE).
-define(SPEED_DEFAULT, 5000).
-define(SLEEP_DEFAULT, 1000).
-define(REFRESH_INTERVAL_DEFAULT, 60000).
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
          func,
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

add_retry(Pid, Fun) ->
    gen_server:cast(Pid, {add_retry, Fun}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([Host, QueueId, Queue, ConsumeType, Opts]) ->
    ?INFO_MSG("start easemob_message_limit_queue with:~p", [Opts]),
    Speed = get_queue_speed(QueueId, Opts),
    SleepTime = proplists:get_value(sleep_time, Opts, ?SLEEP_DEFAULT),
    Read = proplists:get_value(read, Opts, true),
    Shaper = easemob_shaper:new2(Speed),
    RefreshInterval = proplists:get_value(refresh_interval, Opts, ?REFRESH_INTERVAL_DEFAULT),
    erlang:send_after(0, self(), auto_refresh),
    RateList = proplists:get_value(rate_list, Opts, []),
    StatExpireTime = proplists:get_value(statistics_expire_time, Opts, 1000),
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
handle_cast({add_retry, Fun}, State) ->
    Queue = State#state.retry_queue,
    Retry = #retry_info{
               func = Fun,
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
                        {ok, RouteNum, StatKey} ->
                            State1 = statistics_add(State, StatKey, Now),
                            {NewShaper, Pause} = easemob_shaper:update(Shaper, RouteNum),
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
                {ok, RouteNum, StatKey} ->
                    queue_ack_msg(Queue, Partition, Offset),
                    {ok, RouteNum, StatKey};
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

parse_msg(Msg) ->
    try
        Props = jsx:decode(Msg),
        parse_msg1(Props)
    catch
        Class:Exception ->
            ?ERROR_MSG("error to parse msg:~p ~p stacktrace:~p msg:~p",
                       [Class, Exception, erlang:get_stacktrace(), Msg]),
            {error, {Class,Exception}}
    end.

parse_msg1(Props) ->
    From = proplists:get_value(<<"from">>, Props),
    To = proplists:get_value(<<"to">>, Props),
    MsgId = proplists:get_value(<<"msgid">>, Props),
    Slice = proplists:get_value(<<"slice">>, Props),
    SliceSize = proplists:get_value(<<"slice_size">>, Props),
    MemberNum = proplists:get_value(<<"mem_num">>, Props, SliceSize),
    FromJID = msync_msg:parse_jid(From),
    ToJID = msync_msg:parse_jid(To),
    {slice_route, FromJID, ToJID, MsgId, Slice, SliceSize, MemberNum}.

make_slice_route(FromJID, ToJID, Meta, Slice, MemberNum, SliceSizeDict) ->
    SliceSize =
        case dict:find(Slice, SliceSizeDict) of
            error -> 0;
            {ok, Value} -> Value
        end,
    [{<<"from">>, msync_msg:pb_jid_to_binary(FromJID)},
     {<<"to">>, msync_msg:pb_jid_to_binary(ToJID)},
     {<<"msgid">>, integer_to_binary(msync_msg:get_meta_id(Meta))},
     {<<"slice">>, Slice},
     {<<"slice_size">>, SliceSize},
     {<<"mem_num">>, MemberNum}].

push_message(Queue, FromJID, ToJID, Meta) ->
    case process_muc_queue:route_to_down_queue_low_priority(FromJID, FromJID, ToJID, Meta) of
        {error, Reason} ->
            {error, Reason};
        {ok, SliceNum} ->
            case push_slice(Queue, FromJID, ToJID, Meta, SliceNum) of
                ok -> ok;
                {error, Reason} ->
                    {error, Reason}
            end
    end.
push_slice(Queue, FromJID, ToJID, Meta, SliceNum) ->
    try
        GroupId = msync_msg:pb_jid_to_long_username(ToJID),
        MsgId = msync_msg:get_meta_id(Meta),
        SliceSizeList = easemob_muc_redis:read_slice_size_list(GroupId, SliceNum),
        MemberNum = lists:sum([SliceSize||{_,SliceSize}<-SliceSizeList]),
        SliceSizeDict = dict:from_list(SliceSizeList),
        KeyValues =
            [{<<>>,jsx:encode(make_slice_route(FromJID, ToJID, Meta, Slice, MemberNum, SliceSizeDict))}
             ||Slice<-utils:random_list(lists:seq(1,SliceNum))],
        Key = GroupId,
        Res = queue_push_msg(Queue, Key, KeyValues),
        ?INFO_MSG("PushToQueue:Queue=~p,msgid=~p,res=~p",[Queue, MsgId, Res]),
        Res
    catch
        Class:Exception ->
            ?ERROR_MSG("push msg error:"
                       "Class:~p Exception:~p stacktrace:~p",
                       [Class, Exception, erlang:get_stacktrace()]),
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
    Opts = mod_message_limit:message_down_opts(),
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
            Shaper = easemob_shaper:new2(Speed),
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
            Rate1 + (Rate2 - Rate1) * (Len - From) / (To - From);
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

statistics_add(State, skip_stat, _) ->
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
    %%calc the key's speed (cnt per second)
    Speed = Cnt * 1000 / StatExpireTime,
    Rate = calc_rate(RateList, Speed),
    utils:do_with_interval(
      fun() ->
              ?INFO_MSG("get rate: queue_id=~p, key=~p,cnt=~p,speed=~p,rate=~p,len=~p", 
                        [State#state.queue_id, Key, Cnt, Speed, Rate, State#state.stat_queue_length])
      end, statistics_speed, 3000),
    {Rate, Speed}.

statistics_queue_speed(#state{stat_queue_length = StatQueueLength, stat_expire_time=StatExpireTime}) ->
    (StatQueueLength + 1) * 1000 / StatExpireTime.

do_retry(#state{retry_queue=Queue}=State) ->
    {{value, #retry_info{
                func = Func,
                start_time = StartTime,
                cnt = Cnt
               }=Retry}, NewQueue} = queue:out(Queue),
    Now = p1_time_compat:system_time(seconds),
    Res = Func(),
    IsRetryRes = is_retry_res(Res),
    ExpireTime = application:get_env(msync, message_down_retry_expire_seconds, 30),
    MaxRetryTimes = get_max_retry_times(),
    RetryTimes = Cnt + 1,
    case IsRetryRes of
        false ->
            ?INFO_MSG("retry ok:res=~p,retry=~p,",[Res, Retry]),
            {0, State#state{retry_queue = NewQueue}};
        true when abs(Now-StartTime) =< ExpireTime andalso RetryTimes < MaxRetryTimes ->
            NewRetry = Retry#retry_info{
                         cnt = Retry#retry_info.cnt + 1},
            NewQueue1 = queue:in_r(NewRetry, NewQueue),
            ?INFO_MSG("retry continue:res=~p,retry=~p",[Res, Retry]),
            Sleep = application:get_env(msync, message_down_retry_sleep, 100),
            {Sleep, State#state{retry_queue = NewQueue1}};
        true ->
            ?ERROR_MSG("retry fail:res=~p,retry=~p",[Res, Retry]),
            {0, State#state{retry_queue = NewQueue}}
    end.

get_max_retry_times() ->
    application:get_env(msync, message_down_retry_max_times, 0).
%%%===================================================================
%%% Message Queue
%%%===================================================================
queue_new(kafka, Client, Id, _Opts) ->
    {ok, Topic} = easemob_kafka:get_topic_name(Client, Id),
    {kafka, Client, Topic}.

queue_pop_msg({kafka, Client, Topic}) ->
    case easemob_kafka:consume_async(Client, Topic) of
        {ok, undefined} ->
            queue_empty;
        {ok, Msg, Partition, Offset} ->
            {ok, Msg, Partition, Offset};
        {error, Reason} ->
            {error, Reason}
    end.

queue_ack_msg({kafka, Client, Topic}, Partition, Offset) ->
    case easemob_kafka:ack(Client, Topic, Partition, Offset) of
        ok -> ok;
        {error, Reason} ->
            {error, Reason}
    end.

queue_push_msg({kafka, Client, Topic}, Key, Data) ->
    easemob_kafka:produce_sync(Client, Topic, fun partition_by_key/4, Key, Data).

queue_length({kafka, Client, Topic}) ->
    case easemob_kafka:queue_length(Client, Topic) of
        {ok, Len} ->
            Len;
        {error, Reason} ->
            {error, Reason}
    end.

queue_assignments_length({kafka, Client, Topic}) ->
    easemob_kafka:get_assignments_length(Client, Topic).

partition_by_key(_Topic, PartitionsCount, Key, _Value) ->
    {ok, erlang:phash2(Key, PartitionsCount)}.

%%%===================================================================
%%% Consume Functions
%%%===================================================================

consume_message(State, Msg) ->
    case parse_msg(Msg) of
        {error, _Reason} ->
            {ok, 0};
        {slice_route, FromJID, ToJID, MsgId, Slice, SliceSize, MemberNum} ->
            GroupId = msync_msg:pb_jid_to_long_username(ToJID),
            StatKey = {GroupId, Slice},
            {DropRate, Speed} = statistics_drop_rate(State, StatKey),
            case trigger_drop(DropRate, 100) of
                true ->
                    spawn(fun() ->
                                  ?INFO_MSG("drop msg:msgid=~p,drop_rate=~p/100, speed=~p, slice=~p,slice_size=~p, member_num=~p",
                                            [MsgId, DropRate, Speed, Slice, SliceSize, MemberNum])
                          end),
                    {ok, 0, skip_stat};
                false ->
                    QueueTotalLen = queue_assignments_length(State#state.queue),
                    QueueTotalSpeed = statistics_queue_speed(State),
                    {RouteNum, Info} = calc_packet_route_num(Speed, MemberNum, QueueTotalLen, QueueTotalSpeed, SliceSize),
                    F = fun() ->
                                Res =
                                    try
                                        AppKey = ToJID#'JID'.app_key,
                                        case easemob_message_body:read_message(MsgId, AppKey) of
                                            not_found ->
                                                not_found;
                                            error ->
                                                {error, db_error};
                                            Body ->
                                                Meta = msync_msg:decode_meta(Body),
                                                process_muc_queue:route_from_down_queue_by_push(FromJID, FromJID, ToJID, Meta, Slice, SliceSize, RouteNum)
                                        end
                                    catch
                                        Class:Error ->
                                            ?ERROR_MSG("route fail:msgid=~p,error=~p", 
                                                       [MsgId,{Class, Error, erlang:get_stacktrace()}]),
                                            {error, {Class, Error}}
                                    end,
                                case is_good_res(Res) of
                                    true ->
                                        ?INFO_MSG("route ok: queue=~p, msgid=~p, slice:~p, member_num=~p, total_len=~p, total_speed=~p, "
                                                  "info=~p, speed=~p, drop_rate=~p, route_num=~p/~p, res=~p",
                                                  [State#state.queue_id, MsgId, Slice, MemberNum, QueueTotalLen, QueueTotalSpeed,
                                                   Info, Speed, DropRate, RouteNum, SliceSize, Res]);
                                    false ->
                                        ?ERROR_MSG("route error: queue=~p, msgid=~p, slice:~p, member_num=~p, total_len=~p, total_speed=~p, "
                                                   "info=~p, speed=~p, drop_rate=~p, route_num=~p/~p, res=~p, retry=~p",
                                                   [State#state.queue_id, MsgId, Slice, MemberNum, QueueTotalLen, QueueTotalSpeed,
                                                    Info, Speed, DropRate, RouteNum, SliceSize, Res, is_retry_res(Res)])
                                end,
                                Res
                        end,
                    safe_do(F),
                    {ok, RouteNum, StatKey}
            end
    end.

trigger_drop(Rate, Max) ->
    rand:uniform(Max) =< Rate.

calc_packet_route_num(Speed, MemberNum, QueueTotalLen, QueueTotalSpeed, SliceSize) ->
    Opts = mod_message_limit:message_down_opts(),
    MemberNumToDownSpeed = proplists:get_value(member_num_to_down_speed,Opts, []),
    ExpectDelayTime = proplists:get_value(expect_delay_milli_seconds, Opts, 2000),
    MaxFactor = proplists:get_value(max_factor, Opts, 2.0),
    Factor = min(MaxFactor,
                 (QueueTotalSpeed * ExpectDelayTime / 1000) / max(1,QueueTotalLen)),
    MaxSpeed = calc_rate(MemberNumToDownSpeed, MemberNum),
    RouteNumBase = if
                   Speed =< MaxSpeed ->
                       SliceSize;
                   true ->
                       round(SliceSize * MaxSpeed / Speed)
               end,
    RouteNum = min(SliceSize, round(RouteNumBase * Factor)),
    ?DEBUG("SliceSize=~p, UpSpeed=~p, rule=~p, MemberNum=~p, QueueTotalLen=~p, QueueTotalSpeed=~p, Factor=~p, MaxSpeed=~p, RouteNum=~p",
           [SliceSize, Speed, MemberNumToDownSpeed, MemberNum, QueueTotalLen, QueueTotalSpeed, Factor, MaxSpeed, RouteNum]),
    Info = [{factor,Factor},{max_speed,MaxSpeed}],
    {RouteNum, Info}.

safe_do(F)  ->
    Self = self(),
    spawn(fun() ->
                  Res = F(),
                  case get_max_retry_times() > 0 of
                      true ->
                          case is_retry_res(Res) of
                              true ->
                                  ?MODULE:add_retry(Self, F);
                              false ->
                                  skip
                          end;
                      false ->
                          skip
                  end
          end),
    ok.

is_good_res(ok) ->
    true;
is_good_res(_) ->
    false.

is_retry_res(_) ->
    false.
