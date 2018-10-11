-module(multi_send).
-compile([export_all]).

test() ->
    {ok, Socket} = gen_tcp:connect("127.0.0.1",5000,[]),
    ListPids = lists:map(
      fun(_) ->
              spawn_link(?MODULE,send,[Socket])
      end, lists:seq(0,200)),
    wait(ListPids),
    gen_tcp:close(Socket).

wait([]) ->
    ok;
wait(Lists) ->
    NewLists =
        lists:filter(
          fun(Pid) ->
                  erlang:is_pid(Pid) andalso erlang:is_process_alive(Pid)
          end, Lists),
    io:format("~p alives~n",[NewLists]),
    timer:sleep(500),
    wait(NewLists).


send(Socket) ->
    gen_tcp:send(Socket, <<"hello\n">>).
