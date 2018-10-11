-module(verify_session_consistancy).
-include("pb_msync.hrl").
-export([v1/0, v2/0]).

v1() ->
    {A,B,C} = os:timestamp(),
    Now = {A, B - 600, C},
    lists:foreach(
      fun({Socket, JID, _, _, _Shaper})  ->
              Session = easemob_session:get_session(
                          msync_msg:pb_jid_to_long_username(JID),
                          JID#'JID'.domain,
                          JID#'JID'.client_resource),
              case Session of
                  {ok, {session,_,{_, Pid}, _, _, _}} when is_pid(Pid) ->
                      io:format("Pid = ~p, Node = ~p~n", [Pid, node(Pid)]);
                  {ok, {session,_,{TimeStamp, {msync_c2s, _Node}}, _, _, Info}} ->
                      S2 = proplists:get_value(socket, Info, undefined),
                      if S2 =/= Socket andalso (TimeStamp < Now)->
                              %% sorry, cannot find this socket
                              gen_tcp:close(Socket),
                              io:format("deleting socket ~p for ~p~n", [Socket, msync_msg:pb_jid_to_long_username(JID)]),
                              ets:delete(msync_c2s_tbl_sockets, Socket);
                         true ->
                              io:format("ok socket ~p for ~p~n", [Socket, msync_msg:pb_jid_to_binary(JID)])
                      end;
                  {error, _Reason} ->
                      io:format("Session is not found: ~p~n",[JID])
              end;
         (Other)  ->
              io:format("ignore ~p~n", [Other])
      end,
      ets:tab2list(msync_c2s_tbl_sockets)).

v2() ->
    {A,B,C} = os:timestamp(),
    Now = {A, B - 600, C},
    lists:foreach(
      fun({{AppKey, Name, Domain}, Resource, Socket,{TimeStamp, _} = SID})  ->
              JID = {'JID', AppKey, Name, Domain, Resource},
              case msync_c2s_lib:get_pb_jid_prop(JID,socket)  of
                  {ok, Socket} ->
                      io:format("ok: ~s~n",[msync_msg:pb_jid_to_binary(JID)]),
                      ok;
                  {error, Reason} when TimeStamp < Now ->
                      ets:delete_object(msync_c2s_tbl_pb_jid,
                                        {
                                          {AppKey, Name, Domain},
                                          Resource, %resource
                                          Socket,
                                          SID
                                        }),
                      io:format("deleting socket ~p for ~p ~p ~w ~w~n", [Socket, msync_msg:pb_jid_to_long_username(JID), Reason, TimeStamp, Now]);
                  _ ->
                      io:format("Session is not found: ~s~n",[msync_msg:pb_jid_to_binary(JID)]),
                      ok
              end;
         (Other)  ->
              io:format("ignore ~p~n", [Other]),
              exit(0)
      end,
      ets:tab2list(msync_c2s_tbl_pb_jid)),

    ok.
