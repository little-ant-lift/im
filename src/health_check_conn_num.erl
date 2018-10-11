-module(health_check_conn_num).
-export([check/0, services/0]).

check() ->
    Envs = [is_msync],
    NeedCheck = health_check_utils:check_node(Envs),
    do_check(NeedCheck).

services() ->
    [msync].

do_check(true) ->
    WarnLen = application:get_env(msync, conn_num_limit, 100000),
	case ets:info(msync_c2s_tbl_sockets, size) of
		Num when is_integer(Num), Num < WarnLen ->
            #{status => normal, conn_num => Num};
        Num when is_integer(Num) ->
            #{status => warn, conn_num => Num};
        X -> #{status => fault, error => health_check_utils:format("~p", [X])}
	end;
do_check(false) ->
    #{status => ignore}.
