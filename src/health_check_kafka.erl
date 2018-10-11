-module(health_check_kafka).
-export([check/0, services/0]).

services() ->
    [msync].

check() ->
    Envs = [is_msync],
    NeedCheck = health_check_utils:check_node(Envs),
    Type = application:get_env(message_store, kafka_client_module, ekaf),
    check(Type, NeedCheck).

check(ekaf, true) ->
    health_check_utils:check_collect(tasks(), fun do_check/1);
check(brod, true) ->
    #{status => normal};
check(_Client, _NeedCheck) ->
    #{status => ignore}.

do_check({kafka_link, T, W, Pts}) when is_list(Pts) ->
    Pid = health_check_utils:format("~p", [W]),
    case check_worker(W, Pts) of
        true ->
            #{status => normal, type => kafka_link,
              topic => T, worker => Pid};
        false -> #{status => fault, type => kafka_link,
                   topic => T, worker => Pid, error => leader_wrong};
        E -> #{status => fault, type => kafka_link,
               topic => T, worker => Pid, error => E}
    end;
do_check({kafka_link, T, W, E}) ->
    Pid = health_check_utils:format("~p", [W]),
    #{status => fault, type => kafka_link, topic => T,
      worker => Pid, error => E};
do_check({log_kafka, N, W}) when is_pid(W) ->
    do_check({log_kafka, N, W, is_process_alive(W)});
do_check({log_kafka, N, W, true}) ->
    Pid = health_check_utils:format("~p", [W]),
    From = <<"kafka#test_from@easemob.com">>,
    To = <<"kafka#test_to@easemob.com">>,
    MId = <<"kafka_mid1">>,
    Payload = <<"kafka message body 1">>,
    try
        Timestamp = os:timestamp(),
        ChatMsgOutgoing = {chatmsg, Timestamp, <<"chat">>,
                           outgoing, From, To, Payload, MId},
        case timer:tc(gen_server,call,[W, ChatMsgOutgoing]) of
            {Time, ok} ->
                #{status => normal, type => kafka_worker,
                  number => N, worker => Pid, time => Time};
            {Time, {ok, <<"1">>}} ->
                #{status => fault, type => kafka_worker,
                  number => N, worker => Pid, time => Time,
                  error => using_redis};
            {Time, Value} ->
                #{status => fault, number => N, worker => Pid,
                  type => kafka_worker, time => Time, error => Value}
        end
    catch
        Class:Type ->
            Error = health_check_utils:format("~p:~p", [Class, Type]),
            #{status => fault, type => kafka_worker,
              number => N, worker => Pid, error => Error}
    end;
do_check({log_kafka, N, W, false}) ->
    #{status => fault, type => kafka_worker, number => N,
      worker => health_check_utils:format("~p", [W]), error => not_alive};
do_check({log_kafka, _N, E}) ->
    #{status => fault, type => kafka_worker, error => E}.

tasks() ->
    Topics = get_topics(),
    lists:foldl(fun(T, Out) ->
                        Workers = get_workers(T),
                        Out ++ Workers
                end, [], Topics).

get_topics() ->
    LogKafkaOpts = application:get_env(message_store, log_kafka, []),
    lists:filtermap(
      fun({_, T}) when is_binary(T) ->
              {true, T};
         (_) -> false
      end, LogKafkaOpts).

get_partitions(Topic)->
    LogKafkaOpts = application:get_env(message_store, log_kafka, []),
    KafkaHost = proplists:get_value(kafka_broker_host, LogKafkaOpts),
    KafkaPort = proplists:get_value(kafka_broker_port, LogKafkaOpts),
    try
        {ok, Sock} = ekaf_socket:open({KafkaHost, KafkaPort}),
        Req = ekaf_protocol:encode_metadata_request(
                0, "ekaf", [Topic]),
        gen_tcp:send(Sock, Req),
        receive
            {tcp, Sock, Packet = <<_CorrelationId:32, _/binary>>} ->
                ekaf_socket:close(Sock),
                case ekaf_protocol:decode_metadata_response(Packet) of
                    {metadata_response, _CID, _Bs, Ts} ->
                        case lists:keyfind(topic, 1, Ts) of
                            {topic, Topic1, _ECode, Ps}
                              when Topic1 == Topic-> Ps;
                            _ -> []
                        end;
                    _ -> []
                end
        after 5000 ->
                  ekaf_socket:close(Sock),
                  timeout
        end
    catch _C:_E ->
              server_down
    end.

check_worker(W, Ps) ->
    R = gen_fsm:sync_send_event(W, info, 5000),
    R1 = tuple_to_list(R),
    P = case R1 of
            [ekaf_fsm | _] ->
                lists:filtermap(
                  fun({partition, ID, _, Leader, _, _, _, _}) -> {true, {ID, Leader}};
                     (_E) -> false
                  end, R1);
            _ -> disconnected
        end,
    case P of
        [{ID, Leader}] ->
            lists:any(fun({partition, ID1, _, Leader1, _, _, _, _})
                            when {ID1, Leader1} == {ID, Leader}-> true;
                         (_) -> false
                      end, Ps);
        E -> E
    end.

get_workers(Topic) ->
    Workers = health_check_utils:get_pool_workers(log_kafka),
    Partitions = get_partitions(Topic),
    Links = [{kafka_link, Topic, P, Partitions} ||
             [P, N] <- ets:match(pg2l_table, {{member, Topic, '$1'},'$2'}),
             _ <- lists:seq(1, N)],
    Workers ++ Links.
