-module(health_check_lager).
-export([check/0, services/0]).

check() ->
    Envs = [is_msync],
    NeedCheck = health_check_utils:check_node(Envs),
    do_check(NeedCheck).

services() ->
    [msync].

do_check(true) ->
    WarnLen = application:get_env(msync, process_queue_warn_len, 200),
    try process_info(whereis(lager_event), message_queue_len) of
        {message_queue_len, Len} when Len < WarnLen ->
                #{status => normal, queue_lenth => Len};
        {message_queue_len, Len} ->
                #{status => warn, queue_lenth => Len};
        X -> #{status => fault, error => health_check_utils:format("~p", [X])}
    catch
        C:E ->
            #{status => fault, error => health_check_utils:format("~p:~p", [C, E])}
    end;
do_check(false) ->
    #{status => ignore}.
