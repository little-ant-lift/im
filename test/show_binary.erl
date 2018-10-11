-module(show_binary).

-export([init/0, show/2]).

init() ->
      erlang:load_nif("test/show_binary", 0).

show(_,_) ->
      "NIF library not loaded".

show_pid(Pid) ->
    {binary, BI} = erlang:process_info(Pid, binary),
    io:format("~p~n", [BI]),
    lists:foreach(
      fun({Ptr, Size, _} ) ->
              A = show_binary:show(Ptr, Size),
              io:format("~s~n", [A])
      end, BI).
