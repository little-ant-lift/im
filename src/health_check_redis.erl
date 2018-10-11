-module(health_check_redis).
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

check({T, N, Pid}) when is_pid(Pid) ->
    {A, B, C} = os:timestamp(),
    random:seed(A, B, C),
    P = health_check_utils:format("~p", [Pid]),
    Key = health_check_utils:format("~p", [random:uniform()]),
    Threshold = application:get_env(msync, redis_ping_threshold, 100000),
    try timer:tc(eredis,q,[Pid, [get, Key]]) of
        {Time, {ok, _}} when Time < Threshold->
            #{status => normal, table => T, number => N, pid => P, time => Time/1000};
        {Time, {ok, _}} ->
            #{status => warn, table => T, number => N, pid => P, time => Time/1000};
        X ->
            #{status => fault, table => T, number => N, pid => P,
              error => health_check_utils:format("~p", [X])}
    catch
        C:E ->
            #{status => fault, table => T, number => N, pid => P,
              error => health_check_utils:format("~p:~p",[C, E])}
    end;
check({T, N, E}) ->
    #{status => fault, table => T,
      number => N, error => E}.

tasks() ->
    CheckTable =
    fun(Table) ->
            case ets:info(Table) of
                undefined ->
                    false;
                _ ->
                    true
            end
    end,

    {ok, Tables} = application:get_env(message_store, redis),
    Modules = [ mod_easemob_cache,
                mod_roster_cache,
                mod_session_redis,
                mod_message_log_redis,
                mod_privacy_cache,
                mod_message_cache,
                mod_message_index_cache,
                mod_muc_room_destroy],
    ModTable =
    fun(Mod) ->
            list_to_atom(atom_to_list(Mod) ++ "_easemob.com")
    end,
    EjabberdTables = lists:map(ModTable, Modules),
    lists:foldl(fun(T, Out) ->
                        Workers = health_check_utils:get_pool_workers(T),
                        Out ++ Workers
                end, [],
                Tables ++ lists:filter(CheckTable, EjabberdTables)).
