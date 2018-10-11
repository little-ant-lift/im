%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(process_conference).
-export([handle/7]).

-include("logger.hrl").
-include("pb_conferencebody.hrl").
-include("pb_mucbody.hrl").
-include_lib("gen-erl/rtc_service_types.hrl").
-author("wcy123@gmail.com").

%% for testing purose
-export([test1/0, test2/0, test3/0]).

handle(From, To, ClientId, ServerId, Meta, #'ConferenceBody'{}= ConferenceBody, Response) ->
    ?INFO_MSG("receive conference message meta: ~p~n", [Meta]),
    case msync_route:save(From, To, Meta) of
        ok ->
            handle_after_save(From, To, ClientId, ServerId, Meta, #'ConferenceBody'{}= ConferenceBody, Response);
        {error, Reason} ->
            ?INFO_MSG("muc op db error ~p, meta: ~p~n", [Reason, Meta]),
            return_internal_error(From, To, ClientId, ServerId, Response, <<"database error">>)
    end.

handle_after_save(From, To, ClientId, ServerId, Meta, #'ConferenceBody'{}= ConferenceBody, Response) ->
    case ConferenceBody#'ConferenceBody'.operation of
        'JOIN' ->
            handle_join(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        'INITIATE' ->
            handle_initiate(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        'ACCEPT_INITIATE' ->
            handle_accept_initiate(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        'ANSWER' ->
            handle_answer(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        'TERMINATE' ->
            handle_terminate(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        'REMOVE' ->
            handle_remove(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        'STREAM_CONTROL' ->
            handle_stream_control(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        'MEDIA_REQUEST' ->
            handle_media_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response);
        Unknown ->
            ?INFO_MSG("unknown operation ~p, ConferenceBody = ~p~n", [Unknown, ConferenceBody]),
            return_internal_error(From, To, ClientId, ServerId, Response, <<"Unknown OP">>)
    end.

handle_join(From, _To, ClientId, ServerId, _Meta, ConferenceBody, Response) ->
    To =
        chain:apply(
          #'JID'{
             name = ConferenceBody#'ConferenceBody'.peer_name
            },
          [ { msync_msg, pb_jid_with_default_appkey, [From] },
            { msync_msg, pb_jid_with_default_domain, [From] }
          ]),
    case msync_route:is_online(To) of
        true ->
            case add_content(ConferenceBody#'ConferenceBody'.type, From, To, ConferenceBody) of
                #'ConferenceBody'{} = NewConferenceBody ->
                    %% bound the message
                    NewFrom = system_jid(From),
                    NewTo = From,
                    NewMeta = msync_msg:new_meta(NewFrom, NewTo, 'CONFERENCE', NewConferenceBody),
                    try_save_and_online_route(NewFrom,NewTo,ClientId,ServerId, NewMeta, Response);
                Reason ->
                    return_permission_denied(From, To, ClientId, ServerId, Response, Reason)
            end;
        false ->
            NewConferenceBody = ConferenceBody#'ConferenceBody'{
                                  status = #'ConferenceBody.Status'{
                                              error_code = 404
                                             }
                                 },
            %% bound the message
            NewFrom = system_jid(From),
            NewTo = From,
            NewMeta = msync_msg:new_meta(NewFrom, NewTo, 'CONFERENCE', NewConferenceBody),
            try_save_and_online_route(NewFrom,NewTo,ClientId,ServerId, NewMeta, Response)
    end.
try_save_and_online_route(From,To,ClientId,ServerId,Meta, Response) ->
    case msync_route:save(From, To, Meta) of
        ok ->
            try_online_route_after_save(From,To,ClientId,ServerId,Meta, Response);
        {error, Reason} ->
            ?INFO_MSG("save msg fail ~p, meta: ~p~n", [Reason, Meta] ),
            return_internal_error(From, To, ClientId, ServerId, Response, <<"db error">>)
    end.

try_online_route_after_save(From,To,ClientId,ServerId,Meta, Response) ->
    case msync_route:route_online_only(From, To, Meta) of
        ok ->
            return_ok(From, To, ClientId, ServerId, Response);
        {error, Reason} ->
            ?INFO_MSG("online route msg fail ~p, meta: ~p~n", [Reason, Meta]),
            return_internal_error(From, To, ClientId, ServerId, Response, <<"db error">>)
    end.

add_content(Type, From, To, ConferenceBody) ->
    case create_p2p(Type,From,To) of
        JSONMap when is_map(JSONMap) ->
            ConferenceBody#'ConferenceBody'{ content = jsx:encode(JSONMap) };
        Error when is_binary(Error) ->
            Error
    end.


type2fun('VOICE') ->
    createP2PVoice;
type2fun('VIDEO') ->
    createP2PVideo;
type2fun(undefined) ->
    createP2PVoice.
create_p2p(Type, From, To) ->
    Function = type2fun(Type),
    LUser = msync_msg:pb_jid_to_long_username(From),
    IsMediaUsed = case Function of
                      createP2PVideo ->
                          app_config:is_video_used(LUser);
                      createP2PVoice ->
                          app_config:is_audio_used(LUser)
                      end,
    case IsMediaUsed of
        false ->
            <<"you are limit for media">>;
        true ->
            User1 = msync_msg:pb_jid_to_long_username(From),
            User2 = msync_msg:pb_jid_to_long_username(To),
            case im_thrift:call(conference_service_thrift, Function,
                                [ User1,
                                  "127.0.0.1",
                                  User2,
                                  "127.0.0.1"]) of
                {ok, [ M1, M2 ]} ->
                    JSONMap = #{'relayMS' =>
                               #{ caller => member_to_json(M1),
                                  callee => member_to_json(M2)
                                } },
                    make_turn_servers(Function, JSONMap, From#'JID'.domain);
                OtherWise ->
                    ?INFO_MSG("conference_service_thrift fail, Res = ~p, from: ~p, to: ~p, type: ~p~n", [OtherWise, From, To, Type]),
                    <<"cannot create p2p">>
            end
    end.

member_to_json(Member) ->
    #'Member'{'userId' = UserName,
              'conferenceId' = ConferenceID,
              'serverIp' = ServerIp,
              'rcode' = Rcode,
              'serverPort' = ServerPort,
              'channelId' = ChannelID,
              'vchannelId' = VChannelId} = Member,
    case VChannelId of
        -1 ->
            #{'username' => UserName,
              'conferenceId' => ConferenceID,
              'serverIp' => ServerIp,
              'rcode' => Rcode,
              'serverPort' => ServerPort,
              'channelId' => ChannelID
             };
        _Else ->
            #{'username' => UserName,
              'conferenceId' => ConferenceID,
              'serverIp' => ServerIp,
              'rcode' => Rcode,
              'serverPort' => ServerPort,
              'channelId' => ChannelID,
              'vchannelId' => VChannelId
             }
    end.


make_turn_servers(Function, JSONMap, LServer) ->
    IsMediaTurnServerUsed = case Function of
                                createP2PVideo ->
                                    app_config:is_video_turnserver_used(LServer);
                                createP2PVoice ->
                                    app_config:is_audio_turnserver_used(LServer)
                            end,
    case IsMediaTurnServerUsed of
        true ->
            case make_turn_servers_internal(LServer) of
                [] ->
                    JSONMap;
                TurnServers when is_list(TurnServers) ->
                    maps:put(<<"turnAddrs">>, TurnServers, JSONMap)
            end;
        false ->
            JSONMap
    end.

make_turn_servers_internal(LServer) ->
    Servers = proplists:get_value(LServer, application:get_env(msync, turnServers, []), []),
    [iolist_to_binary(S) || S <- Servers].

handle_initiate(From, To, ClientId, ServerId, Meta, ConferenceBody, Response) ->
    handle_conference_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).
handle_accept_initiate(From, To, ClientId, ServerId, Meta, ConferenceBody, Response) ->
    handle_conference_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).
handle_answer(From, To, ClientId, ServerId, Meta, ConferenceBody, Response) ->
    handle_conference_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).
handle_terminate(From, To, ClientId, ServerId, Meta, ConferenceBody, Response) ->
    handle_conference_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).
handle_stream_control(From, To, ClientId, ServerId, Meta, ConferenceBody, Response) ->
    handle_conference_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).

try_online_route(From, To, ClientId, ServerId, Meta, _ConferenceBody, Response)->
    case msync_route:route_online_only(From, To, Meta) of
        ok ->
            return_ok(From, To, ClientId, ServerId, Response);
        {error, _Reason} ->
            return_internal_error(From, To, ClientId, ServerId, Response, <<"db error">>)
    end.

handle_remove(From, To, ClientId, ServerId, _Meta, ConferenceBody, Response) ->
    case ConferenceBody#'ConferenceBody'.conference_id of
        ConferenceID when is_binary(ConferenceID) ->
            try_remove_p2p(From, To, ClientId, ServerId, _Meta, ConferenceID, Response);
        _Else ->
            return_internal_error(From, To, ClientId, ServerId, Response, <<"no cid">>)
    end.

handle_conference_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response) ->
    try application:get_env(msync, enable_media_request_transfer, false) of
        true ->
            NewConferenceBody = ConferenceBody#'ConferenceBody'{route_flag = 1},
            do_handle_media_request(From, To, ClientId, ServerId,
                                    Meta, NewConferenceBody, Response),
            return_ok(From, To, ClientId, ServerId, Response);
        _ ->
            try_online_route(From, To, ClientId, ServerId, Meta, ConferenceBody, Response)
    catch
        _:_ ->
            try_online_route(From, To, ClientId, ServerId, Meta, ConferenceBody, Response)
    end.

handle_media_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response) ->
    do_handle_media_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response),
    return_ok(From, To, ClientId, ServerId, Response).

do_handle_media_request(From, To, ClientId, ServerId, Meta, #'ConferenceBody'{route_flag = 1} = ConferenceBody, Response) ->
    ?INFO_MSG("processing media request: ~p~n", [Meta]),
    Header = jsx:encode([{from, msync_msg:pb_jid_to_binary(From)},
                         {to, msync_msg:pb_jid_to_binary(To)},
                         {op, ulmsg}]),
    Binary = msync_msg:encode_meta(Meta),
    case im_thrift:call('rtc_service_thrift', 'mediaRequest', [Header, Binary]) of
        {ok, <<"{\"result\":0}">>} ->
            ?INFO_MSG("rtc_service_thrift OK: ~p~n", [ServerId]),
            ok;
        {ok, RetBinary} when is_binary(RetBinary) ->
            ?INFO_MSG("rtc_service_thrift OK: ~p, return ~n", [ServerId, RetBinary]),
            NewMeta = msync_msg:decode_meta(RetBinary),
            NewFrom = msync_msg:get_meta_from(NewMeta),
            NewTo = msync_msg:get_meta_to(NewMeta),
            %try_online_route(NewFrom, NewTo, ClientId, ServerId, NewMeta, ConferenceBody, Response);
            msync_route:route_online_only(NewFrom, NewTo, NewMeta);
        Ret ->
            ?ERROR_MSG("error data: ~p, meta: ~p~n", [Ret, Meta]),
            %return_internal_error(From, To, ClientId, ServerId,
            %                      Response, iolist_to_binary(io_lib:format("~p", [Ret])))
            error
    end;
do_handle_media_request(From, To, ClientId, ServerId, Meta, ConferenceBody, Response)->
    msync_route:route_online_only(From, To, Meta).

try_remove_p2p(From, To, ClientId, ServerId, Meta, ConferenceID, Response) ->
    case maybe_remove_p2p(From, ConferenceID) of
        {ok, _Result} ->
            %% %% bound the message
            %% NewFrom = To,
            %% NewTo = From,
            %% NewConferenceBody = #'ConferenceBody'{
            %%                        operation = 'REMOVE',
            %%                        conference_id = ConferenceID
            %%                       },
            %% NewMeta = msync_msg:new_meta(NewFrom, NewTo, 'CONFERENCE', NewConferenceBody),
            %% msync_route:route_online_only(NewFrom, NewTo, NewMeta),
            return_ok(From, To, ClientId, ServerId, Response);
        Reason ->
            ?INFO_MSG("thrift rpc error ~p, meta: ~p~n",[Reason, Meta]),
            return_internal_error(From, To, ClientId, ServerId, Response, <<"rpc error">>)
    end.


maybe_remove_p2p(From, CId) ->
    LUser = msync_msg:pb_jid_to_long_username(From),
    im_thrift:call(conference_service_thrift, deleteP2P, [ LUser, CId ]).



return_ok(From, To, ClientId, ServerId, Response) ->
    ?DEBUG("send server ack for message client_id=~p server_id=~p from ~p to ~p~n",
           [ClientId,ServerId, msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To)]),
    chain:apply(Response,
                [ {msync_msg,set_status,['OK', undefined]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).

return_permission_denied(From, To, ClientId, ServerId, Response, Reason) ->
    ?DEBUG("send server ack for message client_id=~p server_id=~p from ~p to ~p~n",
           [ClientId,ServerId, msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To)]),
    chain:apply(Response,
                [ {msync_msg,set_status,['PERMISSION_DENIED', Reason]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).

return_internal_error(From, To, ClientId, ServerId, Response, Reason) ->
    ?DEBUG("send server ack for message client_id=~p server_id=~p from ~p to ~p~n",
           [ClientId,ServerId, msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To)]),
    chain:apply(Response,
                [ {msync_msg,set_status,['FAIL', Reason]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).



test1() ->
    From = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                  name = <<"c1">>,domain = <<"easemob.com">>,
                  client_resource = <<"mobile">>},
    To = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c2">>,domain = <<"easemob.com">>,
                client_resource = <<"mobile">>},
    ClientId = 1,
    ServerId = 2,
    ConferenceBody = #'ConferenceBody'{
                        operation = 'JOIN',
                        peer_name = <<"c2">>
                       },
    Meta = {'Meta',576460752303423462,undefined,{'JID',<<"easemob-demo#chatdemoui">>,<<"c1">>,<<"easemob.com">>,undefined},undefined,'CONFERENCE',ConferenceBody},
    Response = {'MSync','MSYNC_V1',undefined,undefined,undefined,undefined,undefined,undefined,'SYNC',undefined,{'CommSyncDL',{'Status','OK',undefined,[]},576460752303423462,163074465100464128,[],undefined,undefined,undefined}},
    handle(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).

test2() ->
    From = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                  name = <<"c1">>,domain = <<"easemob.com">>,
                  client_resource = <<"mobile">>},
    To = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c2">>,domain = <<"easemob.com">>,
                client_resource = <<"mobile">>},
    ClientId = 1,
    ServerId = 2,
    ConferenceBody = #'ConferenceBody'{
                        operation = 'REMOVE',
                        conference_id = <<"123">>
                       },
    Meta = {'Meta',576460752303423462,undefined,{'JID',<<"easemob-demo#chatdemoui">>,<<"c1">>,<<"easemob.com">>,undefined},undefined,'CONFERENCE',ConferenceBody},
    Response = {'MSync','MSYNC_V1',undefined,undefined,undefined,undefined,undefined,undefined,'SYNC',undefined,{'CommSyncDL',{'Status','OK',undefined,[]},576460752303423462,163074465100464128,[],undefined,undefined,undefined}},
    handle(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).

test3()->
    From = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                  name = <<"c1">>,domain = <<"easemob.com">>,
                  client_resource = <<"mobile">>},
    To = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c2">>,domain = <<"easemob.com">>,
                client_resource = <<"mobile">>},
    Content = jsx:encode([{op, 3}, {version, <<"3.1.0">>}, {callVersion, <<"2.0.0">>},
                          {confrId, <<"00010000000123456789012">>},
                          {tsxId, <<"1464060983383-0">>},
                          {tok, <<"8Pw4xd1tJEbktmwS5jdmmHq422Q=">>}]),
    ConferenceBody = #'ConferenceBody'{session_id = <<"1461218722470">>,
                                       operation = 'MEDIA_REQUEST',conference_id = undefined,
                                       type = 'VIDEO',content = Content,network = <<"wifi">>,
                                       version = <<"3.0.0">>,identity = 'CALLER',
                                       duration = undefined,peer_name = undefined,
                                       end_reason = undefined,status = undefined,is_direct = true,
                                       control_type = 'PAUSE_VOICE', route_flag = 1, route_key = <<"001">>},
    Meta = msync_msg:new_meta(From, To, 'CONFERENCE', ConferenceBody),
    ClientId = 1,
    ServerId = 2,
    Response = {'MSync','MSYNC_V1',undefined,undefined,undefined,undefined,undefined,undefined,'SYNC',undefined,{'CommSyncDL',{'Status','OK',undefined,[]},576460752303423462,163074465100464128,[],undefined,undefined,undefined}},
    handle(From, To, ClientId, ServerId, Meta, ConferenceBody, Response).

system_jid(From) ->
    From#'JID'{app_key = undefined, name = undefined, client_resource = undefined}.
