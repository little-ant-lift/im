%%%-------------------------------------------------------------------
%%% @author zou <>
%%% @copyright (C) 2016, zou
%%% @doc
%%%
%%% @end
%%% Created :  1 Dec 2016 by zou <>
%%%-------------------------------------------------------------------
-module(mod_message_limit).

%% API
-export([start/2,
         stop/1,
         maybe_queue_message/4,
         maybe_queue_to_down/3,
         init_spec/0,
         limit_app/3,
         change_queue_speed/2,
         unlimit_app/1,
         status/0,
         set_read/1,
         set_read/2,
         get_queue/1,
         get_queue/2,
         get_message_priority/2,
         set_message_priority/3,
         unset_message_priority/2,
         get_module_opts_from_env/0,
         message_down_opts/0
        ]).
-include("logger.hrl").
-include("jlib.hrl").
-include("pb_msync.hrl").
-define(TOPIC_PREFIX_DEFAULT, <<"im:msg:queue:">>).
-define(QUEUE_NUM_DEFAULT, 10).
-define(QUEUE_PROCNAME, easemob_message_limit_queue).
-define(REDIS_KEY_DEFAULT, message_limit_queue).
-define(KAFKA_KEY_DEFAULT, kafka_message_limit_queue).
-define(TYPE_CHATROOM, <<"chatroom">>).
-define(TYPE_GROUP, <<"group">>).

start(Host, Opts) ->
    case application:get_env(msync, enable_message_limit_queue, false) of
        true ->
            easemob_message_limit_queue_sup:start(),
            ChildSpecs = init_spec_opts(Host, Opts),
            easemob_message_limit_queue_sup:start_workers(ChildSpecs);
        false ->
            skip
    end,
    ok.

stop(Host) ->
    Names = get_process_names(Host),
    easemob_message_limit_queue_sup:stop_workers(Names),
    ok.

limit_app(AppKey, Speed, QueueId0) ->
    QueueId = fix_queue_id(QueueId0),
    case app_config:get_app_message_limit_queue_id(AppKey, undefined) of
        undefined ->
            case is_valid_queue_id(QueueId) of
                true ->
                    ?INFO_MSG("limit_app:appkey=~p,speed=~p,queueid=~p",[AppKey, Speed, QueueId]),
                    app_config:set_app_message_limit_queue_id(AppKey, QueueId),
                    app_config:set_message_queue_speed(QueueId, Speed),
                    refresh_queue(QueueId),
                    ok;
                false ->
                    {error, bad_queue_id}
            end;
        _ ->
            {error, app_already_limited}
    end.

fix_queue_id(QueueId) when is_binary(QueueId) ->
    case catch binary_to_integer(QueueId) of
        QueueIdInt when is_integer(QueueIdInt) ->
            fix_queue_id(QueueIdInt);
        _ ->
            QueueId
    end;
fix_queue_id(QueueId) when is_atom(QueueId) ->
    fix_queue_id(list_to_binary(atom_to_list(QueueId)));
fix_queue_id(QueueId) when is_integer(QueueId) ->
    Client = get_queue_client(),
    make_queue_id(Client, QueueId).

is_valid_queue_id(QueueId) ->
    LimitClient = get_queue_client(),
    case parse_queue_id(QueueId) of
        {LimitClient, Index} ->
            QueueNum = get_queue_num(),
            Index >= 1 andalso Index =< QueueNum;
        _ ->
            false
    end.

change_queue_speed(QueueId0, Speed) ->
    QueueId = fix_queue_id(QueueId0),
    ?INFO_MSG("change_queue_speed:QueueId=~p,speed=~p",[QueueId, Speed]),
    app_config:set_message_queue_speed(QueueId, Speed),
    refresh_queue(QueueId),
    ok.

unlimit_app(AppKey) ->
    case app_config:get_app_message_limit_queue_id(AppKey, undefined) of
        undefined ->
            {error, app_not_limited};
        QueueId ->
            ?INFO_MSG("unlimit_app:key=~p",[AppKey]),
            app_config:remove_app_message_limit_queue_id(AppKey),
            refresh_queue(QueueId),
            ok
    end.

status() ->
    AppKeys = app_config:get_app_message_limit_all_appkeys(),
    QueueNum = get_queue_num(),
    QueueIdNotUsed = get_queue_not_used(AppKeys, QueueNum),
    AllQueueIds = message_limit_all_queue_ids() ++ message_down_all_queue_ids(),
    io:format("queueId not used:~p~n", [QueueIdNotUsed]),
    io:format("limit app or group total num:~p~n", [length(AppKeys)]),
    lists:foreach(
      fun(AppKey) ->
              QueueId = app_config:get_app_message_limit_queue_id(AppKey, undefined),
              Speed = easemob_message_limit_queue:get_queue_speed(QueueId),
              Queue = get_queue(QueueId),
              QueueLen = easemob_message_limit_queue:queue_length(Queue),
              io:format("Key:~ts,Speed:~p,QueueId:~ts,QueueLength:~p~n",
                        [AppKey, Speed, QueueId, QueueLen])
      end, AppKeys),
    lists:foreach(
      fun(QueueId) ->
              Queue = get_queue(QueueId),
              Speed = easemob_message_limit_queue:get_queue_speed(QueueId),
              QueueLen = easemob_message_limit_queue:queue_length(Queue),
              io:format("QueueId:~ts,Speed:~p,QueueLength:~p~n",
                        [QueueId, Speed, QueueLen])
      end, AllQueueIds),
    ok.

get_queue_not_used(AppKeys, QueueNum) ->
    ToIndex = fun(QueueId) ->
                case QueueId of
                    undefined -> undefined;
                    _ ->
                        case parse_queue_id(QueueId) of
                            {_Client, Index} ->
                                Index;
                            _ ->
                                undefined
                        end
                end
        end,
    lists:seq(1,QueueNum) -- 
        [ToIndex(app_config:get_app_message_limit_queue_id(AppKey,undefined))
         ||AppKey<-AppKeys].

set_read(IsRead) ->
    QueueNum = get_queue_num(),
    [set_read(IsRead, QueueId)||QueueId<-lists:seq(1,QueueNum)].
set_read(IsRead, QueueId) ->
    Hosts = [<<"easemob.com">>],
    lists:foreach(
      fun(Host) ->
         Name = get_process_name(Host, QueueId),
         easemob_message_limit_queue:set_read(Name, IsRead)
      end,Hosts).

init_spec() ->
    Host = <<"easemob.com">>,
    init_spec(Host).

maybe_queue_message(Host, #'JID'{}=FromJID, #'JID'{}=ToJID, #'Meta'{}=Meta) ->
    case maybe_queue_to_limit(Host, FromJID, ToJID, Meta) of
        queue -> queue;
        {error, Reason} -> {error, Reason};
        skip ->
            case maybe_queue_to_down(FromJID, ToJID, Meta) of
                queue -> queue;
                {error, Reason} -> {error, Reason};
                skip -> skip
            end
    end.

maybe_queue_to_limit(Host, FromJID, ToJID, Meta) ->
    case application:get_env(msync, enable_message_limit_queue, false) of
        true ->
            case message_limit_get_queue_id(FromJID, ToJID, Meta) of
                {QueueId, Priority} ->
                    case queue_message(FromJID, ToJID, Meta, QueueId, Host, Priority) of
                        ok ->
                            queue;
                        {error, _Reason} ->
                            handle_produce_fail(FromJID, ToJID, Meta, Priority)
                    end;
                undefined ->
                    skip
            end;
        false ->
            skip
    end.

maybe_queue_to_down(From, To, #'Meta'{ns=NameSpace}=Meta) ->
    case message_down_queue_enabled() of
        true ->
            GroupId = msync_msg:pb_jid_to_long_username(To),
            IsLargeMuc = easemob_muc_redis:is_large_muc(GroupId),
            case IsLargeMuc andalso NameSpace == 'CHAT' of
                true ->
                    Type = easemob_muc_redis:read_group_type(GroupId),
                    {QueueClient, Index} =
                        case Type of
                            ?TYPE_GROUP ->
                                {kafka_message_down_large_group_normal,1};
                            ?TYPE_CHATROOM ->
                                Priority = get_message_priority(To, Meta),
                                case Priority of
                                    <<"normal">> ->
                                        {kafka_message_down_large_chatroom_normal,1};
                                    <<"low">> ->
                                        {kafka_message_down_large_chatroom_low,1}
                                end
                        end,
                    Queue = get_queue(QueueClient, Index),
                    QueueModule = queue_module(QueueClient),
                    case QueueModule:push_message(Queue, From, To, Meta) of
                        ok -> queue;
                        {error, Reason} ->
                            {error, Reason}
                    end;
                false ->
                    skip
            end;
        false ->
            skip
    end.

handle_produce_fail(_FromJID, ToJID, _Meta, Priority) ->
    ToJIDStr = msync_msg:pb_jid_to_binary(ToJID),
    case {Priority, app_config:get_message_limit_produce_fail_notify(ToJIDStr)} of
        {<<"low">>, false} ->
            queue;
        _ ->
            {error, produce_fail}
    end.

message_limit_get_queue_id(FromJID, ToJID, Meta) ->
    ToStr = msync_msg:pb_jid_to_binary(ToJID),
    case app_config:get_app_message_limit_queue_id(ToStr, undefined) of
        undefined ->
            FromStr = msync_msg:pb_jid_to_binary(FromJID),
            AppKey = app_config:get_user_appkey(FromStr),
            case app_config:get_app_message_limit_queue_id(AppKey, undefined) of
                undefined ->
                    undefined;
                QueueId ->
                    Priority = get_message_priority(ToJID, Meta),
                    {QueueId, Priority}
            end;
        QueueId ->
            Priority = get_message_priority(ToJID, Meta),
            {QueueId, Priority}
    end.

queue_module(kafka_message_down_large_group_normal) ->
    easemob_message_down_queue;
queue_module(kafka_message_down_large_chatroom_normal) ->
    easemob_message_down_queue;
queue_module(kafka_message_down_large_chatroom_low) ->
    easemob_message_down_low_prio_queue;
queue_module(QueueId) ->
    case parse_queue_id(QueueId) of
        undefined ->
            easemob_message_limit_queue;
        {QueueClient, _} ->
            queue_module(QueueClient)
    end.

queue_message(FromJID, ToJID, Meta, QueueId, Host, Priority) ->
    Queue = get_queue(QueueId),
    retry(easemob_message_limit_queue, push_message,
          [Queue, FromJID, ToJID, Meta, Host, Priority], 2, 500).

retry(Module, Fun, Args, Try, SleepTime) when Try > 0 ->
    case apply(Module,Fun,Args) of
        {error, Reason} ->
            ?INFO_MSG("Fail to retry ~p:~p:~p due to ~p",
                         [Module, Fun, Args, Reason]),
            if
                Try - 1 > 0 ->
                    timer:sleep(SleepTime),
                    retry(Module, Fun, Args, Try-1, SleepTime);
                true ->
                    {error, Reason}
            end;
        Res ->
            Res
    end.


get_message_priority(#'JID'{}=JID, Meta) ->
    MsgLevelType = get_msg_level_type(Meta),
    case MsgLevelType of
        undefined -> 
            maybe_fake_message_priority(Meta);
        _ ->
            JIDStr = msync_msg:pb_jid_to_binary(JID),
            case app_config:get_user_appkey(JIDStr) of
                undefined ->
                    message_priority_default();
                AppKey ->
                    get_message_priority(AppKey, MsgLevelType)
            end
    end;
get_message_priority(AppKey, MsgLevelType) ->
    try
        Key = get_message_priority_key(AppKey),
        P1 = ["HGET", Key, MsgLevelType],
        case easemob_redis:q(muc, P1) of
            {ok, undefined} ->
                message_priority_default();
            {ok, Priority} ->
                Priority;
            {error, Reason} ->
                ?DEBUG("get_message_priority error: appkey=~p reason=~p", [AppKey, Reason]),
                message_priority_default()
        end
    catch
        Class:Exception ->
            ?ERROR_MSG("get_message_priority error: appkey=~p"
                       " Class=~p Exception=~p stacktrace=~p",
                       [AppKey, Class, Exception, erlang:get_stacktrace()]),
            message_priority_default()
    end.

% change message priority default to <<"low">> only for debug
message_priority_default() ->
    application:get_env(msync, message_priority_default, <<"normal">>).

% fake_message_priority for debug
maybe_fake_message_priority(Meta) ->
    case application:get_env(msync, fake_message_priority, false) of
        true ->
            try
                MessageBody = msync_msg:get_meta_payload(Meta),
                case msync_msg_ns_chat:to_json_map(MessageBody) of
                    #{<<"bodies">> := [#{<<"msg">> := Msg}|_]} ->
                        case catch binary_to_integer(Msg) of
                            {'EXIT', _} ->
                                message_priority_default();
                            _ ->
                                ?INFO_MSG("fake message priority:msg=~p",[Msg]),
                                <<"low">>
                        end;
                    _ ->
                        message_priority_default()
                end
            catch
                _:_ ->
                    message_priority_default()
            end;
        false ->
            message_priority_default()
    end.

set_message_priority(AppKey, MsgType, Priority) ->
    try
        Key = get_message_priority_key(AppKey),
        P1 = ["HSET", Key, MsgType, Priority],
        case easemob_redis:q(muc, P1) of
            {ok, _} ->
                ok;
            {error, Reason} ->
                ?DEBUG("set_message_priority error: appkey=~p reason=~p", 
                       [AppKey, Reason]),
                {error, Reason}
        end
    catch
        Class:Exception ->
            ?ERROR_MSG("set_message_priority error: appkey = ~p"
                       " Class=~p Exception=~p stacktrace=~p ~n",
                       [AppKey, Class, Exception, erlang:get_stacktrace()]),
            {error, Exception}
    end.
unset_message_priority(AppKey, MsgType) ->
    try
        Key = get_message_priority_key(AppKey),
        P1 = ["HDEL", Key, MsgType],
        case easemob_redis:q(muc, P1) of
            {ok, _} ->
                ok;
            {error, Reason} ->
                ?DEBUG("unset_message_priority error: appkey=~p reason=~p", 
                       [AppKey, Reason]),
                {error, Reason}
        end
    catch
        Class:Exception ->
            ?ERROR_MSG("unset_message_priority error: appkey = ~p"
                       " Class=~p Exception=~p stacktrace=~p ~n",
                       [AppKey, Class, Exception, erlang:get_stacktrace()]),
            {error, Exception}
    end.
%%%===================================================================
%%% Internal functions
%%%===================================================================
get_msg_level_type(Meta) ->
    try
        MessageBody = msync_msg:get_meta_payload(Meta),
        JsonMap = msync_msg_ns_chat:to_json_map(MessageBody),
        case JsonMap of
            #{<<"ext">> := #{ <<"em_msg_level">> := MsgLevelType }} ->
                MsgLevelType;
            _ ->
                undefined
        end
    catch
        _:_ ->
            undefined
    end.
refresh_queue(QueueId) ->
    Hosts = [<<"easemob.com">>],
    lists:foreach(
      fun(Host) ->
         Name = get_process_name(Host, QueueId),
              QueueModule = queue_module(QueueId),
              QueueModule:refresh(Name)
      end,Hosts).

get_process_name(Host, QueueId)  ->
    case parse_queue_id(QueueId) of
        {Client, Index} ->
            get_process_name(Host, Client, Index);
        undefined ->
            undefined
    end.
get_process_name(Host, Client, Index) ->
    Name = gen_mod:get_module_proc(Host, ?QUEUE_PROCNAME),
    list_to_atom(lists:concat([Name, "_", Client, "_", Index])).

get_process_names(Host) ->
    [element(1,Spec) || Spec<-init_spec(Host)].

get_queue_opts() ->
    application:get_env(msync, message_limit_queue, []).

get_queue_num() ->
    QueueOpts = get_queue_opts(),
    get_queue_num(QueueOpts).
get_queue_num(QueueOpts) ->
    proplists:get_value(queue_num, QueueOpts, ?QUEUE_NUM_DEFAULT).

get_queue_type(QueueOpts) ->
    proplists:get_value(queue_type, QueueOpts, redis).

get_queue_client() ->
    QueueOpts = get_queue_opts(),
    get_queue_client(QueueOpts).
get_queue_client(QueueOpts) ->
    QueueType = get_queue_type(QueueOpts),
    case QueueType of
        redis ->
            proplists:get_value(redis_key, QueueOpts, ?REDIS_KEY_DEFAULT);
        kafka ->
            proplists:get_value(kafka_message_limit_queue, QueueOpts, ?KAFKA_KEY_DEFAULT)
    end.

get_queue(QueueId) ->
    {Client, Index} = parse_queue_id(QueueId),
    get_queue(Client, Index).

get_queue(Client, Index) ->
    QueueOpts = get_queue_opts(),
    QueueType = 
        case is_limit_queue(Client) of
            true -> % limit queue get queue type from queue_opts
                get_queue_type(QueueOpts);
            false -> % message queue use kafka
                kafka
        end,
    easemob_message_limit_queue:queue_new(QueueType, Client, Index, QueueOpts).

is_limit_queue(Client) ->
    get_queue_client() == Client.

init_spec(Host) ->
    LimitSpecs =
        case application:get_env(msync, enable_message_limit_queue, false) of
            true ->
                case get_module_opts_from_env() of
                    [] ->
                        [];
                    Opts ->
                        init_spec_opts(Host, Opts)
                end;
            false ->
                []
        end,
    DownSpecs = message_down_spec(Host),
    LimitSpecs ++ DownSpecs.

init_spec_opts(Host, Opts) ->
    message_limit_spec(Host, Opts).

message_limit_spec(Host, Opts) ->
    QueueNum = get_queue_num(),
    Client = get_queue_client(),
    [queue_spec(Client, Index, Host, Opts)
     || Index <- lists:seq(1, QueueNum)].

message_down_spec(Host) ->
    Opts = message_down_opts(),
    case message_down_queue_enabled() of
        true ->
            Clients = message_down_enabled_clients(),
            lists:foldl(
              fun(Client, Acc) ->
                      TopicNum = length(easemob_kafka:get_topic_names(Client)),
                      if
                          TopicNum > 0 ->
                              [queue_spec(Client, Index, Host, Opts)
                               ||Index<-lists:seq(1,TopicNum)] ++ Acc;
                          true ->
                              Acc
                      end
              end, [], Clients);
        false ->
            []
    end.

get_module_opts_from_env() ->
    application:get_env(msync, mod_message_limit, []).

queue_spec(Client, Index, Host, ModOpts) ->
    Queue = get_queue(Client, Index),
    Name = get_process_name(Host, Client, Index),
    QueueId = make_queue_id(Client, Index),
    QueueModule = queue_module(Client),
    {Name,
     {QueueModule, start_link, [Name, Host, QueueId, Queue, consume_type(Client), ModOpts]},
     permanent,
     infinity,
     worker,
     [QueueModule]}.

make_queue_id(Client, Index) ->
    list_to_binary(lists:concat([Client, "_", Index])).

parse_queue_id(QueueId) when is_binary(QueueId) ->
    QueueIdStr = binary_to_list(QueueId),
    Pos = string:rchr(QueueIdStr, $_),
    if
        Pos > 0 ->
            {ClientStr,[_|IndexStr]} = lists:split(Pos-1,QueueIdStr),
            case catch list_to_integer(IndexStr) of
                Integer when is_integer(Integer) ->
                    {list_to_atom(ClientStr),Integer};
                _ ->
                    undefined
            end;
        true ->
            undefined
    end;
parse_queue_id(QueueId) when is_atom(QueueId) ->
    parse_queue_id(list_to_binary(atom_to_list(QueueId)));
parse_queue_id(_) ->
    undefined.

message_down_all_queue_ids() ->
    AllQueueIds =
        lists:foldl(
          fun(Client, Acc) ->
                  Len = length(easemob_kafka:get_topic_names(Client)),
                  if
                      Len > 0 ->
                          [make_queue_id(Client, Idx)||Idx<-lists:seq(1,Len)]++Acc;
                      true ->
                          Acc
                  end
          end,[],message_down_all_clients()),
    lists:sort(AllQueueIds).

message_limit_all_queue_ids() ->
    Client = get_queue_client(),
    QueueNum = get_queue_num(),
    [make_queue_id(Client, Idx)
     ||Idx<-lists:seq(1,QueueNum)].

consume_type(kafka_message_limit_queue) ->
    message_limit;
consume_type(message_limit_queue) ->
    message_limit;
consume_type(_) ->
    message_queue.

get_message_priority_key(AppKey) ->
    <<"im:message_priority:", AppKey/binary>>.

message_down_all_clients() ->
    lists:usort([Client
                 ||Feature<-message_down_features(),
                   Client<-message_down_feature_clients(Feature)]).

message_down_enabled_clients() ->
    lists:usort([Client
                 ||Feature<-message_down_enabled_features(),
                   Client<-message_down_feature_clients(Feature)]).

message_down_queue_enabled() ->
    application:get_env(msync, enable_message_down_queue, false).

message_down_enabled_features() ->
    message_down_features().

message_down_opts() ->
    application:get_env(msync, message_down_queue,[]).

message_down_feature_clients(Feature) ->
    application:get_env(msync, Feature, []).

message_down_features() ->
    application:get_env(msync, message_down_features, []).
