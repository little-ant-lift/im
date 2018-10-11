-module(msync_route).
-export([save_and_route/3,
         route/3,
         route_online_only/3,
         route_meta/3,
         save/3,
         route_to_ejabberd/3,
         get_online_sessions/1,
         maybe_send_notice/4,
         maybe_send_meta/4,
         is_online/1,
         do_route/3,
         get_apns_users/3,
         incr_user_apns/1
        ]).

-include("logger.hrl").
-include("pb_msync.hrl").
-include("xml.hrl").
save_and_route(#'JID'{} = From, #'JID'{} = To, #'Meta'{} = Meta) ->
    case save(From,To, Meta) of
        ok ->
            route(From,To, Meta);
        {error, Reason} -> {error, Reason}
    end.

save(#'JID'{} = From, #'JID'{} = To, #'Meta'{} = Meta) ->
    Packet = msync_msg:encode_meta(Meta),
    ServerId = msync_msg:get_meta_id(Meta),
    FromS = msync_msg:pb_jid_to_binary(From),
    ToS = msync_msg:pb_jid_to_binary(To),
    Payload = msync_msg:get_apns_payload(Meta),
    Type = msync_msg:get_message_type(Meta),
    AppKey = msync_msg:get_with_default(To#'JID'.app_key, From#'JID'.app_key),
    ?DEBUG("save message~n"
              "\tFrom = ~p~n"
              "\tTo = ~p~n"
              "\tPacket = ~p~n",
              [From,To,Meta]),
    easemob_metrics_statistic:inc_counter(outgoing),
    msync_log:on_message_outgoing(From, To, Meta, []),

    Result = message_store:write(FromS, ToS, integer_to_binary(ServerId),
                                 Packet, Payload, Type, AppKey),
    case Result of
        ok ->
            maybe_produce_message_incr_outgoing_body(
              AppKey, FromS, ToS, Packet, integer_to_binary(ServerId), Type);
        _ ->
            ignore
    end,
    Result.

route(#'JID'{} = From, To, #'Meta'{} = Meta) ->
    OfflineFlag =
        case get_online_sessions(To) of
            [] ->
                case app_config:is_offline_msg_limit(
                       msync_msg:pb_jid_to_binary(To)) of
                    true ->
                        false;
                    false ->
                        {true, []}
                end;
            Sessions ->
                {true, Sessions}
        end,

    case OfflineFlag of
        {true, OnlineSessions} ->
            ?DEBUG("route message~n"
                   "\tFrom = ~p~n"
                   "\tTo = ~p~n"
                   "\tPacket = ~p~n",
                   [From, To, Meta]),
            %% {true, _} = {erlang:is_binary(
            %% message_store:read(integer_to_binary(Meta#'Meta'.id))), Meta},
            %% Save to index:unread:Owner:GroupJID and incr unread
            case msync_offline_msg:route_offline(From, To, Meta) of
                %% TODO: it should return ok/{error, Error}, not true/false
                true ->
                    %% send notice if the user is online,
                    %% XMPP user might receive and decode the meta.
                    %% do_route asynchronously, because
                    %% 1. we don't care about the return value.
                    %% 2. it is nonblocking so that the number of workers will
                    %% be increased and system is still responsive.
                    spawn(fun () ->
                                  maybe_route_to_online_sessions(
                                    OnlineSessions, From, To, Meta)
                          end),
                    maybe_produce_message_incr_outgoing_index(
                      From, To, Meta),
                    ok;
                false ->
                    {error, <<"db error">>}
            end;
        false ->
            ok
    end.

route_online_only(#'JID'{} = From, #'JID'{} = To, #'Meta'{} = Meta) ->
    ?DEBUG("route online only message~n"
              "\tFrom = ~p~n"
              "\tTo = ~p~n"
              "\tPacket = ~p~n",
              [From,To,Meta]),
    %% {true, _} = { erlang:is_binary(message_store:read(integer_to_binary(Meta#'Meta'.id))), Meta },
    %% msync_offline_msg:route_offline(From, To, Meta),
    %% send notice if the user is online, XMPP user might receive and decode the meta.
    spawn(fun() -> do_route_online_only(From, To , Meta) end),
    ok.

route_meta(#'JID'{} = From, #'JID'{} = To, Metas) ->
    Sessions = get_online_sessions(To),
    lists:foreach(fun (Session) ->
                          do_route_meta(Session, From, To, Metas)
                  end, Sessions).

do_route_meta(Session, From, To, Metas) ->
    Pid = element(2, element(3, Session)),
    Info = element(6, Session),
    Socket = proplists:get_value(socket, Info),
    case Pid of
        {P, msync} ->
            P ! {route, From, To, Metas, Socket};
        Pid ->
            Pid ! {route, From, To, Metas, Socket}
    end.

%% route packet to ejabberd server.
route_to_ejabberd(#'JID'{} = From, #'JID'{} = To, Packet) ->
    Sessions = get_online_sessions(To),
    lists:foreach(
      fun(S) ->
              route_to_ejabberd(S, From, To, Packet)
      end, Sessions).

do_route(#'JID'{} = From, #'JID'{} = To, #'Meta'{} = Meta) ->
    maybe_route_to_online_sessions(get_online_sessions(To), From,To, Meta).

do_route_online_only(#'JID'{} = From, #'JID'{} = To, #'Meta'{} = Meta) ->
    maybe_route_to_online_sessions_online_only(get_online_sessions(To), From,To, Meta).

%% user is not online, send APNS.
maybe_route_to_online_sessions([], From, To, Meta) ->
    log_offline(From,To,Meta);
maybe_route_to_online_sessions(ListOfSessions, From, To, Meta) ->
    maybe_send_notice(ListOfSessions, From, To, Meta).

maybe_route_to_online_sessions_online_only(ListOfSessions, From, To, Meta) ->
    maybe_send_notice_online_only(ListOfSessions, From, To, Meta).

log_offline(From,To,Meta) ->
    NewFrom = msync_msg:remove_admin_domain(From),
    case is_send_apns(NewFrom, To, Meta) of
        true ->
            ChatType = guess_type(NewFrom, To),
            From1 = msync_msg:pb_jid_to_binary(NewFrom#'JID'{client_resource = undefined}),
            To1 = msync_msg:pb_jid_to_binary(To#'JID'{client_resource = undefined }),
            AppKey = To#'JID'.app_key,
            Id1 = erlang:integer_to_binary(msync_msg:get_meta_id(Meta)),
            Payload = msync_msg:get_apns_payload(Meta),
            ?DEBUG(" easemob_message_log_redis:log_packet_offline:~n"
                   "\tChatType = ~p~n"
                   "\tFrom1 = ~p~n"
                   "\tTo1 = ~p~n"
                   "\tAppKey = ~p~n"
                   "\tId1 = ~p~n"
                   "\tPayload = ~p~n"
                  , [ChatType, From1, To1, AppKey, Id1, Payload]),
            %% for APNS
            case application:get_env(message_store, enable_redis_log_offline,false) of
                true ->
                    easemob_message_log_redis:log_packet_offline(ChatType, From1, To1, AppKey, Id1, Payload);
                _ -> ok
            end,
            %% for kafka, callback REST call
            easemob_metrics_statistic:inc_counter(offline),
            msync_log:on_message_offline(From, To, Meta, []),
            %% comment by zhangchao
            %% add apns when msg type equal to
            %% <<"chat">> | <<"groupchat">>
            case is_apns_without_mute(NewFrom, To) of
                true ->
                    incr_user_apns(To);
                false ->
                    ok
            end;
        false ->
            ignore_apns_offline
    end.

get_apns_users(GroupJID, UserJIDList, Meta) ->
    lists:filter(fun (UserJID) ->
                         is_send_apns(GroupJID, UserJID, Meta)
                 end, UserJIDList).

is_send_apns(_From, _To, Meta) ->
    Type = msync_msg:get_message_type(Meta),
    case Type == <<"chat">> orelse Type == <<"groupchat">> of
        true ->
            MetaPayLoad = Meta#'Meta'.payload,
            case msync_msg_ns_chat:get_payload_type(MetaPayLoad, Type) of
                <<"normal">> ->
                    false;
                _Type ->
                    true
            end;
        false ->
            false
    end.

is_apns_without_mute(From, To) ->
    ToIgnoreResB = msync_msg:pb_jid_to_binary(msync_offline_msg:ignore_resource(To)),
    case app_config:is_apns_mute(ToIgnoreResB) of
        true ->
            GroupJIdDomain = msync_msg:pb_jid_to_binary(From#'JID'{client_resource = undefined }),
            case easemob_apns_mute:is_mute_apns_group(ToIgnoreResB, GroupJIdDomain) of
                true ->
                    false;
                false ->
                    true
            end;
        false ->
            true
    end.

incr_user_apns(To) ->
    ToIgnoreResB = msync_msg:pb_jid_to_binary(msync_offline_msg:ignore_resource(To)),
    easemob_apns:incr_users_apnses([ToIgnoreResB], 1).

maybe_send_notice(ListOfSessions, From, To, Meta) ->
    NewFrom = msync_msg:group_admin_jid(From),
    lists:foreach(
      fun(Session) ->
              Pid = element(2, element(3, Session)),
              Resource = element(3, element(2, Session)),
              ?DEBUG("msync send packet to ejabberd ~p~n\tFrom=~p~n\tTo=~p~n\tPacket=~p~n",
                     [Pid, NewFrom, To, Meta]),
              %% let's pray Pid is alive.
              send_route_signal(Pid, NewFrom,
                                To#'JID'{client_resource = Resource},
                                Meta, Session)
      end, ListOfSessions).

maybe_send_notice_online_only([], _From, To, Meta) ->
    case msync_msg:get_meta_ns(Meta) of
        'CONFERENCE' ->
            ?INFO_MSG("no session of ~p for sending msg: ~p~n", [To, Meta]),
            ok;
        _ ->
            ok
    end;
maybe_send_notice_online_only(ListOfSessions, From, To, Meta)
  when is_list(ListOfSessions) ->
    %% Save to index:unread:Owner:GroupJID and incr unread
    msync_offline_msg:route_offline(From, To, Meta),
    NewFrom = msync_msg:group_admin_jid(From),
    lists:foreach(fun (Session) ->
                          Pid = element(2, element(3, Session)),
                          Resource = element(3, element(2, Session)),
                          ?DEBUG("msync send online only packet to ejabberd "
                                 "~p~n\tFrom=~p~n\tTo=~p~n\tPacket=~p~n",
                                 [Pid, From, To, Meta]),
                          %% let's pray Pid is alive.
                          send_route_signal(
                            Pid, NewFrom, To#'JID'{client_resource = Resource},
                            Meta, Session)
                  end, ListOfSessions),
    maybe_produce_message_incr_outgoing_index(
      From, To, Meta).
%%
%% it is a problem for gpb that a PB message is mapped to a tuple,
%% when ConferenceBody has two more fields, we lose backward
%% compatibility. Here we check a flag it support new version of PB.
convert_conferencebody(Meta = #'Meta'{})->
    LC = tuple_to_list(msync_msg:get_meta_payload(Meta)),
    LC1 = lists:sublist(LC, length(LC) - 2),
    msync_msg:set_meta_payload(Meta, list_to_tuple(LC1)).

need_to_convert_conferencebody_p(Pid) when is_pid(Pid)->
    MyConferenceBody =  msync_msg_ns_conference:decode(<<>>),
    case (catch rpc:call(node(Pid), msync_msg_ns_conference, decode, [<<>>])) of
          ConferenceBody when is_tuple(ConferenceBody),
                              tuple_size(ConferenceBody) == tuple_size(MyConferenceBody) ->
            false;
          ConferenceBody when is_tuple(ConferenceBody),
                              tuple_size(ConferenceBody) < tuple_size(MyConferenceBody) ->
            true;
        _ ->
            false
    end.

maybe_convert_conference(Pid, Meta)->
    case msync_msg:get_meta_ns(Meta) of
        'CONFERENCE' ->
            case need_to_convert_conferencebody_p(Pid) of
                true ->
                    convert_conferencebody(Meta);
                _ ->
                    Meta
            end;
        _ ->
            Meta
    end.

send_route_signal({Pid, msync}, From, To, Meta, Session) ->
    case msync_msg:get_meta_ns(Meta) of
        'CONFERENCE' ->
            ?INFO_MSG("route signal to ~p  msg: ~p~n", [To, Meta]);
        _ ->
            ok
    end,
    Pid ! {route, From, To, msync_msg:get_meta_id(Meta), Session};
send_route_signal({msync_c2s, _Node} = Pid, From, To, Meta, Session) ->
    case msync_msg:get_meta_ns(Meta) of
        'CONFERENCE' ->
            ?INFO_MSG("route signal to ~p  msg: ~p~n", [To, Meta]);
        _ ->
            ok
    end,
    Pid ! {route, From, To, msync_msg:get_meta_id(Meta), Session};
send_route_signal(Pid, From, To, Meta, Session)
  when is_pid(Pid) ->
    Pid ! {route, From, To, maybe_convert_conference(Pid, Meta), Session}.

maybe_send_meta(ListOfSessions, From, To, Meta) ->
    NewFrom = msync_msg:group_admin_jid(From),
    lists:foreach(
      fun(Session) ->
              Pid = element(2, element(3, Session)),
              Resource = element(3, element(2, Session)),
              ?DEBUG("msync send packet to Pid ~p~n\tFrom=~p~n\tTo=~p~n\tPacket=~p~n",
                     [Pid, NewFrom, To, Meta]),
              %% let's pray Pid is alive.
              send_route_meta(Pid, NewFrom,
                                To#'JID'{client_resource = Resource},
                                Meta, Session)
      end, ListOfSessions).

send_route_meta({msync_c2s, _Node} = Pid, From, To, Meta, Session) ->
    case msync_msg:get_meta_ns(Meta) of
        'CONFERENCE' ->
            ?INFO_MSG("route signal to ~p  msg: ~p~n", [To, Meta]);
        _ ->
            ok
    end,
    Pid ! {route, From, To, Meta, Session};
send_route_meta({Pid, msync}, From, To, Meta, Session)
  when is_pid(Pid) ->
    Pid ! {route, From, To, maybe_convert_conference(Pid, Meta), Session};
send_route_meta(Pid, From, To, Meta, Session)
  when is_pid(Pid) ->
    Pid ! {route, From, To, maybe_convert_conference(Pid, Meta), Session}.

%% when resouce is not specified, we try to get all online resources.
get_online_sessions(#'JID'{client_resource = undefined } = JID) ->
    User = msync_msg:pb_jid_to_long_username(JID),
    Server = JID#'JID'.domain,
    case easemob_session:get_all_sessions(User, Server) of
        {error, Reason } ->
            ?WARNING_MSG("cannot get resources: Reason = ~p, JID = ~p~n", [Reason, JID]),
            [];
        {ok, Sessions} when is_list(Sessions) ->
            Sessions
    end;
get_online_sessions(#'JID'{client_resource = Resource } = JID)
  when is_binary(Resource) ->
    User = msync_msg:pb_jid_to_long_username(JID),
    Server = JID#'JID'.domain,
    case easemob_session:get_session(User, Server, Resource) of
        {ok, Session} ->
            [Session];
        {error, _Reason} ->
            []
    end.

route_to_ejabberd(Session, From, To, Packet) ->
    Pid = element(2, element(3,Session)),
    ?DEBUG("send packet to ejabberd Pid = ~p, Node = ~p~n"
           "\tFrom=~p~n"
           "\tTo=~p~n"
           "\tPacket=~p~n",
           [Pid, node(Pid), From,To,Packet]),
    send_to_ejabberd_pid(Pid, Session, From,To,Packet).

%% double checkout to avoid serious potential bug, in case
%% the Pid is not a ejabberd process.
send_to_ejabberd_pid(Pid, Session, From, To, Packet) when not(is_pid(Pid)) ->
    ?ERROR_MSG("logical error ~p~n",[{Pid, Session, From,To,Packet}]);
%% send {route ....}
send_to_ejabberd_pid(Pid, Session, From, To, #xmlel{} = Packet) ->
    Pid ! {route, msync_msg:pb_jid_to_jid(From), msync_msg:pb_jid_to_jid(To), Packet, Session};
%% send {broadcast, ...}
send_to_ejabberd_pid(Pid, _Session, From, To, Packet)
  when is_tuple(Packet) and (element(1,Packet) =:= broadcast) ->
    Pid ! {route, msync_msg:pb_jid_to_jid(From), msync_msg:pb_jid_to_jid(To), Packet}.

%% get_session(JID) ->
%%     User = msync_msg:pb_jid_to_long_username(JID),
%%     Server = JID#'JID'.domain,
%%     Resource = JID#'JID'.client_resource,
%%     case easemob_session:get_session(User, Server, Resource) of
%%         {error, not_found} ->
%%             %% in case dirty session, try to look up local ets table.
%%             get_session_local(JID);
%%         {ok, Session} ->
%%             {ok, Session}
%%     end.
%% get_session_local(JID) ->
%%     Resources = msync_c2s_lib:get_resources(JID),
%%     case Resources of
%%         {error, not_found} ->
%%             [];
%%         _ ->
%%             lists:map(
%%               fun({R,Socket, SID}) ->
%%                       create_legacy_session(JID#'JID'{client_resource = R}, R, SID, Socket)
%%               end, Resources)
%%     end.



is_online(JID) ->
    not(get_online_sessions(JID) == []).


guess_type(From, To) ->
    case (is_conference(From) or is_conference(To)) of
        true -> <<"groupchat">>;
        false -> <<"chat">>
    end.


is_conference(#'JID'{domain = <<"conference", _/binary>>}) ->
    true;
is_conference(_) ->
    false.

maybe_produce_message_incr_outgoing_body(AppKey, From, To, Packet, MID, Type) ->
    case app_config:is_data_sync_enabled(AppKey) of
        true ->
            spawn(fun () ->
                          easemob_sync_incr_lib:produce_message_incr_body(
                            AppKey, From, To, MID, Packet, Type)
                  end);
        false ->
            ignore
    end,
    ok.

maybe_produce_message_incr_outgoing_index(From,
                                          #'JID'{client_resource = ToResource} = To,
                                          Meta) ->
    AppKey = msync_msg:get_with_default(To#'JID'.app_key, From#'JID'.app_key),
    case app_config:is_data_sync_enabled(AppKey) of
        true ->
            spawn(fun () ->
                          NewFrom = msync_msg:group_admin_cid(From#'JID'{client_resource = undefined}),
                          ToBin = msync_msg:pb_jid_to_binary(To#'JID'{client_resource = undefined}),
                          easemob_sync_incr_lib:produce_message_incr_index(
                            NewFrom,
                            [{ToBin, ToResource}],
                            integer_to_binary(msync_msg:get_meta_id(Meta)),
                            msync_msg:get_message_type(Meta))
                  end);
        false ->
            ignore
    end,
    ok.
