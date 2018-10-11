-module(health_check_utils).
-export([check_collect/2, check_result/2,
         check_node/1, get_timestamp/0,
         get_services/0, get_service_id/0,
         format/2,
         get_pool_workers/1]).

check_collect(Collect, FCheck) ->
    lists:foldl(fun(Table, Acc) ->
                       check_task(Table, Acc, FCheck)
               end, #{status => normal, details =>[]}, Collect).

check_task(Task, #{status := S, details := D} = Result, FCheck) ->
    try FCheck(Task) of
        #{status := normal} -> Result;
        #{status :=S1} = Result1 ->
                  Result#{status => check_result(S1, S), details => [Result1 | D]}
    catch
        C:E ->
            Result1 = #{status => fault, task => health_check_utils:format("~p", [Task]),
                        error => health_check_utils:format("~p:~p", [C, E])},
            Result#{status => fault, details => [Result1 | D]}
    end.

check_result(warn, normal) ->
    warn;
check_result(fault, _) ->
    fault;
check_result(_, Old) ->
    Old.

check_node(Keys) when is_list(Keys) ->
    lists:any(fun(Key) -> application:get_env(msync, Key, false) end, Keys).

format(Format, Args) ->
    iolist_to_binary(io_lib:format(Format, Args)).

get_timestamp() ->
    {M, S, U} = os:timestamp(),
    M * 1000000000 + S * 1000 + U div 1000.

get_services() ->
    Services = [is_msync],
    lists:filtermap(
      fun(S) ->
              case application:get_env(msync, S, false) of
                  true ->
                      BS = atom_to_binary(S, latin1),
                      [<<"is">>, S1] = binary:split(BS, <<"_">>),
                      {true, binary_to_atom(S1, latin1)};
                  false -> false
              end
      end, Services).

get_service_id() ->
    node().

get_pool_workers(Table) ->
    try ets:lookup(Table, pool_size) of
        [{pool_size, PoolSize}] ->
            lists:filtermap(
              fun(N) ->
                      try ets:lookup(Table, N) of
                          [{N, Worker}] when is_pid(Worker)->
                              {true, {Table, N, Worker}};
                          _ -> {true, {Table, N, no_worker}}
                      catch
                          _C:_E ->
                              {true, {Table, N, no_worker}}
                      end
              end, lists:seq(1, PoolSize));
        _ -> [{Table, -1, no_pool}]
    catch
        _C:_E ->
            [{Table, -1, no_pool}]
    end.
