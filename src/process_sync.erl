-module(process_sync).
-export([handle/3]).
-include("logger.hrl").

-include("pb_msync.hrl").

handle(#'MSync'{
          payload = #'CommSyncUL'{
                       is_roam = true} = CommSyncUL},
       Response, JID) ->
    process_roam:handle(CommSyncUL, Response, JID);
handle(#'MSync'{
          payload = #'CommSyncUL'{
                       meta = #'Meta'{
                                 id = ClientId,
                                 ns = 'STATISTIC',
                                 payload = Stat
                                }}} = _RequestMsg,
       Response, JID) ->
    ServerId = msync_uuid:generate_msg_id(),
    ReceiveTimeStamp = time_compat:erlang_system_time(milli_seconds),
    process_stat_meta:process(JID, Stat),
    chain:apply(Response,
                [ {msync_msg,set_status,['OK', undefined]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]},
                  {fun set_sync_timestamp/2, [ReceiveTimeStamp]}
                ]);
handle(#'MSync'{
          payload = undefined
         } = RequestMsg, Response, _JID) ->
    ?ERROR_MSG("missing parameter: Msg = ~p~n",[RequestMsg]),
    msync_msg:set_status(Response,'MISSING_PARAMETER', <<"no meta body">>);
handle(#'MSync'{
          payload = #'CommSyncUL'{
                       meta = #'Meta'{
                                 id = undefined
                                }}} = RequestMsg,
       Response, _JID) ->
    ?ERROR_MSG("MISSING_PARAMETER: no meta id. Msg = ~p~n",[RequestMsg]),
    msync_msg:set_status(Response,'MISSING_PARAMETER', <<"no meta id">>);
handle(#'MSync'{
          payload = #'CommSyncUL'{
                       meta = #'Meta'{
                                 to = undefined
                                }}} = RequestMsg,
       Response, _JID) ->
    ?ERROR_MSG("MISSING_PARAMETER: no meta to. Msg = ~p~n",[RequestMsg]),
    msync_msg:set_status(Response,'MISSING_PARAMETER', <<"no meta to">>);
handle(Request, Response, JID) ->
    ReceiveTimeStamp = time_compat:erlang_system_time(milli_seconds),
    Response1 = handle_sync(Request, Response, JID),
    Response2 = set_sync_timestamp(Response1, ReceiveTimeStamp),
    Response2.

handle_sync(#'MSync'{
               payload = #'CommSyncUL'{
                            meta = Meta,
                            key = Key,
                            queue = Queue
                           }}, Response, JID) ->
    %% handle_sync_meta handle UL messages
    %% and handle_sync_meta handle DL messages
    Response1 = handle_sync_meta(Meta, Response,JID),
    ErrorCode = msync_msg:get_status_error_code(Response1),
    case ErrorCode of
        'OK' ->
            %% if process meta is OK, then, i.e. continue to process
            %% sync queue request
            Response2 = handle_sync_queue(Key, Queue, Response1,JID),
            Response2;
        undefined ->
            %% the request is not processed, i.e. no Meta in UL SYNC,
            %% process sync queue request only
            Response2 = handle_sync_queue(Key, Queue, Response1,JID),
            Response2;
        _ ->
            %% otherwise reply the response as early as possible.
            Response1
    end.

handle_sync_meta(undefined, Response, _JID) ->
    Response;
handle_sync_meta(#'Meta'{
                    id = ClientId,
                    from = From,
                    to = #'JID'{} = To
                   } = Meta, Response, JID) ->
    NewFrom =
        chain:apply(
          JID,
          [{ msync_msg, get_with_default, [From]},
           { msync_msg, pb_jid_with_default_appkey, [From]},
           { msync_msg, pb_jid_with_default_domain, [From]} ]
         ),
    NewTo1 =
        chain:apply(
          To,
          [
           { msync_msg, pb_jid_with_default_appkey, [NewFrom]},
           { msync_msg, pb_jid_with_default_domain, [NewFrom]} ]),
    NewTo =
        case NewTo1#'JID'.name  of
            undefined ->
                %% this is the system queue, so that we remove AppKey and resource.
                NewTo1#'JID'{
                  app_key = undefined,
                  client_resource = undefined
                 };
            _ -> NewTo1
        end,
    NewMeta =
        chain:apply(
          Meta,
          [
           %% server will generate a new ID and replace the old one
           {msync_msg, allocate_meta_id, []},
           %% server will generate a timestamp, whatever.
           {msync_msg, generate_timestamp, []},
           {msync_msg, set_meta_from, [NewFrom]},
           {msync_msg, set_meta_to, [NewTo]}
          ]),
    %% ?DEBUG("~s:~p: [~p] -- ~p~n",[?FILE, ?LINE, ?MODULE, {NewFrom, NewTo, NewMeta, Meta}]),
    ServerId = msync_msg:get_meta_id(NewMeta),
    case To#'JID'.name of
        undefined ->
            handle_sync_meta_system(ClientId, ServerId, NewFrom, NewTo, NewMeta, Response, JID);
        _ ->
            NewResponse = handle_sync_meta_1(ClientId, ServerId, NewFrom,
                                             NewTo, NewMeta, Response, JID),
            case msync_msg:get_status_error_code(NewResponse) of
                'OK' ->
                    LongFrom = msync_msg:pb_jid_to_long_username(NewFrom),
                    case app_config:is_unique_msg_enabled(LongFrom) of
                      true ->
                          easemob_message_idcache:set_id(LongFrom, ClientId, ServerId);
                      false ->
                          ok
                    end;
                _ ->
                    ignore
            end,
            NewResponse
    end.
handle_sync_meta_1(ClientId, ServerId, From, To, Meta, Response, JID) ->
    case ul_packet_filter:check(ClientId, From,To,Meta) of
        ok ->
            handle_sync_meta_2(ClientId, ServerId, From, To, Meta, Response, JID);
        {ok, NewMeta} ->
            handle_sync_meta_2(ClientId, ServerId, From, To, NewMeta, Response, JID);
        {error, {ReturnCode, Description}} ->
            chain:apply(Response,
                        [ {msync_msg,set_status,[ReturnCode, Description]},
                          {msync_msg,set_meta_ack_id, [ClientId, ServerId]}])
    end.
handle_sync_meta_2(ClientId, ServerId, From, To, Meta, Response, JID) ->
    case is_conference(To#'JID'.domain) of
        true ->
            case easemob_traffic_control:get_ticket(traffic_control_group_chat) of
                ok ->
                    handle_sync_meta_conference(ClientId, ServerId, From, To, Meta, Response, JID);
                {error, _Reason} ->
                    handle_sync_meta_traffic_control(groupchat, ClientId, ServerId, From, To, Meta, Response, JID)
            end;
        false ->
            case easemob_traffic_control:get_ticket(traffic_control_chat) of
                ok ->
                    handle_sync_meta_normal(ClientId, ServerId, From, To, Meta, Response, JID);
                {error, _Reason} ->
                    handle_sync_meta_traffic_control(chat, ClientId, ServerId, From, To, Meta, Response, JID)
            end
    end.

handle_sync_meta_traffic_control(Type, ClientId, ServerId, _From, _To, _Meta, Response, JID) ->
    ?WARNING_MSG("~p traffic control happened: JID:~p",[Type, JID]),
    chain:apply(Response,
                [ {msync_msg,set_status,['FAIL', <<"traffic control happened, retry later">>]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).

handle_sync_meta_normal(ClientId, ServerId, From, To, Meta, Response, JID) ->
    ?DEBUG("income new message ns=~p, client_id=~p server_id=~p from ~p to ~p~n",
           [msync_msg:get_meta_ns(Meta), ClientId,ServerId, msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To)]),
    IsAllowed = not(msync_privacy_cache:member(To, From)),
    case IsAllowed of
        false ->
            handle_sync_meta_normal_perminsion_denied(ClientId, ServerId, From, To, Meta, Response, JID);
        true ->
            handle_sync_meta_normal_perminsion_ok(ClientId, ServerId, From, To, Meta, Response, JID)
    end.
handle_sync_meta_normal_perminsion_denied(ClientId, ServerId, From, To, _Meta, Response, _JID) ->
    %% sorry you are not allowed to send message to the other
    ?DEBUG("blocking meta,  client_id=~p server_id=~p from ~p to ~p~n",
           [ClientId,ServerId, msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To)]),
    chain:apply(Response,
                [ {msync_msg,set_status,['FAIL', <<"blocked">>]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).
handle_sync_meta_normal_perminsion_ok(ClientId, ServerId, From, To, Meta, Response, JID) ->
    case msync_msg:get_meta_ns(Meta) of
        'CHAT' ->
            handle_sync_meta_normal_chat(ClientId, ServerId, From, To, Meta, Response, JID);
        'CONFERENCE' ->
            handle_sync_meta_normal_conference(ClientId, ServerId, From, To, Meta, Response, JID);
        UnknownNS ->
            ?DEBUG("unknown namespace ~p Meta = ~p~n", [UnknownNS, Meta])
    end.

handle_sync_meta_normal_chat(ClientId, ServerId, From, To, Meta, Response, JID) ->
    case maybe_recall_message(From, Meta) of
        ok ->
            case msync_route:save_and_route(JID, To, Meta) of
                ok ->
                    return_ok(From, To, ClientId, ServerId, Response);
                {error, Reason} ->
                    return_internal_error(From, To, ClientId, ServerId,
                                          Response, Reason)
            end;
        {error, Reason} ->
            return_internal_error(From, To, ClientId, ServerId, Response, Reason)
    end.

handle_sync_meta_normal_conference(ClientId, ServerId, _From, To, Meta, Response, JID) ->
    process_conference:handle(JID, To, ClientId, ServerId, Meta, Meta#'Meta'.payload, Response).


%% If key is undefined, it is the initial sync request.
handle_sync_queue(undefined = _Key, undefined = _Queue,Response,_JID) ->
    %% when neither key nor queue is known, no response
    Response;
%% Key can be `undefined' if Queue is not `undefined'
handle_sync_queue(Key, Queue0, Response, JID) ->
    Queue =
        case Queue0#'JID'.name of
            undefined ->
                %% this is the system queue.
                Queue0#'JID'{app_key  = undefined, client_resource = undefined};
            _ ->
                chain:apply(
                  Queue0,
                  [{ msync_msg, pb_jid_with_default_domain, [JID] },
                   { msync_msg, pb_jid_with_default_appkey, [JID] }])
        end,

    BinKey =
        case Key of
            undefined ->
                undefined;
            _ ->
                integer_to_binary(Key)
        end,

    {DeletedMetaIds, Metas, NextKey} =
        case is_conference(Queue#'JID'.domain) of
            true ->
                N = app_config:get_msg_page_size(JID#'JID'.app_key),
                MetaIds =
                    msync_offline_msg:delete_group_messages_migration(
                      JID, msync_offline_msg:ignore_resource(Queue), BinKey),
                {ChatMetas, NK} =
                    msync_offline_msg:get_group_messages_migration(
                      JID, msync_offline_msg:ignore_resource(Queue), BinKey, N),
                {MetaIds, ChatMetas, NK};
            false ->
                MetaIds = msync_offline_msg:delete_read_messages(JID, Queue, Key),
                N = app_config:get_msg_page_size(JID#'JID'.app_key),
                {Ms, NK} = msync_offline_msg:get_unread_metas(JID, Queue, Key, N),
                maybe_fix_unread(
                  Ms, JID, Queue,
                  application:get_env(msync, enable_fix_unread, false)),
                {MetaIds, Ms, NK}
        end,

    spawn(lists, foreach,
          [fun(ID) -> dl_packet_filter:check_ack(Queue, JID, ID) end, DeletedMetaIds]),  
    spawn(lists,foreach,[fun(Meta) -> dl_packet_filter:check(Queue, JID, Meta) end, Metas]),
    maybe_produce_message_incr_ack(JID, Queue, Key),

    case NextKey of
        undefined ->
            %% no more message, do nothing
            %% send nothing, see msync_c2s_handler:send_pb_message
            ?DEBUG("no more metas, stop sync queue =~p, key=~p, owner=~p",
                   [msync_msg:pb_jid_to_binary(Queue),Key,
                    msync_msg:pb_jid_to_binary(JID)]),
            chain:apply(
              Response,
              [ {msync_msg,set_unread_metas,[Queue, [], NextKey,JID]},
                {msync_msg,set_is_last,[true]},
                {msync_msg,set_status,['OK',undefined]}
              ]);
        _ ->
            ?DEBUG("sync queue =~p, key=~p, nextkey=~p, owner=~p, messages=~p, ",
                   [ msync_msg:pb_jid_to_binary(Queue),
                     Key,
                     NextKey,
                     msync_msg:pb_jid_to_binary(JID),
                     lists:map(fun(M) -> M#'Meta'.id end, Metas)
                   ]),
            chain:apply(
              Response,
              [ {msync_msg,set_unread_metas,[Queue, Metas,NextKey,JID]},
                {msync_msg,set_status,['OK',undefined]}
              ])
    end.

handle_sync_meta_system(ClientId, ServerId, From, To, Meta, Response, JID) ->
    %% this is the system queue, so that this meta do not save to the db.
    %% msync_route:save(From,To,Meta),
    case msync_msg:get_meta_ns(Meta) of
        %% TODO: refactor these codes
        'CONFERENCE' ->
            handle_sync_meta_normal_conference(ClientId, ServerId, From, To, Meta, Response, JID);
        NS when NS == 'MUC'; NS == 'ROSTER' ->
            case process_system_queue:route(JID, From, To, Meta) of
                ok ->
                    FromS = msync_msg:pb_jid_to_binary(From),
                    ToS = msync_msg:pb_jid_to_binary(To),
                    %% wanna flow control? uncomment out the spawn.
                    ?DEBUG("send server ack for system message client_id=~p server_id=~p from ~p to ~p~n",
                           [ClientId,ServerId, FromS, ToS]),
                    chain:apply(Response,
                                [ {msync_msg,set_status,['OK', undefined]},
                                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]);
                {error, Error} when is_binary(Error) ->
                    ?ERROR_MSG("fail to process system queue for ~s: ~p~nMeta=~p~n",
                               [msync_msg:pb_jid_to_binary(JID), Error, Meta]),
                    chain:apply(Response,
                                [ {msync_msg,set_status,['FAIL', Error]},
                                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}])
            end;
        _ ->
            ?WARNING_MSG("fail to process system queue for ~s:error namespace Meta=~p",
                               [msync_msg:pb_jid_to_binary(JID), Meta]),
                    chain:apply(Response,
                                [ {msync_msg,set_status,['FAIL', <<"error namespace">>]},
                                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}])
    end.

handle_sync_meta_conference(ClientId, ServerId, From, To, Meta, Response, JID) ->
    GroupID = msync_msg:pb_jid_to_long_username(To),
    FromName = msync_msg:pb_jid_to_long_username(From),
    try easemob_muc_redis:is_user_muted(GroupID, FromName) of
        false ->
            try easemob_muc_redis:is_group_member(GroupID, FromName) of
                true ->
                    case maybe_recall_message(From, Meta) of
                        ok ->
                            case msync_route:save(From, To, Meta) of
                                ok ->
                                    case mod_message_limit:maybe_queue_message(
                                           <<"easemob.com">>, From, To, Meta) of
                                        queue ->
                                            return_ok(From, To, ClientId, ServerId, Response);
                                        {error, Reason} when is_binary(Reason) ->
                                            return_internal_error(From, To, ClientId,
                                                                  ServerId, Response, Reason);
                                        {error, _Reason} ->
                                            return_internal_error(
                                              From, To, ClientId,
                                              ServerId, Response, <<"queue error">>);
                                        skip ->
                                            %% Write to large group message cursor was moved to
                                            %% process_muc_queue:write_large_group_message_cursor/4
                                            handle_sync_meta_conference_after_save(
                                              ClientId, ServerId, From, To, Meta, Response, JID)
                                    end;
                                {error, Reason} ->
                                    ?WARNING_MSG("fail to save msg to conference queue for ~s: "
                                                 "Meta=~p, Reason = ~p~n",
                                                 [msync_msg:pb_jid_to_binary(JID), Meta, Reason]),
                                    return_internal_error(From, To, ClientId,
                                                          ServerId, Response, <<"db error">>)
                            end;
                        {error, Reason} ->
                            return_internal_error(From, To, ClientId,
                                                  ServerId, Response, Reason)
                    end;
                false ->
                    ?INFO_MSG("not group/chatroom member, group: ~p, user: ~p~n",
                              [GroupID, FromName]),
                    return_internal_error(From, To, ClientId, ServerId, Response,
                                          <<"not in group or chatroom">>)
            catch
                _Class: Reason ->
                    return_internal_error(From, To, ClientId,
                                          ServerId, Response, Reason)
            end;
        true ->
            ?INFO_MSG("muted, group: ~p, user: ~p~n", [GroupID, FromName]),
            return_internal_error(From, To, ClientId, ServerId,
                                  Response, 'USER_MUTED', <<"user muted">>)
    catch
        _Class: Reason ->
            return_internal_error(From, To, ClientId,
                                  ServerId, Response, Reason)
    end.

handle_sync_meta_conference_after_save(ClientId, ServerId, From, To, Meta, Response, JID) ->
    case process_muc_queue:route(JID, From, To, Meta) of
        ok ->
            FromS = msync_msg:pb_jid_to_binary(From),
            ToS = msync_msg:pb_jid_to_binary(To),
            %% wanna flow control? uncomment out the spawn.
            ?DEBUG("send server ack for system message client_id=~p server_id=~p from ~p to ~p~n",
                   [ClientId,ServerId, FromS, ToS]),
            return_ok(From, To, ClientId, ServerId, Response);
        {error, Error} when is_binary(Error) ->
            ?WARNING_MSG("fail to process system queue for ~s: ~p~nMeta=~p~n",
                         [msync_msg:pb_jid_to_binary(JID), Error, Meta]),
            return_internal_error(From, To, ClientId, ServerId, Response, Error)
    end.
%% TODO, it should be configuable.wk,]
is_conference(<<"conference", _/binary>>) ->
    true;
is_conference(_) ->
    false.


set_sync_timestamp(#'MSync'{ payload = #'CommSyncDL'{} = SyncDL} = MSync,  ReceiveTimeStamp) ->
    Now = time_compat:erlang_system_time(milli_seconds),
    ResponseTimestamp = (Now + ReceiveTimeStamp) div 2,
    IntervalTime = Now - ReceiveTimeStamp,
    easemob_metrics_statistic:observe_histogram(msync_sync_time, IntervalTime),
    case IntervalTime > 5000 of
        true ->
            ?WARNING_MSG("Spent too much time (>5000ms) for handle_sync, Interval Time: ~p, Data: ~p~n", [IntervalTime, SyncDL]);
        _ ->
            ignore
    end,
    MSync#'MSync'{
      payload = SyncDL#'CommSyncDL'{ timestamp = ResponseTimestamp}}.


return_ok(From, To, ClientId, ServerId, Response) ->
    ?DEBUG("send server ack for message client_id=~p server_id=~p from ~p to ~p~n",
           [ClientId,ServerId, msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To)]),
    chain:apply(Response,
                [ {msync_msg,set_status,['OK', undefined]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).

return_internal_error(From, To, ClientId, ServerId, Response, Reason) ->
    ?DEBUG("send server ack for message client_id=~p server_id=~p from ~p to ~p~n",
           [ClientId,ServerId, msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To)]),
    Error = case is_binary(Reason) of
                true -> Reason;
                _ -> atom_to_binary(Reason, latin1)
            end,
    chain:apply(Response,
                [ {msync_msg,set_status,['FAIL', Error]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).

return_internal_error(From, To, ClientId, ServerId, Response, ErrorCode, Reason) ->
    ?DEBUG("send server ack for message client_id: ~p server_id: ~p from ~p to ~p~n",
           [ClientId, ServerId,
            msync_msg:pb_jid_to_binary(From),
            msync_msg:pb_jid_to_binary(To)]),
    Error = case is_binary(Reason) of
                true -> Reason;
                _ -> atom_to_binary(Reason, latin1)
            end,
    chain:apply(Response,
                [ {msync_msg,set_status,[ErrorCode, Error]},
                  {msync_msg,set_meta_ack_id, [ClientId, ServerId]}]).

maybe_fix_unread([], JID, Queue, true) ->
    ?INFO_MSG("maybe_fix_unread JID: ~p, Queue: ~p~n", [JID, Queue]),
    spawn(msync_fix_unread, clr, [JID, Queue]);
maybe_fix_unread(_Metas, _JID, _Queue, _) ->
    ok.

maybe_recall_message(#'JID'{app_key = AppKey} = From, Meta) ->
    case check_recall_message(AppKey, Meta) of
        {recall, RecallID} ->
            spawn(fun () -> recall_message(From, RecallID) end),
            ok;
        normal ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

check_recall_message(AppKey, Meta) ->
    case msync_msg:get_message_type(Meta) of
        <<"recall">> ->
            case app_config:is_message_recall_enabled(AppKey) of
                true ->
                    MessageBody = msync_msg:get_meta_payload(Meta),
                    RecallID = integer_to_binary(element(7, MessageBody)),
                    case easemob_message_body:read_message(RecallID, AppKey) of
                        Message when is_binary(Message) ->
                            #'Meta'{timestamp = Timestamp} = msync_msg:decode_meta(Message),
                            Now = time_compat:erlang_system_time(milli_seconds),
                            RecallTimeLimit = app_config:get_message_recall_time(AppKey),
                            if
                                Now - Timestamp =< RecallTimeLimit ->
                                    {recall, RecallID};
                                true ->
                                    {error, <<"exceed recall time limit">>}
                            end;
                        not_found ->
                            normal;
                        _ ->
                            {error, <<"db error">>}
                    end;
                false ->
                    {error, <<"message recall disabled">>}
            end;
        _ ->
            normal
    end.

recall_message(From, RecallID) ->
    ?WARNING_MSG("user: ~p recalled message, id: ~p~n",
                 [msync_msg:pb_jid_to_binary(From), RecallID]),
    AppKey = From#'JID'.app_key,
    message_store:recall_message(AppKey, RecallID).

maybe_produce_message_incr_ack(_, _, undefined) ->
    ok;
maybe_produce_message_incr_ack(#'JID'{app_key = AppKey,
                                      client_resource = Resource} = JID, Queue, MID) ->
    case app_config:is_data_sync_enabled(AppKey) of
        true ->
            spawn(fun () ->
                          easemob_sync_incr_lib:produce_message_incr_ack(
                            msync_msg:pb_jid_to_binary(JID#'JID'{client_resource = undefined}),
                            Resource,
                            msync_msg:pb_jid_to_binary(Queue),
                            integer_to_binary(MID))
                  end);
        false ->
            ignore
    end,
    ok.
