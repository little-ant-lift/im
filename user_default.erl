-module(user_default).
-compile([export_all]).
-include("pb_msync.hrl").
-include("logger.hrl").
-lager_print_records_flag(1).
-include("xml.hrl").


table(T) ->
    mnesia:transaction(fun () -> mnesia:select(T,[{'_',[],['$_']}]) end).
p(Pid) ->
    case (catch is_process_alive(Pid)) of
        true ->
            io:format("~p~n",
                      [[erlang:process_info(Pid), proc_lib:translate_initial_call(Pid)]]);
        Msg -> io:format("pupu: ~p~n", [Msg])
    end.
tpl(Module) ->
    dbg:tpl(Module,[{'$1',[],[{return_trace}]}]).
tpl(Module,Fun) ->
    dbg:tpl(Module,Fun,[{'$1',[],[{return_trace}]}]).
show_path() ->
    Root = code:root_dir(),
    lists:foreach(fun(P) ->
                          case string:str(P, Root) of
                              1 -> ok;
                              _ -> io:format("~p~n", [P])
                          end
                  end, code:get_path()).
s(S)
  when is_binary(S); is_list(S) ->
    io:format("~s~n",[iolist_to_binary(S)]);
s(X) ->
    io:format("~p~n",[X]).
%% r1() ->
%%     M1 = #'PBMessage'{
%%            message_id = "1445432345376",
%%            from =
%%                #'PBJID'{
%%                   app_key = "easemob-demo#chatdemoui",
%%                   name = "nc3",
%%                   domain = "easemob.com",client_resource = "mobile",
%%                   server_resource = undefined},
%%            to =
%%                #'PBJID'{
%%                   app_key = "easemob-demo#chatdemoui",name = "no2",
%%                   domain = "easemob.com",client_resource = undefined,
%%                   server_resource = undefined},
%%            timestamp = 1445432345376,type = 'SINGLE_CHAT',
%%            body =
%%                #'PBMessageBody'{
%%                   from = #'PBJID'{
%%                             app_key = "easemob-demo#chatdemoui",
%%                             name = "inner_from",
%%                             domain = "easemob.com",client_resource = "mobile",
%%                             server_resource = undefined},
%%                   to = #'PBJID'{
%%                           app_key = "easemob-demo#chatdemoui",
%%                           name = "inner_to",
%%                           domain = "easemob.com",client_resource = "mobile",
%%                           server_resource = undefined},
%%                   contents =
%%                       [#'PBMessageBody.Content'{
%%                           type = 'TEXT',text = <<"10">>,
%%                           latitude = 100.0,
%%                           longitude = 101.0,
%%                           address = <<"addr">>,
%%                           displayName = <<"displayName">>,
%%                           remotePath = <<"url">>,
%%                           secretKey = <<"secret">>,
%%                           fileLength = 1960,
%%                           action = <<"action">>,
%%                           params = [#'PBKeyValue'{ key = <<"k2">> , type = 'INT', value = { varint_value , 111} },
%%                                     #'PBKeyValue'{ key = <<"k1">> , type = 'INT', value = { varint_value , 112} }],
%%                           duration = 1001,
%%                           size = #'PBMessageBody.Content.Size'{width = 600, height = 400 },
%%                           thumbnailRemotePath = <<"thumbnailRemotePath">>,
%%                           thumbnailSecretKey = <<"thumbnailSecretKey">>,
%%                           thumbnailDisplayName = <<"thumbnailDisplayName">>,
%%                           thumbnailFileLength = 1002,
%%                           thumbnailSize = #'PBMessageBody.Content.Size'{width = 600, height = 400 }}],
%%                   ext = [#'PBKeyValue'{ key = <<"k4">> , type = 'INT', value = { varint_value , 111} },
%%                          #'PBKeyValue'{ key = <<"k3">> , type = 'INT', value = { varint_value , 112} }]},
%%             ack = undefined},
%%     A = (msync_message_converter:to_xml(M1)),
%%     M2 = msync_message_converter:from_xml(A),
%%     M1 = M2.
%% Children = A#xmlel.children,
%% Body = hd(Children),
%% [{xmlcdata, Text}] = Body#xmlel.children,
%% A.

%% {'PBMessage',<<"1445432345376">>,
%%     {'PBJID',"easemob-demo#chatdemoui","nc3","easemob.com","mobile",undefined},
%%     {'PBJID',"easemob-demo#chatdemoui","no2","easemob.com",undefined,
%%         undefined},
%%     1445432345376,'SINGLE_CHAT',
%%     {'PBMessageBody',
%%         {'PBJID',"easemob-demo#chatdemoui","no","easemob.com","mobile",
%%             undefined},
%%         undefined,
%%         [{'PBMessageBody.Content','TEXT',<<"10">>,100.0,101.0,<<"addr">>,
%%              <<"displayName">>,<<"url">>,<<"secret">>,1960,<<"action">>,
%%              #{<<"k1">> => 111,<<"k2">> => 112},
%%              1001,
%%              #{<<"height">> => 400,<<"width">> => 600},
%%              <<"thumbnailRemotePath">>,<<"thumbnailSecretKey">>,
%%              <<"thumbnailDisplayName">>,1002,
%%              #{<<"thumbHeight">> => 400,<<"thumbWidth">> => 600}}],
%%         [{'PBKeyValue',<<"k4">>,'INT',{varint_value,112}},
%%          {'PBKeyValue',<<"k3">>,'INT',{varint_value,111}}]},
%%     undefined}


r() ->
    {ok, Client} = msync_client:start_link(#{}),
    msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no guid">>}}},
    timer:sleep(10),
    ok = msync_client:expect_message(Client,Msg),
    msync_client:stop(Client).
r2() ->
    ?INFO_MSG("~p~n",[#'MSync'{}]).


local1() ->
    application:load(msync),
    {ok, Client} = msync_client:start_link(#{}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    Other = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    erlang:put(other, Other),
    erlang:put(me, JID),
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    erlang:put(client, Client),
    Client.
local2() ->
    application:load(msync),
    {ok, Client} = msync_client:start_link(#{}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    Other = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    erlang:put(other, Other),
    erlang:put(me, JID),
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"secret">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    erlang:put(client, Client),
    Client.
remote_zhaoyun_1() ->
    application:load(msync),
    {ok, Client} = msync_client:start_link(#{host => "172.16.0.31"}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    Other = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    erlang:put(other, Other),
    erlang:put(me, JID),
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"secret">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    erlang:put(client, Client),
    Client.
remote_zhaoyun_2() ->
    application:load(msync),
    {ok, Client} = msync_client:start_link(#{host => "172.16.0.31"}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    Other = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    erlang:put(other, Other),
    erlang:put(me, JID),
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"secret">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    erlang:put(client, Client),
    Client.

remote1() ->
    application:load(msync),
    {ok, Client} = msync_client:start_link(#{host => "120.26.12.158"}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    Other = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    erlang:put(other, Other),
    erlang:put(me, JID),
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"secret">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    erlang:put(client, Client),
    Client.
remote2() ->
    application:load(msync),
    {ok, Client} = msync_client:start_link(#{host => "120.26.12.158"}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    Other = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    erlang:put(other, Other),
    erlang:put(me, JID),
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"secret">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    erlang:put(client, Client),
    Client.
logout() ->
    msync_client:stop(erlang:get(client)).

sync_unread() ->
    msync_client:sync_unread(erlang:get(client)).

a_meta(Text1) ->
    Text =  list_to_binary(Text1),
    #'Meta'{
       id = <<"a_id">>,
       to = erlang:get(other),
       ns = 'CHAT',
       payload = test_ns_chat:text(jid("user1"),jid("user2"), Text)
      }.
a_xml(Text1) ->
    msync_meta_converter:to_xml(a_meta(Text1)).


chat(Text1) ->
    Text =  list_to_binary(Text1),
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = (erlang:get(other)), %% #'JID'{app_key = undefined, domain = undefined},
                        ns = 'CHAT',
                        payload = test_ns_chat:text(erlang:get(me), erlang:get(other), Text)
                       }
                },
    Client = erlang:get(client),
    ok = msync_client:set_command(Client,'SYNC'),
    ok = msync_client:send_payload(Client, Payload).
gchat(Text1) ->
    Text =  list_to_binary(Text1),
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = (erlang:get(other)), %% #'JID'{app_key = undefined, domain = undefined},
                        ns = 'CHAT',
                        payload = test_ns_chat:gtext(erlang:get(me), erlang:get(other), Text)
                       }
                },
    Client = erlang:get(client),
    ok = msync_client:set_command(Client,'SYNC'),
    ok = msync_client:send_payload(Client, Payload).

chat(Text1, CompressAlgorithm) ->
    Text =  list_to_binary(Text1),
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = erlang:get(other),
                        ns = 'CHAT',
                        payload = test_ns_chat:text(erlang:get(me), erlang:get(other), Text)
                       }
                },
    Client = erlang:get(client),
    ok = msync_client:set_command(Client,'SYNC'),
    ok = msync_client:send_payload(Client, Payload, CompressAlgorithm).

set_peer(Name)
  when is_list(Name) ->
    set_name(other, erlang:list_to_binary(Name)).
set_peer(Name, Domain)
  when is_list(Name),
       is_list(Domain)->
    set_name(other,
             erlang:list_to_binary(Name),
             erlang:list_to_binary(Domain)).

set_me(Name)
  when is_list(Name) ->
    set_name(me,erlang:list_to_binary(Name)).

set_name(Who,Name) ->
    JID = erlang:get(Who),
    erlang:put(Who, JID#'JID'{ name = Name }).
set_name(Who, Name, Domain) ->
    JID = erlang:get(Who),
    erlang:put(Who, JID#'JID' { name = Name , domain = Domain}).

%% "120.26.12.158"

login(Name, Host, Pass) ->
    application:load(msync),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = list_to_binary(Name),
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    Other = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"user2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    erlang:put(other, Other),
    erlang:put(me, JID),
    set_me(Name),
    {ok, Client} = msync_client:start_link(#{host => Host}),
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, list_to_binary(Pass)),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    erlang:put(client, Client),
    Client.

create() ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc:create_group()
                       }
                },
    msync_client:send_payload(Client, Payload).

destroy(Group0) ->
    Group = list_to_binary(Group0),
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc:destroy_group(Group)
                       }
                },
    msync_client:send_payload(Client, Payload).
join(Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    Who = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc:join_group(Who,list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).
leave(Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    Who = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc:leave_group(Who,list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).
alive() ->
    case erlang:is_process_alive(get(client)) of
        true ->
            msync_msg:pb_jid_to_binary(get(me));
        false ->
            false
    end.
muc_apply(Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    Who = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc:apply_group(Who,list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

muc_apply_accept(Group) ->
    muc_apply_response(Group,apply_accept_group).
muc_apply_decline(Group) ->
    muc_apply_response(Group,apply_decline_group).
muc_apply_response(Group,F) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:F(From, list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

muc_invite(Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% Who = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc:invite(list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

muc_invite_accept(Group) ->
    muc_invite_response(Group,invite_accept_group).
muc_invite_decline(Group) ->
    muc_invite_response(Group,invite_decline_group).
muc_invite_response(Group,F) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:F(list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

kick(User, Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:kick(list_to_binary(User),list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

ban(User, Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:ban(list_to_binary(User),list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

allow(User, Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:allow(list_to_binary(User),list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).
block(User, Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:block(list_to_binary(User),list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

unblock(User, Group) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:unblock(list_to_binary(User),list_to_binary(Group))
                       }
                },
    msync_client:send_payload(Client, Payload).

update(Group0, Key, Value0) ->
    Group = list_to_binary(Group0),
    Value = if is_binary(Value0) -> Value0;
               is_list(Value0) -> list_to_binary(Value0);
               true -> Value0
            end,
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    %% From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload =
                            test_ns_muc:update(Group,Key, Value)
                       }
                },
    msync_client:send_payload(Client, Payload).


roster_invite(User0) ->
    User = list_to_binary(User0),
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload =
                            test_ns_roster:invite(From,User)
                       }
                },
    msync_client:send_payload(Client, Payload).

roster_accept(User) ->
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload =
                            test_ns_roster:accept(jid(User))
                       }
                },
    msync_client:send_payload(Client, Payload).

roster_ban(User0) ->
    User = list_to_binary(User0),
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload =
                            test_ns_roster:ban(User,From)
                       }
                },
    msync_client:send_payload(Client, Payload).

roster_allow(User0) ->
    User = list_to_binary(User0),
    Client = get(client),
    ClientId = erlang:abs(erlang:unique_integer()),
    From = get(me),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload =
                            test_ns_roster:allow(User,From)
                       }
                },
    msync_client:send_payload(Client, Payload).


clear() ->
    UserInviter = <<"easemob-demo#chatdemoui_user1">>,
    UserInvitee = <<"easemob-demo#chatdemoui_user2">>,
    JIDInviter = <<"easemob-demo#chatdemoui_user1@easemob.com">>,
    JIDInvitee = <<"easemob-demo#chatdemoui_user2@easemob.com">>,
    easemob_roster:del_roster_by_jid(UserInviter, UserInvitee, JIDInviter, JIDInvitee).



run() ->
    RetList =  [{ok,<<"OK">>},{error, no_connection},
                {ok,<<"0">>},{ok,<<"2">>},{ok,<<"1">>},{ok,<<"1">>},{ok,<<"1">>},{ok,<<"1">>}],
    P = 1,
    lists:foldl(
      fun(Ret, AccRet) ->
              case Ret of
                  {error, no_connection} ->
                      ?ERROR_MSG("error to exec group redis operation:~p reason:no_connection", [P]),
                      {error, no_connection};
                  {error, Reason} ->
                      ?ERROR_MSG("error to exec group redis operation:~p reason:~p", [P, Reason]),
                      {error, Reason};
                  {ok, _} ->
                      AccRet
              end
      end,ok,
      RetList).

sessions() ->
    ets:tab2list(msync_c2s_tbl_pb_jid).
group() ->
    group("1234567").
group(Group0) ->
    GroupId = <<"easemob-demo#chatdemoui_", (list_to_binary(Group0))/binary >>,
    msync_SUITE:verify_group(GroupId),
    Client = cuesport:get_worker(muc),
    Q = [hgetall, <<"im:", GroupId/binary >> ],
    R =  eredis:q(Client, Q),
    io:format("group detail ~p ~n",[R]).
mute_list() ->
    easemob_muc:read_group_mute_list(<<"easemob-demo#chatdemoui_1234567">>).

mute_list(Group0) ->
    Group = <<"easemob-demo#chatdemoui_", (list_to_binary(Group0))/binary >>,
    easemob_muc:read_group_mute_list(Group).

outcast_list() ->
    easemob_muc:read_group_mute_list(<<"easemob-demo#chatdemoui_1234567">>).

outcast_list(Group0) ->
    Group = <<"easemob-demo#chatdemoui_", (list_to_binary(Group0))/binary >>,
    easemob_muc:read_group_outcast(Group).

app_groups() ->
    Q = [smembers, <<"im:easemob-demo#chatdemoui:groups">> ],
    Client = cuesport:get_worker(muc),
    eredis:q(Client, Q).


get_session_socket(User, Resource) ->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = list_to_binary(User),
             domain = <<"easemob.com">>,
             client_resource = list_to_binary(Resource)
            },
    msync_c2s_lib:get_pb_jid_prop(JID, socket).

get_session(User) ->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = list_to_binary(User),
             domain = <<"easemob.com">>
            },
    Resources = msync_c2s_lib:get_resources(JID),
    Results =
        case Resources of
            {error, not_found} -> not_found;
            _ ->
                lists:map(
                  fun({R,Socket,_}) ->
                          NewJID = JID#'JID'{
                                     client_resource = R
                                    },
                          {ok, Socket} = msync_c2s_lib:get_pb_jid_prop(NewJID, socket),
                          SID = msync_c2s_lib:get_pb_jid_prop(NewJID, sid),
                          {NewJID, Socket, SID}
                  end, Resources)
        end,
    EjabberdResources = ejabberd_bridge:rpc(ejabberd_sm,get_user_resources, [msync_msg:pb_jid_to_long_username(JID), JID#'JID'.domain]),
    EjabberdResults =
        lists:map(
          fun(R) ->
                  ejabberd_bridge:rpc(ejabberd_sm,get_session, [ msync_msg:pb_jid_to_long_username(JID), JID#'JID'.domain, R])
          end, EjabberdResources),
    {Results, EjabberdResults}.



proc_attrs(binary_memory, Pid) ->
    case process_info(Pid, [binary, registered_name,
                            current_function, initial_call]) of
        [{_, Bins}, {registered_name,Name}, Init, Cur] ->
            {ok, {Pid, binary_memory(Bins), [Name || is_atom(Name)]++[Init, Cur]}};
        undefined ->
            {error, undefined}
    end.
binary_memory(Bins) ->
    lists:foldl(fun({_,Mem,_}, Tot) -> Mem+Tot end, 0, Bins).



most_binary_size(N) ->
    lists:sublist(
      lists:usort(
        fun({K1,V1},{K2,V2}) ->
                {V1,K1} >= {V2,K2} end,
        [
         try
             %% {_, BinaryList} = erlang:process_info(Pid, binary),
             {ok, { _, Value, _ } } = proc_attrs(binary_memory, Pid),
             %% length(BinaryList)
             {Pid, Value}
         catch a -> 0 end
         || Pid <- processes()]),
      N).

most_leak(N) ->
    lists:sublist(
      lists:usort(
        fun({K1,V1},{K2,V2}) ->
                {V1,K1} =< {V2,K2} end,
        [try
             {_,Pre} = erlang:process_info(Pid, binary),
             erlang:garbage_collect(Pid),
             {_,Post} = erlang:process_info(Pid, binary),
             {Pid, length(Post)-length(Pre)}
         catch
             _:_ ->
                 {Pid, 0}
         end || Pid <- processes()]),
      N).
mem() ->
    [{K, V/1024/1024} || {K,V} <- erlang:memory() ].


analyse_binary() ->
    try
        BinLists = lists:map(fun analyse_binary_1/1, processes()),
        lists:foldl(
          fun({Pid, BinList}, Acc) ->
                  lists:foldl(
                    fun({Ptr, Size, Refcount}, Acc2) ->
                            OldList = maps:get(Ptr,Acc2,[]),
                            NewList = [{Size, Refcount, Pid} | OldList],
                            Acc2#{ Ptr => NewList }
                    end, Acc, BinList)
          end,#{}, BinLists)
    catch
        W:T ->
            io:format("~p:~p", [W,T])
    end.
analyse_binary_1(Pid) ->
    {binary,  BinList } = process_info(Pid, binary),
    {Pid, BinList }.

anaylyse_process_links(Pid) ->
    anaylyse_process_links_1(Pid, #{}).

anaylyse_process_links_1(Pid, M) ->
    {links, Links} = process_info(Pid,links),
    lists:foldl(
      fun(L, Acc) ->
              case maps:get(L, Acc, undefined) of
                  undefined ->
                      try
                          Trace = erlang:process_info(L, current_stacktrace),
                          anaylyse_process_links_1(L, Acc#{ L => Trace })
                      catch
                          W:T ->
                              io:format("~p:~p ~p~n",[W,T, L]),
                              Acc
                      end;
                  _ ->
                      Acc
              end
      end, M, Links).

info_alloc() ->
    [{{A, N}, Data} ||
        A <- [temp_alloc, eheap_alloc, binary_alloc, ets_alloc,
              driver_alloc, sl_alloc, ll_alloc, fix_alloc, std_alloc],
        {instance, N, Data} <- erlang:system_info({allocator,A})
        ].

before() ->
    A = << 16#a,16#e1,16#1,16#a,16#d,16#31,16#34,16#34,16#38,16#30,16#31,16#38,16#38,16#30,16#34,16#30,16#38,16#35,16#12,16#33,16#a,16#17,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2d,16#64,16#65,16#6d,16#6f,16#23,16#63,16#68,16#61,16#74,16#64,16#65,16#6d,16#6f,16#75,16#69,16#12,16#3,16#6e,16#63,16#33,16#1a,16#b,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2e,16#63,16#6f,16#6d,16#22,16#6,16#6d,16#6f,16#62,16#69,16#6c,16#65,16#1a,16#2b,16#a,16#17,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2d,16#64,16#65,16#6d,16#6f,16#23,16#63,16#68,16#61,16#74,16#64,16#65,16#6d,16#6f,16#75,16#69,16#12,16#3,16#6e,16#63,16#31,16#1a,16#b,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2e,16#63,16#6f,16#6d,16#28,16#1,16#32,16#6c,16#8,16#1,16#12,16#2b,16#a,16#17,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2d,16#64,16#65,16#6d,16#6f,16#23,16#63,16#68,16#61,16#74,16#64,16#65,16#6d,16#6f,16#75,16#69,16#12,16#3,16#6e,16#63,16#33,16#1a,16#b,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2e,16#63,16#6f,16#6d,16#1a,16#2b,16#a,16#17,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2d,16#64,16#65,16#6d,16#6f,16#23,16#63,16#68,16#61,16#74,16#64,16#65,16#6d,16#6f,16#75,16#69,16#12,16#3,16#6e,16#63,16#31,16#1a,16#b,16#65,16#61,16#73,16#65,16#6d,16#6f,16#62,16#2e,16#63,16#6f,16#6d,16#22,16#e,16#8,0,16#12,16#a,16#31,16#32,16#33,16#34,16#35,16#36,16#37,16#38,16#39,16#30 >>,
    A.

after2() ->
    <<16#78,16#da,16#e2,16#7a,16#c8,16#c8,16#c5,16#6b,16#68,16#62,16#62,16#61,16#60,16#68,16#61,16#61,16#60,16#62,16#60,16#61,16#2a,16#64,16#cc,16#25,16#9e,16#9a,16#58,16#9c,16#9a,16#9b,16#9f,16#a4,16#9b,16#2,16#24,16#95,16#93,16#33,16#12,16#4b,16#40,16#8c,16#d2,16#4c,16#21,16#e6,16#bc,16#64,16#63,16#29,16#6e,16#a8,16#ac,16#5e,16#72,16#7e,16#ae,16#12,16#1b,16#90,16#91,16#99,16#93,16#2a,16#a5,16#8d,16#57,16#93,16#21,16#8a,16#26,16#d,16#46,16#a3,16#1c,16#e,16#46,16#21,16#6d,16#12,16#ec,16#21,16#c9,16#7c,16#25,16#3e,16#e,16#6,16#21,16#2e,16#43,16#23,16#63,16#13,16#53,16#33,16#73,16#b,16#4b,16#3,0,0,0,0,16#ff,16#ff>>.

after3() ->
    <<120,218,226,122,200,200,197,107,104,98,98,97,96,104,97,97,96,98,96,97,42,100,204,37,158,154,88,156,154,155,159,164,155,2,36,149,147,51,18,75,64,140,210,76,33,230,188,100,99,41,110,168,172,94,114,126,174,18,27,144,145,153,147,42,165,141,87,147,33,138,38,13,70,163,28,14,70,33,109,18,236,33,201,124,37,62,14,6,33,46,67,35,99,19,83,51,115,11,75,3,0,0,0,0,255,255>>.

after4() ->
    <<120,156,5,193,1,1,0,48,8,195,48,75,116,27,7,252,27,123,130,156,126,179,71,1,194,132,230,49,44,167,18,146,172,168,245,52,90,157,203,88,182,227,246,243,120,125,169,16,197,73,58,47,147,205,117,125,72,89,18,91>>.

test_zlib(Data) ->
    Z = zlib:open(),
    Level = 9,
    Method = deflated,
    WindowBits = 15,
    MemLevel = 8,
    Strategy = default,
    zlib:deflateInit(Z, Level, Method, WindowBits, MemLevel, Strategy),
    B1 = zlib:deflate(Z,Data),
    B2 = zlib:deflate(Z,<<>>,finish),
    ok = zlib:deflateEnd(Z),
    ok = zlib:close(Z),
    list_to_binary([B1, B2]).


test_unzip(Data) ->
    Z = zlib:open(),
    ok = zlib:inflateInit(Z),
    B = zlib:inflateChunk(Z,Data),
    ok = zlib:close(Z),
    B.


jid(User) ->
    _JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = list_to_binary(User),
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            }.
gjid(G) ->
    _JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = list_to_binary(G),
             domain = <<"conference.easemob.com">>,
             client_resource = undefined
            }.
get_unread_numbers(User) ->
    JID = jid(User),
    msync_offline_msg:get_unread_numbers(JID).

get_unread_list(User, From) ->
    Owner = jid(User),
    Queue = From,
    Key = undefined,
    N = 100,
    Key2 =
        case Key of
            undefined -> undefined;
            _ -> integer_to_binary(Key)
        end,
    {Metas1,NextKeyBinary} =
        message_store:get_unread_messages(
          msync_msg:pb_jid_to_binary(ignore_resource(Queue)), % From
          msync_msg:pb_jid_to_binary(ignore_resource(Owner)), % To
          Owner#'JID'.client_resource,
          Key2,
          N),
    NextKey =
        case NextKeyBinary of
            undefined -> undefined;
            _ -> binary_to_integer(NextKeyBinary)
        end,
    ?DEBUG("get unread messages:~n"
           "\t Owner = ~p~n"
           "\t Queue = ~p~n"
           "\t Key = ~p~n"
           "\t N = ~p~n"
           "\t Metas1 = ~p~n"
           "\t NextKey = ~p~n",
           [Owner, Queue, Key, N, Metas1, NextKey]),
    { lists:filtermap(
        fun(M) ->
                try
                    ?DEBUG("M is ~p~n",[M]),
                    {true, msync_msg:save_bw_meta(msync_msg:decode_meta(M), Owner)}
                catch
                    error:{case_clause,Reason} ->
                        ?ERROR_MSG("lost message.\n"
                                   "\tOwner = ~p\n"
                                   "\tMeta = ~p\n"
                                   "\tReason = ~p\n",
                                   [Owner, M, Reason]),
                        false
                end
        end, Metas1), NextKey }.


get_groups() ->
    Worker = cuesport:get_worker(muc),
    eredis:q(Worker, [smembers, <<"im:easemob-demo#chatdemoui:groups">>]).
get_group(Group0) ->
    Group = list_to_binary(Group0),
    Worker = cuesport:get_worker(muc),
    eredis:q(Worker, [hgetall, <<"im:easemob-demo#chatdemoui_", Group/binary>>]).
get_group_member(Group0) ->
    Group = list_to_binary(Group0),
    Worker = cuesport:get_worker(muc),
    eredis:q(Worker, [smembers, <<"im:easemob-demo#chatdemoui_", Group/binary, ":affiliations">>]).
whoami() ->
    get(me).


get_raw_message(MID0) ->
    MID = list_to_binary(MID0),
    Worker = cuesport:get_worker(muc),
    case eredis:q(Worker, [get, <<"im:message:", MID/binary>>]) of
        {ok, B} ->
            B;
        Else -> Else
    end.


ignore_resource(#'JID'{} = JID) ->
    JID#'JID'{
      %% offline database does not includes resources
      client_resource = undefined
     }.


get_roster(JID) ->
    easemob_roster:get_roster(msync_msg:pb_jid_to_long_username(JID), JID#'JID'.domain).



test(B) ->
    ClientId = integer_to_binary(erlang:abs(erlang:unique_integer())),
    easemob_message_body:write_message(ClientId, B),
    B = easemob_message_body:read_message_cache(ClientId),
    B = easemob_message_body:read_message_odbc(ClientId).

open_session() ->
    JID = jid("c5"),
    Socket = wired_socket,
    SID = {os:timestamp(), self() },
    put(sid, SID),
    User = msync_msg:pb_jid_to_long_username(JID),
    Conn = msync_c2s,
    Info = [{ip, "0.0.0.0"},
            {conn, Conn},
            {socket, Socket},
            {auth_module, undefined}],
    Resource = <<"mobile">>,
    Server = <<"easemob.com">>,
    ejabberd_sm:open_session(SID, User, Server, Resource, Info).

close_session() ->
    JID = jid("c5"),
    SID = get(sid),
    User = msync_msg:pb_jid_to_long_username(JID),
    Resource = <<"mobile">>,
    Server = <<"easemob.com">>,
    ejabberd_sm:close_session(SID, User, Server, Resource).
