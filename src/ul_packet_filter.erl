-module(ul_packet_filter).
-export([check/4, multi_devices/3]).
-include("logger.hrl").
-include("pb_messagebody.hrl").
-include("gen-erl/keyword_types.hrl").
-include("message_store.hrl").
-define(RESULT_KEYWORDSCAN_SUC, 1).
-define(RESULT_ALLOW_WITH_DENYWORDS, 2).


check(ClientId, From,To,Meta) ->
    easemob_metrics_statistic:observe_summary(rp_size_sum, get_meta_size(Meta)),
    lists:foldl(
      fun(Fun, Acc) ->
              case Acc of
                  ok ->
                      Fun(ClientId, From, To, Meta);
                  {ok, NewMeta} ->
                      ?DEBUG("packet is replaced from ~p to ~p~n"
                            , [Meta, NewMeta]),
                      {ok, NewMeta};
                  {error, {ReturnCode, Description}} ->
                      {error, {ReturnCode, Description}}
              end
      end,
      ok,
      [
       fun maybe_block_inter_app_communication/4,
       fun maybe_block_spam/4,
       fun maybe_keyword_scan/4,
       fun maybe_image_audit/4,
       fun maybe_multi_devices/4,
       fun maybe_unique_msg/4
      ]).


maybe_block_inter_app_communication(_ClientId, From, To, _Meta) ->
    case  From#'JID'.app_key =:= To#'JID'.app_key of
        true ->
            ok;
        false ->
            {error, {'PERMISSION_DENIED' , <<"inter-app communication is not allowed">> }}
    end.

maybe_block_spam(_ClientId, From, To, Meta) ->
    case is_allowed_by_antispam(From, To, Meta) of
        true ->
            ok;
        false ->
            {error, {'OK' , <<"blocked by mod_antispam">> }}
    end.

is_allowed_by_antispam(From,To, Meta) ->
    case is_chat_message(Meta) of
        true ->
            User = msync_msg:pb_jid_to_binary(From),
            case app_config:is_antispam_send(User) of
                true ->
                    AntispamService = app_config:get_antispam_service(User),
                    case app_config:is_antispam_receive(User) of
                        true ->
                            not(rpc_is_spam(From, To, Meta, AntispamService));
                        false ->
                            spawn(fun() -> rpc_is_spam(From, To, Meta, AntispamService) end),
                            true
                    end;
                false ->
                    true
            end;
        false ->
            true
    end.
is_chat_message(Meta) ->
    case msync_msg:get_meta_payload(Meta) of
        #'MessageBody'{} ->
            true;
        _ ->
            false
    end.

rpc_is_spam(From0,To0, Meta, thrift) ->
    MessageBody = msync_msg:get_meta_payload(Meta),
    Content = msync_msg_ns_chat:to_json_map(MessageBody),
    #'JID'{
       app_key = AppKey,
       name = _User,
       domain = _Domain
      } = From0,
    Sender = msync_msg:pb_jid_to_binary(From0),
    To = msync_msg:pb_jid_to_binary(To0),
    ChatType = get_message_body_type(MessageBody),
    Timestamp = time_compat:erlang_system_time(milli_seconds),
    IP = case get_ip_address(From0) of
             undefined ->
                 <<"0.0.0.0">>;
             IP0 ->
                 IP0
         end,
    %% {
    %%     "app": "easemob-demo#chatdemoui",
    %%     "sender": "easemob-demo#chatdemoui_c5",
    %%     "acceptor": "easemob-demo#chatdemoui_c6@easemob.com",
    %%     "time": 1464429769425,
    %%     "content": {
    %%         "bodies": [
    %%             {
    %%                 "msg": "yes",
    %%                 "type": "txt"
    %%             }
    %%         ],
    %%         "ext": {
    %%             "timestamp": 1464429769253
    %%         },
    %%         "from": "c5",
    %%         "to": "c6"
    %%     },
    %%     "type": "chat",
    %%     "ip": "118.247.3.98"
    %% }

    Data = jsx:encode([{app, AppKey}, {sender, Sender}, {acceptor, To}, {time, Timestamp}, {content, Content}, {type, ChatType}, {ip, IP}]),
    Result = im_thrift:call(behavior_service_thrift, getBehaviorSpamProb, [Data]),
    case Result of
        {ok, 1} ->
            true;
        {ok, 1.0} ->
            true;
        _ ->
            false
    end;
rpc_is_spam(From0,_To0, Meta, wangyi) ->
    MessageBody = msync_msg:get_meta_payload(Meta),
    Content = msync_msg_ns_chat:to_json_map(MessageBody),
    ?DEBUG("CONTENT:~p", [Content]),
    case Content of
        #{<<"bodies">> := [#{<<"type">> := <<"txt">>, <<"msg">> := Text}|_]} ->
            MsgId = msync_msg:get_meta_id(Meta),
            Sender = msync_msg:pb_jid_to_binary(From0),
            Timestamp = time_compat:erlang_system_time(milli_seconds),
            [SecretId, SecretKey, BusinessId|_] = app_config:get_antispam_service_params(Sender),
            Params = [{secretId, SecretId},
                      {businessId, BusinessId},
                      {version, "v3"},
                      {timestamp, Timestamp},
                      {nonce, rand:uniform(2000000000)},
                      {dataId, MsgId},
                      {content, Text},
                      {account, Sender}
                     ],
            easemob_antispam_wangyi:is_spam(text, SecretKey, Params);
        #{} ->
            false
    end.


maybe_keyword_scan(_ClientId, From, _To, Meta) ->
    case app_config:is_keyword_scan_open() of
        false ->
            %% when the global setting is off, check the app
            %% specific setting
            User = msync_msg:pb_jid_to_long_username(From),
            case app_config:is_keyword_scan_used(User) of
                true ->
                    AppKey = From#'JID'.app_key,
                    keyword_scan(AppKey, Meta);
                false ->
                    ok
            end;
        true ->
            %% when the global setting is on, then enable this feature
            %% for every app
            AppKey = From#'JID'.app_key,
            keyword_scan(AppKey, Meta)
    end.

keyword_scan(AppKey, Meta) ->
    case is_chat_message(Meta) of
        true ->
            keyword_scan_1(AppKey, Meta);
        false ->
            %% ignore meta:s other than chat messages.
            ok
    end.

keyword_scan_1(AppKey,Meta) ->
    case get_message_body_text(msync_msg:get_meta_payload(Meta)) of
        undefined ->
            %% ignore any packet other than text messages
            ok;
        Text when is_binary(Text) ->
            keyword_scan_2(AppKey, Meta, Text)
    end.

keyword_scan_2(AppKey, Meta, Text) ->
    case im_thrift:call(text_parse_service_thrift, parseWords, [AppKey, Text]) of
        {ok , #'ResultMessage'{} = ResultMessage} ->
            keyword_scan_process_result_message(ResultMessage,Meta);
        _ ->
            %% in case of any error, return ok as if the packet looks
            %% perfect.
            ok
    end.


keyword_scan_process_result_message(ResultMessage,Meta) ->
    case ResultMessage#'ResultMessage'.code of
        ?RESULT_KEYWORDSCAN_SUC ->
            case ResultMessage#'ResultMessage'.words of
                [] -> ok;
                _Words ->
                    {error, {'PERMISSION_DENIED', <<"sensitive words">>}}
            end;
        ?RESULT_ALLOW_WITH_DENYWORDS ->
            Info = ResultMessage#'ResultMessage'.info,
            NewMeta = replace_message_body(Meta, Info),
            {ok, NewMeta};
        _ ->
            ok
    end.

get_message_body_type(MessageBody) ->
    case MessageBody#'MessageBody'.type of
        'CHAT' ->
            <<"chat">>;
        'GROUPCHAT' ->
            <<"groupchat">>;
        _ ->
            <<"chat">>
    end.
get_message_body_text(#'MessageBody'{
                         contents = [
                                      #'MessageBody.Content'{
                                         type = 'TEXT',
                                         text = Text
                                        }]}) ->
    Text;
get_message_body_text(_) ->
    undefined.


replace_message_body(Meta, NewText) ->
    MessageBody = msync_msg:get_meta_payload(Meta),
    NewMessageBody =
        MessageBody#'MessageBody'{
          contents = [
                      #'MessageBody.Content'{
                         type = 'TEXT',
                         text = NewText
                        }]},
    msync_msg:set_meta_payload(Meta, NewMessageBody).


get_ip_address(_JID) ->
    %% todo: check the cost of inet:peername
    <<"0.0.0.0">>.


maybe_multi_devices(_ClientId, From, To, Meta) ->
    case is_chat_message(Meta) of
        true ->
            case is_multi_devices_enabled(From) of
                true ->
                    CIDBin = msync_msg:pb_jid_to_binary(
                               To#'JID'{client_resource = undefined}),
                    case utils:is_group(CIDBin) of
                        true ->
                            case easemob_group_cursor:is_large_group(CIDBin) of
                                false ->
                                    %% do it for best effort.
                                    spawn(fun()-> multi_devices(From, To, Meta) end);
                                true ->
                                    ok
                            end;
                        false ->
                            spawn(fun()-> multi_devices(From, To, Meta) end)
                    end;
                false ->
                    ok
            end;
        _ ->
            ok
    end,
    ok.

is_multi_devices_enabled(From) ->
    case application:get_env(msync, enable_multi_devices, false) of
        true ->
            true;
        _ ->
            app_config:is_multi_resource_enabled(
              msync_msg:pb_jid_to_long_username(From))
    end.

multi_devices(_From, #'JID'{client_resource = Resource} = _To, _Meta)
  when Resource =/= undefined ->
    ok;
multi_devices(From, To, Meta) ->
    ThisResouce = From#'JID'.client_resource,
    AllResources =  get_all_resources(From),
    OtherResources = AllResources -- [ThisResouce, ?DEFAULT_RESOURCE],
    lists:foreach(
      fun(R) ->
              route_to_other_resource(From, To, Meta, R)
      end,
      OtherResources).

route_to_other_resource(From, To, Meta, R) ->
    OtherFromJID = From#'JID'{client_resource = R},
    msync_inbox:push(OtherFromJID, To, msync_msg:get_meta_id(Meta)),
    msync_route:maybe_send_notice(
      msync_route:get_online_sessions(OtherFromJID),
      To, OtherFromJID, Meta).

get_all_resources(From) ->
    %% I don't like to hard code the default resouce <<"mobile">>
    %% here, but to save the storage space, the default resource is
    %% not stored in db, it's potentionally troublesome.
    User = msync_msg:pb_jid_to_binary(
             msync_offline_msg:ignore_resource(From)),
    [Resources] = easemob_resource:get_resources([User]),
    Resources.

maybe_unique_msg(ClientID, From, _To, Meta) ->
    case app_config:is_unique_msg_enabled(msync_msg:pb_jid_to_long_username(From)) of
        true ->
            ?DEBUG("ClientID: ~p, From: ~p, Meta: ~p~n",[ClientID, From, Meta]),
            case easemob_message_idcache:get_id(msync_msg:pb_jid_to_long_username(From), ClientID) of
                not_found ->
                    %% ServerID = msync_msg:get_meta_id(Meta),
                    %% easemob_message_idcache:set_id(msync_msg:pb_jid_to_long_username(From), ClientID, ServerID),
                    ok;
                ID ->
                    ?INFO_MSG("duplicated client msg id ClientID: ~p, From: ~p, ServerID: ~p~n",[ClientID, From, ID]),
                    {error, {'OK' , <<"duplicated client msg id">> }}
             end;
        false ->
            ok
    end.

maybe_image_audit(_ClientId, From, To, Meta) ->
    case is_allowed_by_image_audit(From, To, Meta) of
        true ->
            ok;
        false ->
            {error, {'OK', <<"blocked by image audit">>}}
    end.

is_allowed_by_image_audit(From, _To, Meta) ->
    case is_chat_message(Meta) of
        true ->
            User = msync_msg:pb_jid_to_binary(From),
            AppKey = From#'JID'.app_key,
            case app_config:get_image_audit_uid(User) of
                undefined ->
                    true;
                _ ->
                    MessageBody = msync_msg:get_meta_payload(Meta),
                    case msync_msg_ns_chat:to_json_map(MessageBody) of
                        #{<<"bodies">> := Bodies} ->
                            ImageUrls = [Url||#{<<"type">>:= <<"img">>, <<"url">>:=Url}<-Bodies],
                            case ImageUrls of
                                [] -> true;
                                _ ->
                                    ?DEBUG("AppKey:~p,ImageUrls:~p",[AppKey, ImageUrls]),
                                    case easemob_image_audit:check_image(AppKey, <<"url">>, ImageUrls) of
                                        {ok, #{<<"oks">> := Oks}} ->
                                            IsOk = lists:all(fun(Ok) -> Ok == true end, Oks),
                                            IsOk;
                                        _ ->
                                            IsSendWhenFail = app_config:is_image_audit_send_when_fail(User),
                                            IsSendWhenFail
                                    end
                            end;
                        _ ->
                            true
                    end
            end;
        false ->
            true
    end.

get_meta_size(Meta) ->
    MetaBin = msync_msg:encode_meta(Meta),
    byte_size(MetaBin).
