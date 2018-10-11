-module(health_check_process_queue).
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

check({P, {message_queue_len, Len}}) ->
    check({P, Len});
check({Pid, Len}) when is_number(Len)->
    WarnLen = application:get_env(msync, process_queue_warn_len, 200),
    P = iolist_to_binary(pid_to_list(Pid)),
    if Len < WarnLen ->
           #{status => normal, process => P, queue => Len};
       true ->
           #{status => warn, process => P, queue => Len}
    end;
check({Pid, X}) ->
    P = iolist_to_binary(pid_to_list(Pid)),
    #{status => fault, process => P,
      error => health_check_utils:format("~p", [X])}.

tasks() ->
    Processes = lists:map(
                  fun(P) ->
                          Len = try
                                    erlang:process_info(P, message_queue_len)
                                catch
                                    C:E ->
                                        {C, E}
                                end,
                          {P, Len}
                  end, erlang:processes()),
    L = lists:reverse(lists:keysort(2, Processes)),
    lists:sublist(L, 10).
