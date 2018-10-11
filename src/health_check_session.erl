-module(health_check_session).
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

check({Type, Node}) ->
    Threshold = application:get_env(msync, odbc_ping_threshold, 100000),
    try timer:tc(rpc, call,[Node, erlang, node, [], 1000]) of
        {Time, Node} when Time < Threshold ->
            #{status => normal, node => Node, type => Type, time => Time/1000};
        {Time, Node} ->
            #{status => warn, node => Node, type => Type, time => Time/1000};
        X ->
            #{status => fault, node => Node, type => Type,
              error => health_check_utils:format("~p", [X])}
    catch
        C:E ->
            #{status => fault, node => Node, type => Type,
              error => health_check_utils:format("~p:~p", [C, E])}
    end.

tasks() ->
    lists:foldl(
      fun({_, all, Nodes}, Out) when is_list(Nodes) ->
              lists:map(fun(Node)->{all, Node} end, Nodes) ++ Out;
         ({_, sub, Nodes}, Out) when is_list(Nodes) ->
              lists:map(fun(Node)->{sub, Node} end, Nodes) ++ Out;
         ({_, muc, Nodes}, Out) when is_list(Nodes) ->
              lists:map(fun(Node)->{muc, Node} end, Nodes) ++ Out;
         (_, Out) -> Out
      end, [], ets:tab2list(store_nodes)).
