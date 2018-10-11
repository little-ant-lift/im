-module(msync_c2s_handler).
-export([handle/2
        , handle/3
         %% send_pb_message
         ]).
-include("logger.hrl").
-include("jlib.hrl").
-include("pb_msync.hrl").
-include("easemob_session.hrl").
-include("msync.hrl").

handle(C2SPid, Info) ->
    handle(C2SPid, Info, #state{}).

handle(_C2SPid,{sleep, Timer}, _State) ->
    timer:sleep(Timer);
handle(_C2SPid,{become_controller,Socket}, _State) ->
    ok = inet:setopts(Socket, [{active, once},
                               {mode,binary},
                               {packet, 4}]);
handle(_C2SPid, {_,_,get_unack_msgs}, _State) ->
    %% ignore this message. ejabberd tries to get unack messages.
    ok;
handle(_C2SPid, {route, _From, _To, _Packet} = M, State) ->
    handle_route(_C2SPid, M, State);
handle(_C2SPid, {route, From, To, Metas, Socket}, State)
  when is_port(Socket) ->
    handle_route(_C2SPid, {route, From, To, Metas, Socket}, State);
handle(_C2SPid, {route, From, To, Packet, _Session}, State) ->
    handle_route(_C2SPid, {route, From, To, Packet}, State);
handle(_C2SPid, {replaced, Session}, State) ->
    handle_replaced(_C2SPid, Session, State),
    ok;
handle(_C2SPid, {tcp, Socket, <<Data/binary>>}, State) ->
    Msg = try
              msync_msg:decode(Data, State#state.encrypt_type, State#state.encrypt_key)
          catch
              Type:What ->
                  ?ERROR_MSG("unexpected exception when decoding PB message, ~p:~p~n\tstacktrace = ~p~n\tdata=~p~n",
                             [Type, What, erlang:get_stacktrace(), Data]),
                  ?INFO_MSG("close session when decode error, socket: ~p~n", [Socket]),
                  msync_c2s_lib:maybe_close_session(Socket),
                  undefined
          end,
    case Msg of
        undefined ->
            undefined;
        #'MSync'{} ->
            msync_c2s_lib:set_socket_prop(Socket, compression_algorithm, Msg#'MSync'.compress_algorimth),
            DataSize = byte_size(Data),
            Command = msync_msg:get_command(Msg),
            case Command == 'PROVISION' of
                true ->
                    CurrentTime = time_compat:erlang_system_time(milli_seconds),
                    ProvisionPayload = Msg#'MSync'.payload,
                    MsgFilter = Msg#'MSync'{auth = <<"none">>, payload = ProvisionPayload#'Provision'{auth = <<"none">>, password = undefined}},
                    ?INFO_MSG("receive connection time: ~p provision: ~p~n", [CurrentTime, MsgFilter]),
                    case Msg#'MSync'.encrypt_type of
                        [] ->
                            AppKey = (Msg#'MSync'.guid)#'JID'.app_key,
                            case easemob_encrypt:get_rsa_private_key(AppKey) == undefined of
                                true ->
                                    case app_config:is_block_with_encrypt(AppKey) of
                                        true ->
                                            Response = chain:apply(Msg,
                                                                   [{msync_msg,set_command, [dl, Command]},
                                                                    {msync_msg,set_status, ['ENCRYPT_ENABLE', <<"Sorry, you must encrypt?">>]}]),
                                            send_pb_message(Response, Socket, 
                                                            #'JID'{app_key = <<"unknown">>, name = <<"unknown">>, domain = <<"easemob.com">>}, State),
                                            receive_next_packet(Socket),
                                            State;
                                        false ->
                                            handle_0(Msg,Socket,DataSize, State),
                                            State
                                    end;
                                false ->
                                    handle_0(Msg,Socket,DataSize, State),
                                    State
                            end;
                        [ChoosedEncryptType] ->
                            EncryptKey = (Msg#'MSync'.payload)#'Provision'.encrypt_key,
                            EncryptResponse = 
                                case EncryptKey of
                                    disable_encrypt ->
                                        chain:apply(Msg,
                                                    [{msync_msg,set_command, [dl, Command]},
                                                     {msync_msg,set_status, ['ENCRYPT_DISABLE', <<"Sorry, you have no need encrypt?">>]}]);
                                    enable_encrypt ->
                                        AppKey = (Msg#'MSync'.guid)#'JID'.app_key,
                                        EncryptPublicData = easemob_encrypt:get_rsa_public_key_original(AppKey),
                                        chain:apply(Msg,
                                                    [{msync_msg,set_command, [dl, Command]},
                                                     {msync_msg,set_encrypt, [[ChoosedEncryptType], EncryptPublicData]},
                                                     {msync_msg,set_status, ['ENCRYPT_ENABLE', <<"Sorry, you must encrypt?">>]}]);
                                    fail_encrypt ->
                                        AppKey = (Msg#'MSync'.guid)#'JID'.app_key,
                                        EncryptPublicData = easemob_encrypt:get_rsa_public_key_original(AppKey),
                                        chain:apply(Msg,
                                                    [{msync_msg,set_command, [dl, Command]},
                                                     {msync_msg,set_encrypt, [[ChoosedEncryptType], EncryptPublicData]},
                                                     {msync_msg,set_status, ['DECRYPT_FAILURE', <<"Sorry, you data decrypt failure?">>]}]);
                                    _DesKey ->
                                        undefined
                                end,
                            case EncryptResponse == undefined of
                                true ->
                                    NewState = State#state{
                                                 encrypt_key = EncryptKey,
                                                 encrypt_type = ChoosedEncryptType},
                                    handle_0(Msg,Socket,DataSize, NewState),
                                    NewState;
                                false ->
                                    send_pb_message(EncryptResponse, Socket, 
                                                    #'JID'{app_key = <<"unknown">>, name = <<"unknown">>, domain = <<"easemob.com">>}, State),
                                    receive_next_packet(Socket),
                                    State
                            end
                    end;
                false ->
                    handle_0(Msg,Socket,DataSize, State),
                    State
            end
    end;
%% upon receiving any tcp error, close the socket.
handle(_C2SPid, {tcp_error, Socket, Reason}, _State) ->
    ?INFO_MSG("close session when tcp error, socket: ~p, reason: ~p~n",
              [Socket, Reason]),
    msync_c2s_lib:maybe_close_session(Socket),
    ok;
%% it seems that when connect is disconnected abnormally, the below
%% message is received.
handle(_C2SPid, {'EXIT', Socket, Reason}, _State) ->
    ?INFO_MSG("close session when receive exit, socket: ~p, reason: ~p~n",
              [Socket, Reason]),
    msync_c2s_lib:maybe_close_session(Socket),
    ok;

handle(_C2SPid, {tcp_closed, Socket}, _State) ->
    ?INFO_MSG("close session when tcp closed, socket: ~p~n", [Socket]),
    msync_c2s_lib:maybe_close_session(Socket),
    ok;

handle(_C2SPid, {Ref, _}, State) when is_reference(Ref) ->
    ok;

handle(_C2SPid, Msg, State) ->
    Socket = State#state.socket,
    ?ERROR_MSG("close session when receive unknown msg, socket: ~p, msg:~p~n", [Socket, Msg]),
    msync_c2s_lib:maybe_close_session(Socket),
    ok.

handle_0(Msg,Socket,DataSize, State) ->
    try
        ?DEBUG("Socket = ~p, process pb  ~p~n",[Socket, Msg]),
        handle_1(Msg,Socket,DataSize, State)
    catch
        Type:What ->
            ?ERROR_MSG("unexpected exception ~p:~p,stacktrace ~p,msg=~p,~n",
                       [Type, What, erlang:get_stacktrace(), Msg]),
            ?INFO_MSG("close session when handle1 error, socket: ~p~n", [Socket]),
            msync_c2s_lib:maybe_close_session(Socket)
    after
        %% receive next packet, ignore the error in case the socket is
        %% already closed by server.
        receive_next_packet(Socket)
    end.

%% DataSize is used for traffic limitation.
handle_1(Request,Socket,DataSize, State)          ->
    %% to save bandwidth, only the first response has the so-called
    %% `server resource` and send it back to client.
    {JID, InitResponse} = maybe_auth(Request, Socket, State),
    case JID of
        undefined ->
            %% unauthorize access close connection
            %% ignore the error returned by send_pb_message
            send_pb_message(InitResponse, Socket, #'JID'{app_key = <<"unknown">>, name = <<"unknown">>, domain = <<"easemob.com">>}, State),
            ?INFO_MSG("close session when jid is undefined, socket: ~p, request: ~p~n",
                      [Socket, Request]),
            msync_c2s_lib:maybe_close_session(Socket);
        #'JID'{} ->
            Response = handle_2(Request, InitResponse, JID),
            case send_pb_message(Response,Socket, JID, State) of
                ok -> ok;
                {error, Reason} ->
                    ?ERROR_MSG("send response error: reason=~p, response=~p",
                               [Reason, Response]),
                    fail
            end,
            traffic_limitation(Socket, DataSize, JID)
    end.

handle_2(Request, Response, JID)   ->
    Command = msync_msg:get_command(Request),
    NewResponse =
        case Command of
            'UNREAD' ->
                process_unread:handle(Request, Response, JID);
            'SYNC' ->
                process_sync:handle(Request, Response, JID);
            'PROVISION' ->
                process_provision:handle(Request, Response, JID)
        end,
    NewResponse.


handle_route(_C2SPid, {route, #'JID'{} = From, #'JID'{}= To, Id}, State)
  when is_integer(Id) ->
    case msync_c2s_lib:get_pb_jid_prop(To,socket) of
        {ok, Socket} ->
            try_send_notice_via_socket(Socket, From, To, State),
            ?DEBUG("notify a new msync packet arrival~n"
                      "\tFrom=~p~n"
                      "\tTo=~p~n"
                      "\tId=~p~n",
                      [From,To,Id]);
        {error, {many_found, Sessions}} ->
            ?DEBUG("notify a new msync packet arrival, but many session found~n"
                      "\tFrom=~p~n"
                      "\tTo=~p~n"
                      "\tId=~p~n"
                      "\tSessions=~p~n",
                      [From,To,Id, Sessions]),
            [Session | DirtySessions] = sort_session(Sessions),
            close_dirty_sessions(To, DirtySessions, State),
            Socket = hd(Session),
            try_send_notice_via_socket(Socket, From, To, State);
        {error, Reason} ->
            ?DEBUG("faile to notify a new msync packet arrival~n"
                   "\tReason = ~p~n"
                   "\tFrom=~p~n"
                   "\tTo=~p~n"
                   "\tId=~p~n",
                   [Reason, From,To,Id])
    end;
handle_route(_C2SPid, {route, #'JID'{} = From, #'JID'{} = To, Metas, Socket}, State)
  when is_port(Socket) ->
    try_send_meta_via_socket(Socket, From, To, Metas, State);
handle_route(_C2SPid, {route, #'JID'{} = From, #'JID'{}= To, #'Meta'{}=Meta}, State) ->
    case msync_c2s_lib:get_pb_jid_prop(To,socket) of
        {ok, Socket} ->
            try_send_meta_via_socket(Socket, From, To, [Meta], State),
            ?DEBUG("send a msync meta packet arrival~n"
                      "\tFrom=~p~n"
                      "\tTo=~p~n"
                      "\tMeta=~p~n",
                      [From,To,Meta]);
        {error, {many_found, Sessions}} ->
            ?DEBUG("send a msync meta packet arrival, but many session found~n"
                      "\tFrom=~p~n"
                      "\tTo=~p~n"
                      "\tMeta=~p~n"
                      "\tSessions=~p~n",
                      [From,To,Meta, Sessions]),
            [Session | DirtySessions] = sort_session(Sessions),
            close_dirty_sessions(To, DirtySessions, State),
            Socket = hd(Session),
            try_send_meta_via_socket(Socket, From, To, [Meta], State);
        {error, Reason} ->
            ?DEBUG("faile to send a meta msync packet arrival~n"
                   "\tReason = ~p~n"
                   "\tFrom=~p~n"
                   "\tTo=~p~n"
                   "\tMeta=~p~n",
                   [Reason, From,To,Meta])
    end;
handle_route(_C2SPid, {route, #jid{} = From, #jid{}= To, #xmlel{name = <<"presence">>}=  Packet}, State) ->
    ?DEBUG("new presence from ejabberd~n"
           "\tFrom=~p~n"
           "\tTo=~p~n"
           "\tPacket=~p~n",
           [From,To,Packet]),
    process_xmpp_presence(msync_msg:jid_to_pb_jid(From),msync_msg:jid_to_pb_jid(To),Packet, State);
handle_route(_C2SPid, {route, #jid{} = From, #jid{}= To, #xmlel{name = <<"iq">>} = Packet}, State) ->
    ?DEBUG("new iq from ejabberd~n"
           "\tFrom=~p~n"
           "\tTo=~p~n"
           "\tPacket=~p~n",
           [From,To,Packet]),
    process_xmpp_iq(msync_msg:jid_to_pb_jid(From),msync_msg:jid_to_pb_jid(To),Packet, State);
handle_route(_C2SPid, {route, #jid{} = From, #jid{}= To, #xmlel{name = <<"message">>} = Packet}, State) ->
    ?DEBUG("new message from ejabberd~n"
           "\tFrom=~p~n"
           "\tTo=~p~n"
           "\tPacket=~p~n",
           [From,To,Packet]),
    process_xmpp_message(msync_msg:jid_to_pb_jid(From),msync_msg:jid_to_pb_jid(To),Packet, State);
handle_route(_C2SPid, {route, From, To, {broadcast,{item,{_U,_S,_R},_Flag}} = Packet}, _State) ->
    %% I don't understand this protocol yet.
    ?DEBUG("new broadcast from ejabberd~n"
           "\tFrom=~p~n"
           "\tTo=~p~n"
           "\tPacket=~p~n",
           [From,To,Packet]),
    ok;
handle_route(_C2SPid, {route, From, To, {broadcast, {exit, Reason}}}, State) ->
    ?INFO_MSG("user disconnected, from: ~p, to: ~p, reason: ~p~n",
              [From, To, Reason]),
    process_user_disconnect(To, Reason, State),
    ok;
handle_route(_C2SPid, {route, From, To, Packet}, _State) ->
    ?ERROR_MSG("unable to route packet.\n"
               "\tFrom=~p~n"
               "\tTo=~p~n"
               "\tPacket=~p~n",
               [From,To,Packet]).


maybe_auth(Request, Socket, State) ->
    OrigJID = msync_c2s_lib:get_socket_prop(Socket,pb_jid),
    case OrigJID of
        {ok, #'JID'{} = JID} ->
            %% user already login
            Command = msync_msg:get_command(Request),
            InitMSync = msync_msg:set_command(#'MSync'{}, dl, Command),
            {JID, InitMSync};
        {error, not_found} ->
            %% user did not login yet
            %% check license activation first
            case maybe_check_license(Request,Socket) of
                {ok, Response} ->
                    send_pb_message(Response,Socket, _JID = #'JID'{domain = <<"easemob.com">>}, State),
                    {undefined, Request};
                continue ->
                    %% return {JID, InitResponse}
                    {TmpJID, InitMSync} = msync_c2s_handler_auth:try_authenticate(Request),
                    %% TmpJID might be undefined if authentication failed.
                    case TmpJID of
                        undefined ->
                            %% auth fail, do not open session
                            {TmpJID, InitMSync};
                        #'JID'{client_resource = Resource} ->
                            Version = get_version(Request),
                            {OSType, ClientVersion} =
                                case Version of
                                    undefined ->
                                        {undefined, <<"unknown">>};
                                    Value ->
                                        Value
                                end,
                            DeviceID = get_device_id(Request),
                            System = easemob_resource:get_system_by_os_and_resource(OSType, Resource),
                            case easemob_resource:is_system_enabled(msync_msg:pb_jid_to_long_username(TmpJID), System) of
                                false ->
                                    ?INFO_MSG("user is limit for this platform EID:~p Resource:~p OSType:~p DeviceID:~p ~n",
                                              [msync_msg:pb_jid_to_long_username(TmpJID), Resource, OSType, DeviceID]),
                                    Command = msync_msg:get_command(Request),
                                    {undefined,
                                     chain:apply(Request,
                                                 [{msync_msg,set_command, [dl, Command]},
                                                  {msync_msg,set_status, ['PLATFORM_LIMIT', <<"Sorry, you are limit on this platform?">>]}])};
                                true ->
                                    ResourceOrig = easemob_resource:replace(
                                                    msync_msg:pb_jid_to_long_username(TmpJID),
                                                    Resource, OSType, DeviceID),
                                    case justice_resource(ResourceOrig) of
                                        error ->
                                            ?INFO_MSG("user is limit for this illegal resource EID: ~p, Resource: ~p ~n",
                                                      [msync_msg:pb_jid_to_long_username(TmpJID), ResourceOrig]),
                                            Command = msync_msg:get_command(Request),
                                            {undefined, 
                                            chain:apply(Request,
                                                        [{msync_msg,set_command, [dl, Command]},
                                                        {msync_msg,set_status, ['FAIL', <<"Sorry, your resource is illegal?">>]}])};
                                        ResourceFilter ->
                                            NewResource =   case ResourceFilter of
                                                                <<"">> ->
                                                                    iolist_to_binary([randoms:get_string()
                                                                                      | [jlib:integer_to_binary(X)
                                                                                      || X <- tuple_to_list(os:timestamp())]]);
                                                                _ ->
                                                                    ResourceFilter
                                                            end,
                                            UserWithoutDomain = msync_msg:pb_jid_to_long_username(TmpJID),
                                            case easemob_resource:is_resource_enabled( UserWithoutDomain, NewResource) of
                                                false ->
                                                    ?INFO_MSG("user is limit devices EID:~p Resource:~p OSType:~p DeviceID:~p ~n",
                                                              [UserWithoutDomain, Resource, OSType, DeviceID]),
                                                    Command = msync_msg:get_command(Request),
                                                    {undefined,
                                                     chain:apply(Request,
                                                                 [{msync_msg,set_command, [dl, Command]},
                                                                  {msync_msg,set_status, ['TOO_MANY_DEVICES', <<"Sorry, you devices is overflow?">>]}])};
                                                ResourceEnabledRet ->
                                                    NewTmpJID = TmpJID#'JID'{client_resource = NewResource},
                                                    UserDomain = msync_msg:pb_jid_to_binary(NewTmpJID#'JID'{client_resource = undefined}),
                                                    %% replace old session
                                                    case ResourceEnabledRet of
                                                        {false, ReplaceResource} ->
                                                            User = msync_msg:pb_jid_to_long_username(NewTmpJID),
                                                            {ok, Session} = easemob_session:get_session(User, NewTmpJID#'JID'.domain, ReplaceResource),
                                                            ?INFO_MSG("Resource is Overflow and replace old session ~p NewResoource ~p ~n", [Session, NewResource]),
                                                            easemob_session:replace_session(Session),
                                                            easemob_session:close_session(Session#session.sid, User, NewTmpJID#'JID'.domain, ReplaceResource),
                                                            easemob_resource:remove_resource(UserDomain, ReplaceResource);
                                                        true ->
                                                            ignore
                                                    end,
                                                    easemob_resource:login( UserDomain, NewTmpJID#'JID'.client_resource),
                                                    DeviceName = get_device_name(Request),
                                                    Ext = [{device_uuid, DeviceID}, {device_name, DeviceName}],
                                                    NewJID = msync_c2s_lib:open_session(NewTmpJID, Socket, Version, Ext),
                                                    easemob_offline_index:adjust_offline_message(UserDomain, NewJID#'JID'.client_resource),
                                                    %% comment by zhangchao
                                                    %% del user's apns when user login
                                                    NewJIDIgnoreB = msync_msg:pb_jid_to_binary(msync_offline_msg:ignore_resource(NewJID)),
                                                    easemob_apns:del_user_apns(NewJIDIgnoreB),
                                                    set_authorized_sock_opts(Socket),
                                                    {NewJID, InitMSync}
                                            end
                                    end
                            end
                    end
            end
    end.

set_authorized_sock_opts(Socket) ->
    case application:get_env(msync, authorized_sock_opts, []) of
        [] ->
            skip;
        SockOpts ->
            inet:setopts(Socket, SockOpts)
    end.

%%filter illegal resource
justice_resource(Resource) ->
    case application:get_env(message_store, resource_justice_enabled, true) of
        true ->
            jlib:resourceprep(Resource);
        _ ->
            Resource
    end.


get_version(#'MSync'{
               command = 'PROVISION',
               payload = #'Provision'{
                            os_type = OsType,
                            version = Version}
              } = _Request) ->
    {os_type_to_string(OsType), easemob_version:parse(Version)};
get_version(_Request) ->
    undefined.

get_device_id(#'MSync'{
                 command = 'PROVISION',
                 payload = #'Provision'{device_uuid = <<"">>}}) ->
    undefined;
get_device_id(#'MSync'{
                 command = 'PROVISION',
                 payload = #'Provision'{device_uuid = DeviceID}}) ->
    DeviceID;
get_device_id(_Request) ->
    undefined.

get_device_name(#'MSync'{
                   command = 'PROVISION',
                   payload = #'Provision'{device_name = undefined}}) ->
    <<"">>;
get_device_name(#'MSync'{
                   command = 'PROVISION',
                   payload = #'Provision'{device_name = DeviceName}}) ->
    DeviceName;
get_device_name(_Request) ->
    <<"">>.

os_type_to_string('OS_ANDROID') ->
    <<"android">>;
os_type_to_string('OS_IOS') ->
    <<"ios">>;
os_type_to_string('OS_WIN') ->
    <<"win">>;
os_type_to_string('OS_LINUX') ->
    <<"linux">>;
os_type_to_string('OS_OSX') ->
    <<"osx">>;
os_type_to_string(_) ->
    undefined.

process_user_disconnect(JID, Reason, State) ->
    {U, S, R} = jlib:jid_tolower(JID),
    {ok, Session} = easemob_session:get_session(U, S, R),
    PbJID = msync_msg:jid_to_pb_jid(JID),
    MaybeSocket = proplists:get_value(socket, Session#session.info, undefined),
    case MaybeSocket of
        Socket when is_port(Socket) ->
            close_user_session(PbJID, Socket, erlang:binary_to_list(Reason), State);
        undefined ->
            ?ERROR_MSG("user removed but cannot find the socket.~n"
                       "\tSocket = ~p~n"
                       "\tSessiom = ~p~n",
                       [MaybeSocket, Session])
    end.

close_user_session(JID, Socket, "User removed", State) ->
    close_user_session_with_payload(JID, Socket, msync_msg_ns_stat:removed(), State);
close_user_session(JID, Socket, "Users password been changed" ++ _ , State) ->
    close_user_session_with_payload(JID, Socket, msync_msg_ns_stat:kicked(), State);
close_user_session(JID, Socket, "User disconnect by other device", State) ->
    close_user_session_with_payload(JID, Socket, msync_msg_ns_stat:disconnect(), State).

close_user_session_with_payload(JID, Socket, PayLoad, State) ->
    ?INFO_MSG("close removed user sesssion, JID = ~s, Socket = ~p~n",
              [msync_msg:pb_jid_to_binary(JID), Socket]),
    SysQueue = msync_msg:pb_jid(undefined, undefined, <<"easemob.com">>, undefined),
    Response =
        %% TODO, refactor the blow code.
        #'MSync'{
           version = 'MSYNC_V1',
           command = 'SYNC',
           payload =
               #'CommSyncDL'{
                  metas =
                      [
                       chain:apply(
                         #'Meta' {
                            ns = 'STATISTIC',
                            payload = PayLoad
                           },
                         [{msync_msg, allocate_meta_id, []},
                          {msync_msg, generate_timestamp, []},
                          {msync_msg, set_meta_from, [SysQueue]},
                          {msync_msg, set_meta_to, [JID]}])],
                  queue = SysQueue
                 }
          },
    send_pb_message(Response, Socket, JID, State),
    msync_c2s_lib:maybe_close_session(Socket).

handle_replaced(_C2SPid, Session, State) ->
    {U,S,R} = Session#session.usr,
    [AppKey, Name] = binary:split(U, <<"_">>),
    JID = msync_msg:pb_jid(AppKey,Name,S,R),
    %% msync_log:on_user_logout(JID, replaced, Session#session.info),
    %% MaybeSocket = msync_c2s_lib:get_pb_jid_prop(JID,socket),
    MaybeSocket = proplists:get_value(socket, Session#session.info, undefined),
    case MaybeSocket of
        Socket when is_port(Socket) ->
            close_duplicate_session(JID, Socket, State, Session);
        undefined ->
            ?ERROR_MSG("session is replaced but cannot find the socket.~n"
                       "\tSocket = ~p~n"
                       "\tSessiom = ~p~n",
                       [MaybeSocket, Session])
    end.

close_duplicate_session(JID, Socket, State) ->
    close_duplicate_session(JID, Socket, State, undefined).
close_duplicate_session(JID, Socket, State, Session) ->
    ?INFO_MSG("close duplicated sesssion, JID = ~s, Socket = ~p~n",
              [msync_msg:pb_jid_to_binary(JID), Socket]),
    SysQueue = msync_msg:pb_jid(undefined, undefined, <<"easemob.com">>, undefined),
    case is_send_session_replace_notice(JID, Session) of
        true ->
            Response =
                %% TODO, refactor the blow code.
                #'MSync'{
                   version = 'MSYNC_V1',
                   command = 'SYNC',
                   payload =
                       #'CommSyncDL'{
                          metas =
                              [
                               chain:apply(
                                 #'Meta' {
                                    ns = 'STATISTIC',
                                    payload = msync_msg_ns_stat:replaced()
                                   },
                                 [{msync_msg, allocate_meta_id, []},
                                  {msync_msg, generate_timestamp, []},
                                  {msync_msg, set_meta_from, [SysQueue]},
                                  {msync_msg, set_meta_to, [JID]}])],
                          queue = SysQueue
                         }
                  },
            send_pb_message(Response, Socket, JID, State);
        false ->
            skip
    end,
    msync_c2s_lib:maybe_close_session(Socket, replaced).

is_send_session_replace_notice(JID, Session) ->
    User = msync_msg:pb_jid_to_long_username(JID),
    case app_config:is_send_session_replace_notice(User) of
        true ->
            true;
        false ->
            case Session of
                undefined ->
                    Resource = JID#'JID'.client_resource,
                    case binary:split(Resource, <<"_">>) of
                                [<<"android">>,_] ->
                                    ?INFO_MSG("Ignore sending replaced message to user: ~p, reason: duplicate ets data~n", [JID]),
                                    false;
                                [<<"ios">>,_] ->
                                    ?INFO_MSG("Ignore sending replaced message to user: ~p, reason: duplicate ets data~n", [JID]),
                                    false;
                                _ ->
                                    true
                    end;
                #session{info=Info} ->
                    case proplists:get_value(from, Info, undefined) of
                        undefined ->
                            true;
                        FromSession ->
                            ToSession = Session#session{info = lists:keydelete(from, 1, Info)},
                            Resource = JID#'JID'.client_resource,
                            case binary:split(Resource, <<"_">>) of
                                [<<"android">>,_] ->
                                    ?INFO_MSG("Ignore sending replaced message to user: ~p, from session: ~p, to session:~p, reason: duplicate loginning for one device~n",
                                              [JID, FromSession, ToSession]),
                                    false;
                                [<<"ios">>,_] ->
                                    ?INFO_MSG("Ignore sending replaced message to user: ~p, from session: ~p, to session:~p, reason: duplicate loginning for one device~n",
                                              [JID, FromSession, ToSession]),
                                    false;
                                _ ->
                                    true
                            end
                    end
            end
    end.

%% send_pb_message(Msg, Socket, JID) ->
%%     send_pb_message(Msg, Socket, JID, #state{}).

send_pb_message(undefined, _Socket, _JID, _State) ->
    ok;
send_pb_message(#'MSync'{} = MSync, Socket, JID, #state{encrypt_type = EncryptType, encrypt_key = EncryptKey}) ->
    Buffer =
        case EncryptType == 'ENCRYPT_NONE' orelse MSync#'MSync'.command == 'PROVISION' of
            true ->
                case msync_c2s_lib:get_socket_prop(Socket, compression_algorithm) of
                    {ok, CompressAlgorithm} ->
                        ?DEBUG("Socket = ~p, send protobuf to ~s ~p compress = ~p ~n",[Socket, msync_msg:pb_jid_to_binary(JID), MSync, CompressAlgorithm]),
                        msync_msg:encode(MSync,CompressAlgorithm);
                    {error, not_found} ->
                        ?DEBUG("Socket = ~p, send protobuf to ~s ~p compress = ~p ~n",[Socket, msync_msg:pb_jid_to_binary(JID), MSync, not_found]),
                        msync_msg:encode(MSync,undefined)
                end;
            false ->
                    case msync_c2s_lib:get_socket_prop(Socket, compression_algorithm) of
                        {ok, CompressAlgorithm} ->
                            ?DEBUG("Socket = ~p, send protobuf to ~s ~p compress = ~p ~n",[Socket, msync_msg:pb_jid_to_binary(JID), MSync, CompressAlgorithm]),
                            msync_msg:encode(MSync,CompressAlgorithm, EncryptType, EncryptKey);
                        {error, not_found} ->
                            ?DEBUG("Socket = ~p, send protobuf to ~s ~p compress = ~p ~n",[Socket, msync_msg:pb_jid_to_binary(JID), MSync, not_found]),
                            msync_msg:encode(MSync,undefined, EncryptType, EncryptKey)
                    end
        end,
    case gen_tcp:send(Socket, Buffer) of
        ok -> ok;
        {error, closed} ->
            ?INFO_MSG("close session when peer closed, socket: ~p", [Socket]),
            msync_c2s_lib:maybe_close_session(Socket),
            ok;
        {error, Reason} ->
            %% close the socket for whatever reason
            ?INFO_MSG("close session when send data error, socket: ~p, reason: ~p",
                      [Socket, Reason]),
            msync_c2s_lib:maybe_close_session(Socket),
            ok
    end.
receive_next_packet(Socket) ->
    inet:setopts(Socket,[{active, once}]),
    undefined.


%% try_send_notice_via_jid(#'JID'{client_resource = undefined} = To, #'JID'{}= From, State) ->
%%     case msync_c2s_lib:get_resources(To) of
%%         {error, not_found} ->
%%             %% do nothing, race condition, connection closed.
%%             ok;
%%         ResourceSocketList when is_list(ResourceSocketList) ->
%%             lists:foreach(
%%               fun({Resource, Socket, _SID})->
%%                       ?DEBUG("send notice to ~p, queue=~p~n",
%%                              [
%%                               msync_msg:pb_jid_to_binary(To#'JID'{client_resource = Resource}),
%%                               msync_msg:pb_jid_to_binary(From)
%%                              ]),
%%                       try_send_notice_via_socket(Socket, From, To, State)
%%               end, ResourceSocketList)
%%     end;
try_send_notice_via_jid(#'JID'{} = To,  #'JID'{}= From, #state{socket = Socket} = State) ->
    try_send_notice_via_socket(Socket, From, To, State).

try_send_notice_via_socket(Socket, From, To, State)
  when is_port(Socket) ->
    Notice = msync_msg:notice(msync_msg:save_bw_jid(To, From)),
    try send_pb_message(Notice,Socket, To, State) of
        ok -> ok
    catch
         error:closed ->
            ?DEBUG("send notice to ~p fail, tcp socket closed~n",
                   [ msync_msg:pb_jid_to_binary(From)]),
            msync_c2s_lib:maybe_close_session(Socket)
    end.

try_send_meta_via_socket(Socket, From, To, Metas, State)
  when is_port(Socket) ->
    MSync = msync_msg:set_command(#'MSync'{}, dl, 'SYNC'),
    NewMSync =
        chain:apply(
          MSync,
          [{msync_msg, set_unread_metas, [From, Metas, undefined, To]},
           {msync_msg, set_is_last, [true]},
           {msync_msg, set_status, ['OK', undefined]}
          ]),
    try send_pb_message(NewMSync, Socket, To, State) of
        ok ->
            spawn(fun() ->
                          lists:foreach(
                            fun (Meta) ->
                                    dl_packet_filter:check(From, To, Meta)
                            end, Metas)
                  end),
            ok
    catch
         Class: Reason ->
            ?ERROR_MSG("send metas failed, to: ~p, class: ~p, reason: ~p~n",
                       [To, Class, Reason]),
            msync_c2s_lib:maybe_close_session(Socket)
    end.

traffic_limitation(Socket, DataSize ,JID) ->
    case msync_c2s_lib:get_socket_prop(Socket, shaper) of
        {ok, Shaper} ->
            Size = DataSize + 4, %% 4 bytes header
            {Shaper2, Pause} = shaper:update(Shaper, Size),
            case Pause =:= 0 of
                true ->
                    ok;
                false->
                    ?DEBUG("limit rate for ~s, pause ~p ms, shaper = ~p~n",
                           [ msync_msg:pb_jid_to_binary(JID),
                             Pause,
                             Shaper]),
                    timer:sleep(Pause)
            end,
            msync_c2s_lib:set_socket_prop(Socket, shaper, Shaper2);
        _ ->
            ignore
    end.

process_xmpp_message(From, To, Packet, State) ->
    case From of
        #'JID'{domain = <<"conference", _/binary>>} ->
            case easemob_group_cursor:is_large_group(
                   msync_msg:pb_jid_to_binary(
                     From#'JID'{client_resource = undefined})) of
                true ->
                    Type = xml:get_tag_attr_s(<<"type">>, Packet),
                    NewFrom =
                        case Type of
                            <<"groupchat">> ->
                                From;
                            _ ->
                                #'JID'{domain = <<"easemob.com">>}
                        end,
                    try_send_notice_via_jid(To, NewFrom, State);
                false ->
                    try_send_notice_via_jid(To, From, State)
            end;
        _ ->
            try_send_notice_via_jid(To, From, State)
    end.

process_xmpp_iq(From, To, #xmlel{
                              name = <<"iq">>,
                              children = [ #xmlel{ name = <<"jingle">>} | _]
                             }=XML, _State) ->
    case msync_meta_converter:from_xml(XML) of
        #'Meta'{} = Meta ->
            %% ignore the return error, because it is difficult to
            %% rebounce the message to a XMPP client.
            %% anyway, it is possible.
            msync_route:save(From, To, Meta),
            msync_route:route_online_only(From,To,Meta);
        _ ->
            ?DEBUG("ignore iq for ~p", [XML]),
            ignore_iq_packet
    end;
process_xmpp_iq(_From, To, #xmlel{
                             name = <<"iq">>,
                             children =
                                 [#xmlel{
                                     name = <<"query">>,
                                     attrs =
                                         [{<<"xmlns">>,<<"jabber:iq:roster">>}
                                          | _],
                                     children =
                                         [#xmlel{
                                             name = <<"item">>,
                                             attrs =
                                                 [{<<"subscription">>,<<"remove">>},
                                                  {<<"jid">>, Name %% <<"easemob-demo#no1_zl2@easemob.com">>
                                                  }]
                                            }]}]}, State) ->
    %% From == To, so we have to have From2 here
    From = msync_msg:parse_jid(Name),
    try_send_notice_via_jid(To, From, State);
process_xmpp_iq(From, To, _Packet, State) ->
    try_send_notice_via_jid(To,From, State).



%% XMPP client send reverse roster invitation, so that MSYNC client
%% has to response it on half of MSYNC client.
process_xmpp_presence(From, To, #xmlel{name = <<"presence">>,
                                       children = [#xmlel{name = <<"x">>,
                                                          attrs = [{<<"xmlns">>,
                                                                    <<"http://jabber.org/protocol/muc#user">>}],
                                                          children = [#xmlel{name = <<"item">>,
                                                                             attrs = Attrs,
                                                                             children = []}]},
                                                   #xmlel{name = <<"roomtype">>,
                                                          attrs = [{<<"xmlns">>,<<"easemob:x:roomtype">>},
                                                                   {<<"type">>,<<"chatroom">>}],
                                                          children = []}]}, _State) ->
    Member = proplists:get_value(<<"affiliation">>, Attrs, <<"member">>),
    ?DEBUG("asdf ~p~n",[[ok ,{ member, Member}
                         ,{ attrs, Attrs}

                        ] ]),
    case Member of
        <<"member">> ->
            translate_to_muc_chatroom(From, To, muc_presence);
        _ ->
            translate_to_muc_chatroom(From, To, muc_absence)
    end;

process_xmpp_presence(From, To, #xmlel{name = <<"presence">>,
                                       attrs = Attrs,
                                       children = [#xmlel{name = <<"status">>,attrs = [],
                                                          children = [{xmlcdata,<<"[resp:true]">>}]}]}, _State) ->
    case proplists:get_value(<<"type">>, Attrs, undefined) of
        <<"subscribe">> ->
            %% automatically subscribe reversely.
            change_roster_db_to_both(To, From),
            %% revert From and To to bound the iq
            Item = xmpp_broadcast_roster_both(To, From),
            msync_route:route_to_ejabberd(To,From,Item),
            %% IQ
            IQ = xmpp_iq_roster_both(To, From),
            msync_route:route_to_ejabberd(To,From,IQ),
            Presence = xmpp_presence_roster_both(To, From),
                        msync_route:route_to_ejabberd(To,From,Presence);
        _ ->
            ok
    end;
%% XMPP client send initial invitation, so that MID of ROSTER.Add
%% should be ready in the inbox
process_xmpp_presence(From, To, #xmlel{name = <<"presence">>}, State) ->
    try_send_notice_via_jid(To,From, State);
process_xmpp_presence(_From, _To, #xmlel{} = _Packet, _State) ->
    ignore.


xmpp_iq_roster_both(From, _To) ->
    #xmlel{
       name = <<"iq">>,
       attrs = [{<<"id">>, <<"push", (erlang:integer_to_binary(msync_uuid:generate_msg_id()))/binary>>},
                {<<"type">>, <<"set">>}
               ],
       children = [
                   #xmlel{
                      name = <<"query">>,
                      attrs = [ { <<"xmlns">>, <<"jabber:iq:roster">> }
                                %% , { <<"ver">>, get_roster_version(From)}
                              ],
                      children = [
                                  #xmlel{
                                     name = <<"item">>,
                                     attrs = [
                                              {<<"subscription">>, <<"both">>},
                                              {<<"jid">>, msync_msg:pb_jid_to_binary(msync_offline_msg:ignore_resource(From)) }]}]}]}.
xmpp_broadcast_roster_both(From, _To) ->
    {broadcast,{item,{msync_msg:pb_jid_to_long_username(From), From#'JID'.domain, <<>>},both}}.

change_roster_db_to_both(#'JID'{domain = ServerInviter} = Inviter,
                         #'JID'{domain = ServerInvitee} = Invitee) ->
    JIDInviter = msync_msg:pb_jid_to_jid(Inviter#'JID'{ client_resource = undefined}),
    JIDInvitee = msync_msg:pb_jid_to_jid(Invitee#'JID'{ client_resource = undefined}),
    UserInviter = msync_msg:pb_jid_to_long_username(Inviter),
    UserInvitee = msync_msg:pb_jid_to_long_username(Invitee),
    JIDInviter = msync_msg:pb_jid_to_jid(Inviter#'JID'{ client_resource = undefined}),
    %% automatically subscribe reversely.
    easemob_roster:process_subscription(out, UserInvitee, ServerInvitee, JIDInviter, subscribe, <<"">>),
    easemob_roster:process_subscription(in,  UserInviter, ServerInviter, JIDInvitee, subscribe, <<"[resp:true]">>),
    easemob_roster:process_subscription(out, UserInviter, ServerInviter, JIDInvitee, subscribed, <<"">>),
    easemob_roster:process_subscription(in,  UserInvitee, ServerInvitee, JIDInviter, subscribed, <<"">>).

xmpp_presence_roster_both(_From, To) ->
    #xmlel{name = <<"presence">>,
                      attrs = [{<<"type">>,<<"subscribed">>},
                               {<<"to">>, msync_msg:pb_jid_to_binary(To)}],
                      children = []}.

sort_session(Sessions) ->
    lists:sort(fun([_Socket1, SID1],
                   [_Socket2, SID2]) ->
                       SID1 > SID2
               end, Sessions).

translate_to_muc_chatroom(FromJID, ToJID, Action) ->
    Who = msync_msg:pb_jid(ToJID#'JID'.app_key,
                           FromJID#'JID'.client_resource,
                           ToJID#'JID'.domain,
                           undefined),
    MUCJID = msync_msg:pb_jid(FromJID#'JID'.app_key,
                              FromJID#'JID'.name,
                              FromJID#'JID'.domain,
                              undefined),
    IsChatRoom = true,
    MUCBody = msync_msg_ns_muc:Action(Who, MUCJID, IsChatRoom),
    Meta = msync_msg:new_meta(MUCJID, ToJID, 'MUC', MUCBody),
    %% again, it is difficult to handle the error case, so that ignore
    %% the return value of save_and_route, because it is related with
    %% XMPP and MSYNC interworking.
    msync_route:save_and_route(MUCJID, ToJID, Meta).

close_dirty_sessions(JID, Sessions, State) ->
    spawn(fun () ->
                  lists:foreach(fun([Socket, SID]) ->
                                        close_duplicate_session(JID, Socket, State),
                                        RealPid =
                                            case SID of
                                                {_, {Pid, msync}} ->
                                                    Pid;
                                                {_, {msync_c2s, Node}}->
                                                    {msync_c2s, Node};
                                                {_, Pid} ->
                                                    Pid
                                            end,
                                        RealPid ! {stop, {shutdown, close_session}}
                                end, Sessions)
          end).

-ifdef(LICENSE).

maybe_check_license(#'MSync'{
                       command = 'PROVISION',
                       payload =
                           #'Provision'{
                              os_type = 'OS_OTHER',
                              version = <<"activate license", Magic/binary>>
                             }
                      } = _Request, _JID) ->
    OldActive = ejabberd_license:is_active(),
    OldExpireDate = ejabberd_license:get_expire_date(),
    lager:debug("receive magic ~s~n", [Magic]),
    ActivationResult = ejabberd_license:check_activation(Magic),
    NewActive = ejabberd_license:is_active(),
    NewExpireDate = ejabberd_license:get_expire_date(),
    Res = encrypt_data(
            term_to_binary([{old_active, OldActive},
                            {old_expire_date,OldExpireDate},
                            {activation_result,ActivationResult},
                            {new_active,NewActive},
                            {new_expire_date,NewExpireDate}])),
    Response = msync_msg:set_command(#'MSync'{}, dl, 'PROVISION'),
    {ok, msync_msg:set_status(Response, 'OK', Res)};
maybe_check_license(Request, _JID) ->
    case ejabberd_license:is_active() of
        true ->
            continue;
        false ->
            Command = msync_msg:get_command(Request),
            Response = msync_msg:set_command(#'MSync'{}, dl, Command),
            {ok, msync_msg:set_status(Response, 'FAIL', <<"license is expired">>)}
    end.
encrypt_data(Data) ->
    PubKey = ejabberd_license_data:data(),
    DesKey = list_to_binary(lists:map(fun(_N) -> random:uniform(255) end, lists:seq(1,16))),
    EDesKey = public_key:encrypt_public(DesKey, PubKey),
    {_NewState, EData} = crypto:stream_encrypt(crypto:stream_init(rc4, DesKey), Data),
    base64:encode(term_to_binary({EDesKey, EData})).
-else.
maybe_check_license(_Request,_Socket) ->
    continue.
-endif.
