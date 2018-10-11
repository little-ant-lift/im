-module(health_check_odbc).
-export([check/0, services/0]).

check() ->
    Envs = [is_msync],
    NeedCheck = health_check_utils:check_node(Envs),
    do_check(NeedCheck).

services() ->
    [msync].

do_check(true) ->
    health_check_utils:check_collect(tasks(), fun check/1);
do_check(_) ->
    #{status => ignore}.

check({T, N, Pid}) when is_pid(Pid)->
    SQL = {sql_query, [<<"select 1;">>]},
    P = iolist_to_binary(pid_to_list(Pid)),
    Threshold = application:get_env(msync, session_ping_threshold, 100000),
    try timer:tc(gen_fsm,sync_send_event,
                 [Pid, {sql_cmd, SQL, os:timestamp()}, 5000]) of
        {Time, {selected,[<<"1">>],[[<<"1">>]]}} when Time < Threshold ->
            #{status => normal, table => T, number => N,
              pid => P, time => Time/1000};
        {Time, {selected,[<<"1">>],[[<<"1">>]]}} ->
            #{status => warn, table => T, number => N,
              pid => P, time => Time/1000};
        X ->
            #{status => fault, table => T, number => N,
              pid => P, error => health_check_utils:format("~p", [X])}
    catch
        C:E ->
            #{status => fault, table => T, number => N, pid => P,
              error => health_check_utils:format("~p:~p",[C, E])}
    end;
check({T, N, E}) ->
    #{status => fault, table => T,
      number => N, error => E}.

tasks() ->
    lists:foldl(fun(N, Out) ->
                        Table = list_to_atom("odbc_shards_" ++ integer_to_list(N)),
                        Workers = health_check_utils:get_pool_workers(Table),
                        Out ++ Workers
                end, [], lists:seq(0, 31)).
