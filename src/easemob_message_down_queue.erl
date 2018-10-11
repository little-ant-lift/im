%%%-------------------------------------------------------------------
%%% @author zou <>
%%% @copyright (C) 2016, zou
%%% @doc
%%%
%%% @end
%%% Created : 10 Jul 2016 by zou <>
%%%-------------------------------------------------------------------
-module(easemob_message_down_queue).

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
-define(TOPIC_PREFIX_DEFAULT, <<"im:msg:down">>).
-define(REFRESH_INTERVAL_DEFAULT, 60000).
-define(TYPE_CHATROOM, <<"chatroom">>).
-define(TYPE_GROUP, <<"group">>).
-define(ROUTE_TYPE_CURSOR, <<"cursor">>).
-define(ROUTE_TYPE_PUSH, <<"push">>).
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
          retry_queue = queue:new()
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
            refresh_interval = RefreshInterval
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
                         shaper = Shaper, sleep_time=SleepTime} = State) ->
    maybe_print_speed(State),
    {SleepTimeReal,NewState} =
        try
            case Read of
                false ->
                    {SleepTime, State};
                _ ->
                    case do_read_and_consume(State) of
                        queue_empty ->
                            {SleepTime, State};
                        {ok, RouteNum} ->
                            {NewShaper, Pause} = easemob_shaper:update(Shaper, RouteNum),
                            {max(0,Pause), State#state{shaper = NewShaper}};
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
                {ok, RouteNum} ->
                    queue_ack_msg(Queue, Partition, Offset),
                    {ok, RouteNum};
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
    RouteType = proplists:get_value(<<"route_type">>, Props, ?ROUTE_TYPE_CURSOR),
    FromJID = msync_msg:parse_jid(From),
    ToJID = msync_msg:parse_jid(To),
    {slice_route, FromJID, ToJID, MsgId, Slice, SliceSize, RouteType}.

make_slice_route(FromJID, ToJID, Meta, Slice, SliceSizeDict, RouteType) ->
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
     {<<"route_type">>, RouteType}].

push_message(Queue, FromJID, ToJID, Meta) ->
    case decide_route_type(ToJID) of
        {error, Reason} ->
            {error, Reason};
        RouteType ->
            UseCursor = (RouteType == ?ROUTE_TYPE_CURSOR),
            case process_muc_queue:route_to_down_queue(FromJID, FromJID, ToJID, Meta, UseCursor) of
                {error, Reason} ->
                    {error, Reason};
                {ok, SliceNum} ->
                    case push_slice(Queue, FromJID, ToJID, Meta, SliceNum, RouteType) of
                        ok -> ok;
                        {error, Reason} ->
                            {error, Reason}
                    end
            end
    end.

decide_route_type(ToJID) ->
    try
        GroupId = msync_msg:pb_jid_to_long_username(ToJID),
        Type = easemob_muc_redis:read_group_type(GroupId),
        case Type of
            ?TYPE_GROUP ->
                ?ROUTE_TYPE_CURSOR;
            ?TYPE_CHATROOM ->
                SliceSizeList = easemob_muc_redis:read_slice_size_list(GroupId),
                MemberNum = lists:sum([SliceSize||{_,SliceSize}<-SliceSizeList]),
                Opts = mod_message_limit:message_down_opts(),
                MemberNumToPush = proplists:get_value(member_num_to_push, Opts, 10000),
                case MemberNum >= MemberNumToPush of
                    true ->
                        ?ROUTE_TYPE_PUSH;
                    false ->
                        ?ROUTE_TYPE_CURSOR
                end
        end
    catch
        group_not_found ->
            {error, <<"group not found">>};
        db_error ->
            {error, <<"db error">>}
    end.

push_slice(Queue, FromJID, ToJID, Meta, SliceNum, RouteType) ->
    try
        GroupId = msync_msg:pb_jid_to_long_username(ToJID),
        MsgId = msync_msg:get_meta_id(Meta),
        SliceSizeList = easemob_muc_redis:read_slice_size_list(GroupId, SliceNum),
        SliceSizeDict = dict:from_list(SliceSizeList),
        KeyValues =
            [{<<>>,jsx:encode(make_slice_route(FromJID, ToJID, Meta, Slice, SliceSizeDict, RouteType))}
             ||Slice<-utils:random_list(lists:seq(1,SliceNum))],
        Key = GroupId,
        Res = queue_push_msg(Queue, Key, KeyValues),
        ?INFO_MSG("PushToQueue:Queue=~p,msgid=~p,route_type=~p, res=~p",[Queue, MsgId, RouteType, Res]),
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
        do_refresh_speed(State)
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

get_pid_by_queue_name(QueueName) ->
    case whereis(QueueName) of
        Pid when is_pid(Pid) ->
            Pid;
        _ ->
            undefined
    end.

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

consume_message(_State, Msg) ->
    case parse_msg(Msg) of
        {error, _Reason} ->
            {ok, 0};
        {slice_route, FromJID, ToJID, MsgId, Slice, SliceSize, RouteType} ->
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
                                        route_by_type(RouteType, FromJID, ToJID, Meta, Slice, SliceSize)
                                end
                            catch
                                Class:Error ->
                                    {error, {Class, Error}}
                            end,
                        case is_good_res(Res) of
                            true ->
                                ?INFO_MSG("route: msgid=~p, slice:~p, route_type=~p, res=~p",
                                          [MsgId, Slice, RouteType, Res]);
                            false ->
                                ?ERROR_MSG("route error: msgid=~p, slice:~p, route_type=~p, res=~p, retry=~p",
                                           [MsgId, Slice, RouteType, Res, is_retry_res(Res)])
                        end,
                        Res
                end,
            safe_do(F),
            {ok, SliceSize}
    end.

route_by_type(?ROUTE_TYPE_CURSOR, FromJID, ToJID, Meta, Slice, _SliceSize) ->
    process_muc_queue:route_from_down_queue_by_cursor(FromJID, FromJID, ToJID, Meta, Slice);
route_by_type(?ROUTE_TYPE_PUSH, FromJID, ToJID, Meta, Slice, SliceSize) ->
    process_muc_queue:route_from_down_queue_by_push(FromJID, FromJID, ToJID, Meta, Slice, SliceSize, SliceSize).

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

is_retry_res({error, {exit,{timeout,_}}}) ->
    true;
is_retry_res({error, <<"db error">>}) ->
    true;
is_retry_res({error, db_error}) ->
    true;
is_retry_res(_) ->
    false.
