-module(msync_log).
-export([on_message_ack/4,
         on_message_outgoing/4,
         on_message_incoming/4,
         on_message_offline/4,
         on_roster_operation/3,
         on_user_statistics/3,
         on_user_login/3,
         on_user_logout/3]).
-include("pb_messagebody.hrl").
-include("logger.hrl").

cast(M, F, A) ->
    rpc:cast(node(), M, F, A),
    ok.

on_message_ack(From, To, Id, Exts) ->
    on_message_transmission(ack, From, To, Id, Exts).

on_message_incoming(From, To, Meta, Exts) ->
    on_message_transmission(incoming, From, To, Meta, Exts).

on_message_outgoing(From, To, Meta, Exts) ->
    on_message_transmission(outgoing, From, To, Meta, Exts).

on_message_offline(From, To, Meta, Exts) ->
    on_message_transmission(offline, From, To, Meta, Exts).

on_message_transmission(Direction, From, To, Meta, Exts) ->
    Type = get_meta_type(Direction, Meta),
    on_message_transmission_1(Direction, From, To, Type, Meta, Exts).

on_message_transmission_1(_Direction, _From, _To, undefined, _Meta, _Exts) ->
    ok;
on_message_transmission_1(Direction, From, To, Type, Meta, Exts) ->
    Payload = get_meta_payload(Direction, Meta),
    Id = get_meta_id(Meta),
    From1 = convert_jid(From, undefined),
    To1 = convert_jid(To, undefined),
    case easemob_log:enabled() of
        true ->
            FromRe = convert_jid(From),
            ToRe = convert_jid(To),
            AppKey = get_appkey(From, To),
            cast(easemob_log, on_packet_transmission,
                 [Direction, AppKey, FromRe, ToRe, Id, Type, Payload, Exts]),
            cast(message_store, log_packet_ssdb,
                 [Direction, From1, To1, Id, Type, Payload]);
        _ ->
            ExtArgs = case proplists:get_value(largeGroup, Exts) of
                          true -> [true];
                          _ -> []
                      end,
            cast(message_store, log_packet_kafka,
                 [Direction, From1, To1, Id, Type, Payload] ++ ExtArgs),
            cast(message_store, log_packet_ssdb,
                 [Direction, From1, To1, Id, Type, Payload])
    end.

on_roster_operation(From, To, Operation) ->
    From1 = convert_jid(From, undefined),
    To1 = convert_jid(To, undefined),
    case easemob_log:enabled() of
        true ->
            AppKey = get_appkey(From, To),
            Resource = From#'JID'.client_resource,
            cast(easemob_log, on_roster_operation,
                 [AppKey, From1, To1, Operation, [{resource, Resource}]]);
        _ ->
            AppKey = get_appkey(From, To),
            Resource = From#'JID'.client_resource,
            cast(easemob_message_log, on_roster_operation,
                 [AppKey, From1, To1, Operation, [{resource, Resource}]])
    end.

on_user_login(User, Reason, ClientInfos) ->
    on_user_status_change(User, online, Reason, ClientInfos).

on_user_logout(User, Reason, ClientInfos) ->
    on_user_status_change(User, offline, Reason, ClientInfos).

on_user_status_change(User, Status, Reason, ClientInfos) ->
    User1 = convert_jid(User),
    case easemob_log:enabled() of
        true ->
            AppKey = get_appkey(User),
            ExtInfos = filter_client_infos(ClientInfos),
            cast(easemob_log, on_user_status_change,
                 [AppKey, User1, Status, Reason, ExtInfos]);
        _ ->
            Presence = case Status of
                           online -> set_presence;
                           _ -> unset_presence
                       end,
            cast(message_store, Presence, [User1, Reason])
    end.

on_user_statistics(_User, _Reason, undefined) ->
    skip;
on_user_statistics(User, Reason, Location) ->
    case catch jsx:decode(Location) of
        StatInfos when is_list(StatInfos) ->
            User1 = convert_jid(User),
            StatInfos1 = [Info||{_,_}=Info<-StatInfos],
            case easemob_log:enabled() of
                true ->
                    cast(easemob_log, on_user_statistics, [User1, Reason, StatInfos1]);
                false ->
                    cast(easemob_message_log, log_user_statistics, [User1, Reason, StatInfos1])
            end;
        Error ->
            ?WARNING_MSG("bad Location:Error=~p, Location=~p", [Error, Location]),
            skip
    end.

get_meta_id(ID) when is_binary(ID) ->
    ID;
get_meta_id(ID) when is_integer(ID) ->
    integer_to_binary(ID);
get_meta_id(Meta) ->
    integer_to_binary(msync_msg:get_meta_id(Meta)).

get_meta_type(ack, _) ->
    <<"">>;
get_meta_type(_, Meta) ->
    msync_msg:get_message_type(Meta).

get_meta_payload(ack, _) ->
    <<"">>;
get_meta_payload(_, Meta) ->
    msync_msg:get_apns_payload(Meta).

%% get_message_body_type(MessageBody) ->
%%     case MessageBody#'MessageBody'.type of
%%         'CHAT' ->
%%             <<"chat">>;
%%         'GROUPCHAT' ->
%%             <<"groupchat">>;
%%         _ ->
%%             undefined
%%     end.

filter_client_infos(ExtInfos) ->
    lists:foldl(
      fun({ip, {IP, Port}}, Acc) when is_tuple(IP) ->
              IP1 = iolist_to_binary([inet:ntoa(IP), ":", integer_to_binary(Port)]),
              [{ip, IP1} | Acc];
         ({client_version, {OS, Version}}, Acc) when is_tuple(Version) ->
              [{os, OS}, {version, easemob_version:to_binary(Version)} | Acc];
         ({device_id, DeviceId}, Acc) ->
              [{device_id, DeviceId} | Acc];
         ({device_type, DeviceType}, Acc) ->
              [{device_type, DeviceType} | Acc];
         (_, Acc) -> Acc
      end, [], ExtInfos).

convert_jid(JIDs, Resource) when is_list(JIDs) ->
    Converter = jid_converter(),
    [Converter(JID#'JID'{client_resource = Resource }) || JID <- JIDs];
convert_jid(JID, Resource) ->
    convert_jid(JID#'JID'{client_resource = Resource }).
convert_jid(JID) ->
    Converter = jid_converter(),
    Converter(JID).
jid_converter() ->
    fun(JID) -> msync_msg:pb_jid_to_binary(JID) end.

get_appkey(From, To) ->
    case get_appkey(From) of
        undefined -> get_appkey(To);
        AppKey -> AppKey
    end.
get_appkey([JID|_]) ->
    get_appkey(JID);
get_appkey(#'JID'{app_key = AppKey}) ->
    AppKey;
get_appkey(_) ->
    undefined.
