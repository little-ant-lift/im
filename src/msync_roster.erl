-module(msync_roster).

-export([handle/2,
         handle_sync/3
        ]).

-include("pb_rosterbody.hrl").
-include("logger.hrl").

handle(JID, #'RosterBody'{from = undefined} = RosterBody) ->
    handle(JID, RosterBody#'RosterBody'{from = JID});
handle(JID, #'RosterBody'{from = From, to = InviteList}
       = RosterBody ) ->
    NewInviteList = lists:map(
                      fun(To) ->
                              maybe_merge_to(From,To)
                      end, InviteList),
    ?DEBUG("~s:~p: [~p] -- ~n~p~n",[?FILE, ?LINE, ?MODULE, {
                                                     NewInviteList,
                                                     InviteList
                                                  }]),
    Result = handle_1(JID,  RosterBody#'RosterBody'{to = NewInviteList}),
    case Result of
        ok ->
            maybe_produce_roster_privacy_incr(
              JID, RosterBody#'RosterBody'{to = NewInviteList});
        _ ->
            ignore
    end,
    Result.

handle_sync(User, Type, RosterList) ->
    UserJID = msync_msg:parse_jid(User),
    RosterJIDList = [msync_msg:parse_jid(R) || R <- RosterList],
    handle_1(UserJID, #'RosterBody'{
                         operation = Type,
                         from = UserJID,
                         to = RosterJIDList
                        }),
    ok.

handle_1(_JID, #'RosterBody'{
               operation = 'ADD',
               from = From,
               to = InviteList,
               reason = Reason
              }) ->
    invite(From, InviteList, Reason);
handle_1(_JID, #'RosterBody'{
                operation = 'ACCEPT',
                from = Invitee,
                to = [Inviter]
               } = _RosterBody) ->
    accept(Inviter, Invitee);
handle_1(_JID, #'RosterBody'{
                operation = 'DECLINE',
                from = Invitee,
                to = [Inviter]
               } = _RosterBody) ->
    reject(Inviter, Invitee);
handle_1(_JID, #'RosterBody'{
                operation = 'REMOVE',
                from = From,
                to = ToList
               } = _RosterBody) ->
    lists:foreach(fun(To) ->
                          remove(From,To)
                  end, ToList);
handle_1(JID, #'RosterBody'{
                operation = 'BAN',
                from = From,
                to = ToList
               } = _RosterBody) ->
    From1 =
        chain:apply(
          From,
          [ { msync_msg, pb_jid_with_default_appkey, [JID] },
            { msync_msg, pb_jid_with_default_name, [JID] } ]),
    ToList1 =
        lists:map(
          fun(To) ->
                  chain:apply(
                    To,
                    [ { msync_msg, pb_jid_with_default_appkey, [From] },
                      { msync_msg, pb_jid_with_default_name, [From] } ])
          end, ToList),
    do_ban(From1,ToList1);
handle_1(JID, #'RosterBody'{
                operation = 'ALLOW',
                from = From,
                to = ToList
               } = _RosterBody) ->
    From1 =
        chain:apply(
          From,
          [ { msync_msg, pb_jid_with_default_appkey, [JID] },
            { msync_msg, pb_jid_with_default_name, [JID] } ]),
    ToList1 =
        lists:map(
          fun(To) ->
                  chain:apply(
                    To,
                    [ { msync_msg, pb_jid_with_default_appkey, [From] },
                      { msync_msg, pb_jid_with_default_name, [From] } ])
          end, ToList),
    do_allow(From1,ToList1);
handle_1(_JID, #'RosterBody'{} = RosterBody) ->
    ?ERROR_MSG("~p~n",[RosterBody]),
    {error, <<"unknown roster operation">>}.

invite(From, InviteList, undefined = _Reason) ->
    invite(From, InviteList, <<"">>);
invite(From, InviteList, Reason) ->
    lists:foreach(
      fun(To) ->
              try invite_1(From,To,Reason)
              catch
                  Type:Error ->
                      ?ERROR_MSG("roster invite failed. ~p:~p, From=~p, To=~p, Reason=~p~n"
                                "**stacktrace ~p~n",
                                 [Type, Error,
                                  msync_msg:pb_jid_to_binary(From),
                                  msync_msg:pb_jid_to_binary(To),
                                  Reason,
                                  erlang:get_stacktrace()])
              end
      end, InviteList).

invite_1(#'JID'{domain = Server1} = From,
         #'JID'{domain = Server2} = To,
         Reason) ->
    % User = <<"easemob-demo#chatdemoui_a1">>
    ?DEBUG("roster:invite: ~p invite ~p reason=~p~n",
           [msync_msg:pb_jid_to_binary(From),
            msync_msg:pb_jid_to_binary(To),
            Reason]),
    JID1 = msync_msg:pb_jid_to_jid(From#'JID'{ client_resource = undefined}),
    JID2 = msync_msg:pb_jid_to_jid(To#'JID'{ client_resource = undefined}),
    User1 = msync_msg:pb_jid_to_long_username(From),
    User2 = msync_msg:pb_jid_to_long_username(To),
    Type = subscribe,
    %% FIXME: the two transaction should be combined into on transaction.
    %% if the data already exists, it returns false, I don't know why
    %% yet, so ignore such error
    easemob_roster:process_subscription(out, User1, Server1, JID2, Type, Reason),
    easemob_roster:process_subscription(in,  User2, Server2, JID1, Type, Reason),
    Payload = #'RosterBody'{
                 operation = 'ADD',
                 from = From,
                 to = [To],
                 reason = Reason
                },
    SystemQueue = From#'JID'{
                    app_key = undefined, name = undefined,
                    client_resource = undefined
                   },
    msync_log:on_roster_operation(From, To, apply),
    Meta = msync_msg:new_meta(SystemQueue, To, 'ROSTER', Payload),
    do_route(SystemQueue, To, Meta).

accept(#'JID'{domain = ServerInviter} = Inviter,
       #'JID'{domain = ServerInvitee} = Invitee) ->
    ?DEBUG("roster:accept: ~p accept ~p~n",
           [msync_msg:pb_jid_to_binary(Invitee),
            msync_msg:pb_jid_to_binary(Inviter)]),
    JIDInviter = msync_msg:pb_jid_to_jid(Inviter#'JID'{ client_resource = undefined}),
    JIDInvitee = msync_msg:pb_jid_to_jid(Invitee#'JID'{ client_resource = undefined}),
    UserInviter = msync_msg:pb_jid_to_long_username(Inviter),
    UserInvitee = msync_msg:pb_jid_to_long_username(Invitee),
    %% FIXME: the two transaction should be combined into on transaction.
    easemob_roster:process_subscription(out, UserInvitee, ServerInvitee, JIDInviter, subscribed, <<"">>),
    %% if the data already exists, it returns false, I don't know why
    %% yet, so ignore such error
    easemob_roster:process_subscription(in,  UserInviter, ServerInviter, JIDInvitee, subscribed, <<"">>),

    %% automatically subscribe reversely.
    easemob_roster:process_subscription(out, UserInvitee, ServerInvitee, JIDInviter, subscribe, <<"">>),
    easemob_roster:process_subscription(in,  UserInviter, ServerInviter, JIDInvitee, subscribe, <<"[resp:true]">>),
    easemob_roster:process_subscription(out, UserInviter, ServerInviter, JIDInvitee, subscribed, <<"">>),
    easemob_roster:process_subscription(in,  UserInvitee, ServerInvitee, JIDInviter, subscribed, <<"">>),
    msync_log:on_roster_operation(Invitee, Inviter, accept),
    send_accept_feedback('REMOTE_ACCEPT', Inviter,Invitee,Inviter),
    InviteeName = msync_msg:pb_jid_to_long_username(Invitee),
    Version = easemob_roster:get_roster_version(InviteeName),
    msync_multi_devices:send_multi_devices_roster_msg(Invitee, Inviter, 'ACCEPT', Version),
    send_accept_feedback('ACCEPT',Invitee,Inviter,Invitee).

send_accept_feedback(Op, Dest,A,B) ->
    DestName = msync_msg:pb_jid_to_long_username(Dest),
    Version = easemob_roster:get_roster_version(DestName),
    Payload = #'RosterBody'{
                 operation = Op,
                 from = A,
                 to = [B],
                 roster_ver = Version
                },
    SystemQueue = Dest#'JID'{
                    app_key = undefined, name = undefined,
                    client_resource = undefined
                   },
    Meta = msync_msg:new_meta(SystemQueue, Dest, 'ROSTER', Payload),
    do_route(SystemQueue, Dest, Meta).

remove(From,To) ->
    UserFrom = msync_msg:pb_jid_to_long_username(From),
    UserTo = msync_msg:pb_jid_to_long_username(To),
    JIDFrom = msync_msg:pb_jid_to_binary(From#'JID'{client_resource = undefined}),
    JIDTo = msync_msg:pb_jid_to_binary(To#'JID'{client_resource = undefined}),
    easemob_roster:del_roster_by_jid(UserFrom, UserTo, JIDFrom, JIDTo),
    msync_log:on_roster_operation(From, To, remove),
    send_remove_feedback(To,From,[To]),
    FromName = msync_msg:pb_jid_to_long_username(From),
    Version = easemob_roster:get_roster_version(FromName),
    msync_multi_devices:send_multi_devices_roster_msg(From, To, 'REMOVE', Version),
    send_remove_feedback(From,To,[From]).

send_remove_feedback(Dest,From,ToList) ->
    DestName = msync_msg:pb_jid_to_long_username(Dest),
    Version = easemob_roster:get_roster_version(DestName),
    Payload = #'RosterBody'{
                 operation = 'REMOVE',
                 from = From,
                 to = ToList,
                 roster_ver = Version
                },
    SystemQueue = Dest#'JID'{
                    app_key = undefined, name = undefined,
                    client_resource = undefined
                   },
    Meta = msync_msg:new_meta(SystemQueue, Dest, 'ROSTER', Payload),
    do_route(SystemQueue, Dest, Meta).

reject(#'JID'{} = Inviter,
       #'JID'{} = Invitee) ->
    ?DEBUG("roster:reject: ~p reject ~p~n",
           [msync_msg:pb_jid_to_binary(Invitee),
            msync_msg:pb_jid_to_binary(Inviter)]),
    msync_log:on_roster_operation(Invitee, Inviter, decline),
    UserInviter = msync_msg:pb_jid_to_long_username(Inviter),
    UserInvitee = msync_msg:pb_jid_to_long_username(Invitee),
    JIDInviter = msync_msg:pb_jid_to_binary(Inviter#'JID'{client_resource = undefined}),
    JIDInvitee = msync_msg:pb_jid_to_binary(Invitee#'JID'{client_resource = undefined}),
    easemob_roster:del_roster_by_jid(UserInviter, UserInvitee, JIDInviter, JIDInvitee),
    InviteeName = msync_msg:pb_jid_to_long_username(Invitee),
    Version = easemob_roster:get_roster_version(InviteeName),
    msync_multi_devices:send_multi_devices_roster_msg(Invitee, Inviter, 'DECLINE', Version),
    send_reject_feedback(Inviter,Invitee,[Inviter]).


do_ban(From, ToList) ->
    %% todo, check the return value, because of IO.
    msync_privacy_cache:add(From,ToList),
    msync_log:on_roster_operation(From, ToList, add_blacklist),
    lists:foreach(
      fun(To) ->
              %% revert the from/to here, to mimic the sender.
              send_ban_allow_feedback(To, From, 'BAN', 'OK', undefined),
              msync_multi_devices:send_multi_devices_roster_msg(From, To, 'BAN', undefined)
      end, ToList),
    ok.

do_allow(From,ToList) ->
    %% todo, check the return value, because of IO.
    msync_privacy_cache:remove(From,ToList),
    msync_log:on_roster_operation(From, ToList, remove_blacklist),
    lists:foreach(
      fun(To) ->
              send_ban_allow_feedback(To, From, 'ALLOW', 'OK', undefined),
              msync_multi_devices:send_multi_devices_roster_msg(From, To, 'ALLOW', undefined)
      end, ToList),
    ok.

send_reject_feedback(Dest,A,ToList) ->
    DestName = msync_msg:pb_jid_to_long_username(Dest),
    Version = easemob_roster:get_roster_version(DestName),
    Payload = #'RosterBody'{
                 operation = 'REMOTE_DECLINE',
                 from = A,
                 to = ToList,
                 roster_ver = Version
                },
    SystemQueue = Dest#'JID'{
                    app_key = undefined, name = undefined,
                    client_resource = undefined
                   },
    Meta = msync_msg:new_meta(SystemQueue, Dest, 'ROSTER', Payload),
    do_route(SystemQueue, Dest, Meta).


send_ban_allow_feedback(From,To, OP, ErrorCode, Description) ->
    Payload = #'RosterBody'{
                 operation = OP,
                 from = From,
                 to = [To],
                 status = #'RosterBody.Status'{
                             error_code = ErrorCode,
                             description =  Description
                            }
                },
    SystemQueue = From#'JID'{
                    app_key = undefined, name = undefined,
                    client_resource = undefined
                   },
    Meta = msync_msg:new_meta(SystemQueue, To, 'ROSTER', Payload),
    do_route(SystemQueue, To, Meta).


do_route(SystemQueue, Dest, Meta) ->
    case msync_route:save_and_route(SystemQueue,Dest,Meta) of
        ok -> ok;
        {error, V} ->
            ?DEBUG("checking route return value~p~n",[V]),
            {error, <<"route error">>}
    end.



maybe_merge_to(#'JID'{
                  app_key = AppKey1,
                  domain  = Domain1
                 },
               #'JID'{
                  app_key = AppKey2,
                  domain = Domain2
                 } = To) ->
    AppKey = case AppKey2 of
                 undefined ->
                     AppKey1;
                 _ -> AppKey2
             end,
    Domain = case Domain2 of
                 undefined ->
                     Domain1;
                 _ ->
                     Domain2
             end,
    To#'JID'{
      app_key = AppKey,
      domain = Domain
     }.

%% get_default(undefined, Default) ->
%%     Default;
%% get_default(A, _Default) ->
%%     A.

maybe_produce_roster_privacy_incr(UserJID, #'RosterBody'{
                                              operation = Operation,
                                              to = RosterList
                                             }) ->
    User = msync_msg:pb_jid_to_binary(UserJID#'JID'{client_resource = undefined}),
    case app_config:is_data_sync_enabled(User) of
        true ->
            spawn(fun () ->
                          NewRosterList = [msync_msg:pb_jid_to_binary(R) || R <- RosterList],
                          case Operation of
                              _ when Operation == 'BAN'; Operation == 'ALLOW' ->
                                  easemob_sync_incr_lib:produce_privacy_incr(
                                    User, Operation, NewRosterList);
                              _ ->
                                  easemob_sync_incr_lib:produce_roster_incr(
                                    User, Operation, NewRosterList)
                          end
                  end);
        false ->
            ignore
    end,
    ok.
