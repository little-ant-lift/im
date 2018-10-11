-module(health_check_worker_num).
-export([check/0, services/0]).

check() ->
    Envs = [is_msync],
    NeedCheck = health_check_utils:check_node(Envs),
    do_check(NeedCheck).

services() ->
    [msync].

do_check(true) ->
    WarnLen = application:get_env(msync, worker_num_limit, 100),
	case msync_c2s_guard:get_num_of_workers() of
		Num when is_integer(Num), Num < WarnLen ->
            #{status => normal, worker_num => Num};
        Num when is_integer(Num) ->
            #{status => warn, worker_num => Num};
        X -> #{status => fault, error => health_check_utils:format("~p", [X])}
	end;
do_check(false) ->
    #{status => ignore}.
