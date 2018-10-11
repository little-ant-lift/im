-module(process_stat_meta).
-include("logger.hrl").
-include("pb_statisticsbody.hrl").
-export([process/2]).
process(JID, #'StatisticsBody'{
           operation = Operation,
           os = OS,
           version = Version,
           network = Network,
           im_time = IM,
           chat_time = Chat,
           location = Location
          }) ->
    {IP, Version2} =
        case msync_c2s_lib:get_pb_jid_prop(JID,socket) of
        {ok, Socket} ->
                case Version of
                    undefined ->
                        ok;
                    _ ->
                        msync_c2s_lib:set_socket_prop(Socket, version, Version)
                end,
                IP0 = case inet:peername(Socket) of
                          {ok, {Address, Port}} ->
                              {Address, Port};
                          _ ->
                              {{0,0,0,0},0}
                      end,
                Version1 =
                    case msync_c2s_lib:get_socket_prop(Socket, version) of
                        {ok, Version0} ->
                            Version0;
                        _ ->
                            undefined
                    end,
                {IP0, Version1};
            _ ->
                {{{0,0,0,0},0}, undefined}
        end,
    msync_log:on_user_statistics(JID, Operation, Location),
    ?INFO_MSG("[login] ip:~p user:~p im_login_time:~p chat_login_time:~p client_version:~p operation:~p network:~p, location:~p~n",
              [IP,
               msync_msg:pb_jid_to_binary(JID),
               integer_to_binary(IM),
               integer_to_binary(Chat),
               {OS, Version2},
               Operation,
               Network, Location]).

    %% ?INFO_MSG("stat: JID = ~p,"
    %%           "operation = ~p,"
    %%           "os = ~p,"
    %%           "version = ~p,"
    %%           "network = ~p,"
    %%           "im_time = ~p,"
    %%           "chat_time = ~p~n",
    %%           [msync_msg:pb_jid_to_binary(JID), Operation, OS, Version, Network, IM, Chat]).
