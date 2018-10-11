%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(process_muc_queue).
-export([route/4,
         do_route/5,
         route_to_down_queue/5,
         route_from_down_queue_by_cursor/5,
         route_to_down_queue_low_priority/4,
         route_from_down_queue_by_push/7
        ]
         %%get_destination_users/3,
         %%muc_forward_meta/3]
        ).
-include("logger.hrl").
-include("pb_msync.hrl").
-include("message_store.hrl").
-author("wcy123@gmail.com").

route(#'JID'{}=JID,
      #'JID'{} = From,
      #'JID'{} = To,
      #'Meta'{} = Meta) ->
    do_route(JID,From,To,Meta,[]).

do_route(#'JID'{} = JID,
         #'JID'{} = From0,
         #'JID'{} = To,
         #'Meta'{id = MID,
                 ns = NameSpace} = Meta,
         Exclude) ->
    try
        From =
            chain:apply(
              From0,
              [{ msync_msg, pb_jid_with_default_appkey, [JID] },
               { msync_msg, pb_jid_with_default_domain, [JID] }
          ]),
        MUCJID = To,
        AppKey = get_appkey(From, To),
        GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
        Type = easemob_muc:read_group_type(GroupId),
        MUCMetaFrom = generate_muc_from(From, MUCJID),
        MUCMeta = Meta#'Meta' { from = MUCMetaFrom },
        %% the format is appkey_user
        DefaultDomain = msync_msg:get_with_default(From#'JID'.domain, JID#'JID'.domain),
        check_is_user_allowed(From, GroupId),
        OutcastUsers = read_outcast_users(GroupId,DefaultDomain),
        lists:member( From#'JID'{ client_resource = undefined } , OutcastUsers) andalso throw(mute),
        MuteList = read_mute_users(GroupId,DefaultDomain),
        NewExclude = [From#'JID'{ client_resource = undefined}
                      | Exclude ++ OutcastUsers ++ MuteList],
        ?DEBUG("~n\tFrom=~p, ~n\tOutCastUsers=~p~n\tMuteList= ~p ",
               [From, OutcastUsers, MuteList]),

        MsgType = msync_msg:get_message_type(Meta),
        case MsgType of
            <<"groupchat">> ->
                ToBin = msync_msg:pb_jid_to_binary(To),
                easemob_group_msg:write_group_msg_index(ToBin, MID);
            _ ->
                ignore
        end,

        PQSize = easemob_muc:read_group_pq_size(GroupId),
        GroupBin = msync_msg:pb_jid_to_binary(MUCMetaFrom),
        case NameSpace == 'CHAT' andalso easemob_group_cursor:is_large_group(GroupBin) of
            true ->
                IsLargeMuc = easemob_muc_redis:is_large_muc(GroupBin),
                RouteSliceMessage =
                    fun(Slice) ->
                            Users = read_destination_users(Type, GroupId,DefaultDomain, Slice),
                            easemob_statistics:muc_down(AppKey, Type, NameSpace, cursor, length(Users)),
                            lists:foreach(
                              fun (SubUsers) ->
                                      spawn(fun () ->
                                                    route_message(Type, MUCMetaFrom, SubUsers,
                                                                  MUCMeta, DefaultDomain, IsLargeMuc)
                                            end)
                              end, partition_n(Users -- NewExclude, PQSize))
                    end,
                SliceNum = easemob_muc_redis:read_slice_num(GroupId),
                write_large_group_message_cursor(From, To, Meta, JID),
                slice_do(RouteSliceMessage, SliceNum),
                %% Move cursor for users that block group notification
                %% Sync multi-device message for `From'
                spawn(fun () ->
                              move_cursor(
                                GroupBin,
                                [msync_msg:pb_jid_to_binary(J)
                                 || J <- tl(NewExclude)],
                                integer_to_binary(MID)),
                              case Type == <<"group">> of
                                  true ->
                                      maybe_sync_multi_devices(GroupBin, From, Meta);
                                  false ->
                                      ignore
                              end
                      end);
            false ->
                SliceNum = easemob_muc_redis:read_slice_num(GroupId),
                slice_do(
                  fun(Slice) ->
                          Users = read_destination_users(Type, GroupId,DefaultDomain, Slice),
                          easemob_statistics:muc_down(AppKey, Type, NameSpace, index, length(Users)),
                          %% asynchronously here to gurantee server ack is sent back immediately
                          lists:foreach(
                            fun(SubUsers) ->
                                    %% asynchronously here to fan out for each group of users.
                                    spawn(fun() ->
                                                  lists:foldl(
                                                    fun(User, Acc) ->
                                                            ?DEBUG("User = ~p Exclude = ~p ~n",[User, NewExclude]),
                                                            case lists:member(User, NewExclude) of
                                                                false ->
                                                                    NewMUCMetaFrom = msync_msg:admin_muc_jid(MUCMetaFrom),
                                                                    Value = muc_forward_meta(NewMUCMetaFrom, User, MUCMeta, Type),
                                                                    case Value of
                                                                        ok -> Acc;
                                                                        OtherWise -> OtherWise
                                                                    end;
                                                                true ->
                                                                    Acc
                                                            end
                                                    end, ok, SubUsers)
                                          end)
                            end,
                            partition_n(Users, PQSize))
                  end, SliceNum)
        end,
        write_message_roam(From, To, MID),
        ok
    catch
        owner_not_found ->
            ?ERROR_MSG("group has no owner: JID = ~p, From = ~p, To = ~p Meta = ~p",
                      [JID, From0, To, Meta]),
            {error, <<"owner not found">>};
        group_not_found ->
            ?WARNING_MSG("no such group: JID = ~p, From = ~p, To = ~p Meta = ~p",
                         [JID, From0, To, Meta]),
            {error, <<"group not found">>};
        mute ->
            {error, <<"blocked">>};
        db_error ->
            {error, <<"db error">>};
        not_allowed->
            %% to be backward compatible.
            {error, <<"blocked">>}
    end.

route_to_down_queue(#'JID'{} = JID,
         #'JID'{} = From0,
         #'JID'{} = To,
         #'Meta'{id = MID} = Meta, UseCursor) ->
    try
        From =
            chain:apply(
              From0,
              [{ msync_msg, pb_jid_with_default_appkey, [JID] },
               { msync_msg, pb_jid_with_default_domain, [JID] }
          ]),
        MUCJID = To,
        GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
        Type = easemob_muc:read_group_type(GroupId),
        MUCMetaFrom = generate_muc_from(From, MUCJID),
        %% the format is appkey_user
        DefaultDomain = msync_msg:get_with_default(From#'JID'.domain, JID#'JID'.domain),
        check_is_user_allowed(From, GroupId),
        OutcastUsers = read_outcast_users(GroupId,DefaultDomain),
        lists:member( From#'JID'{ client_resource = undefined } , OutcastUsers) andalso throw(mute),
        GroupBin = msync_msg:pb_jid_to_binary(MUCMetaFrom),
        SliceNum = easemob_muc_redis:read_slice_num(GroupId),
        case UseCursor of
            true ->
                MsgType = msync_msg:get_message_type(Meta),
                case MsgType of
                    <<"groupchat">> ->
                        ToBin = msync_msg:pb_jid_to_binary(To),
                        easemob_group_msg:write_group_msg_index(ToBin, MID);
                    _ ->
                        ignore
                end,
                MuteList = read_mute_users(GroupId,DefaultDomain),
                NewExclude = [From#'JID'{ client_resource = undefined}
                              | OutcastUsers ++ MuteList],
                write_large_group_message_cursor(From, To, Meta, JID),
                %% Move cursor for users that block group notification
                %% Sync multi-device message for `From'
                spawn(fun () ->
                              move_cursor(
                                GroupBin,
                                [msync_msg:pb_jid_to_binary(J)
                                 || J <- tl(NewExclude)],
                                integer_to_binary(MID)),
                              case Type == <<"group">> of
                                  true ->
                                      maybe_sync_multi_devices(GroupBin, From, Meta);
                                  false ->
                                      ignore
                              end
                      end);
            false ->
                skip
        end,
        write_message_roam(From, To, MID),
        {ok, SliceNum}
    catch
        owner_not_found ->
            ?ERROR_MSG("group has no owner: JID = ~p, From = ~p, To = ~p Meta = ~p",
                      [JID, From0, To, Meta]),
            {error, <<"owner not found">>};
        group_not_found ->
            ?WARNING_MSG("no such group: JID = ~p, From = ~p, To = ~p Meta = ~p",
                         [JID, From0, To, Meta]),
            {error, <<"group not found">>};
        mute ->
            {error, <<"blocked">>};
        db_error ->
            {error, <<"db error">>};
        not_allowed->
            %% to be backward compatible.
            {error, <<"blocked">>}
    end.

route_from_down_queue_by_cursor(#'JID'{} = JID,
                      #'JID'{} = From0,
                      #'JID'{} = To,
                      #'Meta'{ns = NameSpace} = Meta,
                      Slice) ->
    try
        From =
            chain:apply(
              From0,
              [{ msync_msg, pb_jid_with_default_appkey, [JID] },
               { msync_msg, pb_jid_with_default_domain, [JID] }
          ]),
        MUCJID = To,
        AppKey = get_appkey(From, To),
        GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
        Type = easemob_muc:read_group_type(GroupId),
        MUCMetaFrom = generate_muc_from(From, MUCJID),
        MUCMeta = Meta#'Meta' { from = MUCMetaFrom },
        %% the format is appkey_user
        DefaultDomain = msync_msg:get_with_default(From#'JID'.domain, JID#'JID'.domain),
        check_is_user_allowed(From, GroupId),
        OutcastUsers = read_outcast_users(GroupId,DefaultDomain),
        lists:member( From#'JID'{ client_resource = undefined } , OutcastUsers) andalso throw(mute),
        MuteList = read_mute_users(GroupId,DefaultDomain),
        NewExclude = [From#'JID'{ client_resource = undefined}
                      | OutcastUsers ++ MuteList],
        PQSize = easemob_muc:read_group_pq_size(GroupId),
        GroupBin = msync_msg:pb_jid_to_binary(MUCMetaFrom),
        IsLargeMuc = easemob_muc_redis:is_large_muc(GroupBin),
        Users = read_destination_users(Type, GroupId,DefaultDomain, Slice),
        easemob_statistics:muc_down(AppKey, Type, NameSpace, cursor, length(Users)),
        lists:foreach(
          fun (SubUsers) ->
                  spawn(fun () ->
                                route_message(Type, MUCMetaFrom, SubUsers,
                                              MUCMeta, DefaultDomain, IsLargeMuc)
                        end)
          end, partition_n(Users -- NewExclude, PQSize)),
        ok
    catch
        owner_not_found ->
            ?ERROR_MSG("group has no owner: JID = ~p, From = ~p, To = ~p Meta = ~p",
                      [JID, From0, To, Meta]),
            {error, <<"owner not found">>};
        group_not_found ->
            ?WARNING_MSG("no such group: JID = ~p, From = ~p, To = ~p Meta = ~p",
                         [JID, From0, To, Meta]),
            {error, <<"group not found">>};
        mute ->
            {error, <<"blocked">>};
        db_error ->
            {error, <<"db error">>};
        not_allowed->
            %% to be backward compatible.
            {error, <<"blocked">>}
    end.

route_to_down_queue_low_priority(#'JID'{} = JID,
         #'JID'{} = From0,
         #'JID'{} = To,
         #'Meta'{} = Meta) ->
    try
        From =
            chain:apply(
              From0,
              [{ msync_msg, pb_jid_with_default_appkey, [JID] },
               { msync_msg, pb_jid_with_default_domain, [JID] }
          ]),
        MUCJID = To,
        GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
        %% the format is appkey_user
        DefaultDomain = msync_msg:get_with_default(From#'JID'.domain, JID#'JID'.domain),
        check_is_user_allowed(From, GroupId),
        OutcastUsers = read_outcast_users(GroupId,DefaultDomain),
        lists:member( From#'JID'{ client_resource = undefined } , OutcastUsers) andalso throw(mute),
        SliceNum = easemob_muc_redis:read_slice_num(GroupId),
        {ok, SliceNum}
    catch
        owner_not_found ->
            ?ERROR_MSG("group has no owner: JID = ~p, From = ~p, To = ~p Meta = ~p",
                      [JID, From0, To, Meta]),
            {error, <<"owner not found">>};
        group_not_found ->
            ?WARNING_MSG("no such group: JID = ~p, From = ~p, To = ~p Meta = ~p",
                         [JID, From0, To, Meta]),
            {error, <<"group not found">>};
        mute ->
            {error, <<"blocked">>};
        not_allowed->
            %% to be backward compatible.
            {error, <<"blocked">>}
    end.
route_from_down_queue_by_push(#'JID'{} = JID,
         #'JID'{} = From0,
         #'JID'{} = To,
         #'Meta'{ns = NameSpace} = Meta,
         Slice, SliceSize, RouteNum) ->
    try
        From =
            chain:apply(
              From0,
              [{ msync_msg, pb_jid_with_default_appkey, [JID] },
               { msync_msg, pb_jid_with_default_domain, [JID] }
          ]),
        MUCJID = To,
        AppKey = get_appkey(From, To),
        GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
        Type = easemob_muc:read_group_type(GroupId),
        MUCMetaFrom = generate_muc_from(From, MUCJID),
        MUCMeta = Meta#'Meta' { from = MUCMetaFrom },
        %% the format is appkey_user
        DefaultDomain = msync_msg:get_with_default(From#'JID'.domain, JID#'JID'.domain),
        check_is_user_allowed(From, GroupId),
        OutcastUsers = read_outcast_users(GroupId,DefaultDomain),
        MuteList = read_mute_users(GroupId,DefaultDomain),
        lists:member( From#'JID'{ client_resource = undefined } , OutcastUsers) andalso throw(mute),
        NewExclude = [ From#'JID'{ client_resource = undefined} | OutcastUsers ++ MuteList ],
        PQSize = easemob_muc:read_group_pq_size(GroupId),
        RangeList = random_range_list(SliceSize, RouteNum),
        %?INFO_MSG("range_list:~p ->~p",[RangeList, {SliceSize, RouteNum}]),
        ChosedUsers = read_destination_users(Type, GroupId,DefaultDomain, Slice, RangeList),
        easemob_statistics:muc_down(AppKey, Type, NameSpace, cursor, length(ChosedUsers)),
        lists:foreach(
          fun (SubUsers) ->
                  spawn(fun () ->
                                route_meta(Type, MUCMetaFrom, SubUsers,
                                           MUCMeta, DefaultDomain)
                        end)
          end, partition_n(ChosedUsers -- NewExclude, PQSize)),
        ok
    catch
        owner_not_found ->
            ?ERROR_MSG("group has no owner: JID = ~p, From = ~p, To = ~p Meta = ~p",
                      [JID, From0, To, Meta]),
            {error, <<"owner not found">>};
        group_not_found ->
            ?WARNING_MSG("no such group: JID = ~p, From = ~p, To = ~p Meta = ~p",
                         [JID, From0, To, Meta]),
            {error, <<"group not found">>};
        mute ->
            {error, <<"blocked">>};
        not_allowed->
            %% to be backward compatible.
            {error, <<"blocked">>}
    end.

check_is_user_allowed(From, GroupId) ->
    User = msync_msg:pb_jid_to_long_username(From),
    case easemob_muc_redis:is_group_member(GroupId, User) of
        false ->
            case From#'JID'.name of
                <<"admin">> -> ok;
                _ ->
                    throw(not_allowed)
            end;
        true ->
            ok
    end.

read_destination_users(<<"group">>, GroupId, Domain, Slice) ->
    Affiliations = easemob_muc_redis:read_group_affiliations(GroupId, Slice),
    lists:map(
      fun (U) ->
              user_jid(U, Domain)
      end, Affiliations);
%% todo, subject to change here
read_destination_users(<<"chatroom">>, GroupId, Domain, Slice) ->
    Affiliations = easemob_muc_redis:read_group_affiliations(GroupId, Slice),
    lists:map(
      fun (U) ->
              user_jid(U, Domain)
      end, Affiliations).
read_destination_users(_Type, GroupId, Domain, Slice, RangeList) ->
    Affiliations = easemob_muc_redis:read_group_affiliations(GroupId, Slice, RangeList),
    lists:map(
      fun (U) ->
              user_jid(U, Domain)
      end, Affiliations).


read_mute_users(GroupId, Domain) ->
    Outcasts = easemob_muc:read_group_mute_list(GroupId),
    lists:map(
      fun (U) ->
              user_jid(U, Domain)
      end, Outcasts).
read_outcast_users(GroupId, Domain) ->
    Outcasts = easemob_muc:read_group_outcast(GroupId),
    lists:map(
      fun (U) ->
              user_jid(U, Domain)
      end, Outcasts).

user_jid(User, Domain) ->
    %% TODO, what if User doesn't not have `_` in middle.
    [AppKey, Name] = binary:split(User, <<"_">>),
    #'JID'{app_key  = AppKey, name = Name, domain = Domain}.

muc_forward_meta(#'JID'{}= MUCJID, #'JID'{} = User, Meta, <<"chatroom">>) ->
    muc_forward_meta_op(#'JID'{}= MUCJID, #'JID'{} = User, Meta, route_online_only);
muc_forward_meta(#'JID'{}= MUCJID, #'JID'{} = User, Meta, <<"group">>) ->
    muc_forward_meta_op(#'JID'{}= MUCJID, #'JID'{} = User, Meta, route).

muc_forward_meta_op(#'JID'{}= MUCJID, #'JID'{} = User, Meta, Fun) ->
    case msync_route:Fun(MUCJID,User,Meta#'Meta'{to = User}) of
        ok ->
            ok;
        V ->
            ?DEBUG("checking route return value~p~n",[V]),
            %% FIXME, msync_route:route might return what?
            {error, <<"route error">>}
    end.

generate_muc_from(#'JID'{name = _FromName}, MUCJID) ->
    MUCJID#'JID' { client_resource = undefined }.

partition_n(L, N) ->
    partition_n(L, N, []).
partition_n([], _N, Acc) ->
    Acc;
partition_n(L, N, Acc) ->
    try
        {L1, L2} = lists:split(N, L),
        partition_n(L2, N, [L1 | Acc])
    catch
        error:badarg ->
            [L | Acc]
    end.

%% Move cursor for users that block group notification
-spec move_cursor(CID :: binary(),
                  UserDomainList :: [binary()],
                  MID :: binary()) ->
                         ok.
move_cursor(CID, UserDomainList, MID) ->
    easemob_group_cursor:set_users_cursor(UserDomainList, CID, MID).

%% Incr unread, log offline, incr apns and send notice
-spec route_message(Type :: binary(),
                    GroupJID :: #'JID'{},
                    UserJIDList :: [#'JID'{}],
                    Meta :: #'Meta'{},
                    Domain :: binary(),
                    IsInLargeGroup :: boolean()) ->
                           ok.
route_message(Type, GroupJID, UserJIDList, #'Meta'{id = MID} = Meta, Domain, IsInLargeGroup) ->
    GroupBin = msync_msg:pb_jid_to_binary(GroupJID),
    UserNameSessionsList =
        easemob_session_redis:get_all_sessions_pipeline(
          [msync_msg:pb_jid_to_long_username(J) || J <- UserJIDList]),
    {OnlineUserNameSessionsList, OfflineUserNameSessionsList} =
        lists:partition(fun ({_, []}) ->
                                false;
                            ({_, _}) ->
                                true
                        end, UserNameSessionsList),
    {OnlineUserNameList, OnlineUserSessions} =
        lists:unzip(OnlineUserNameSessionsList),
    {OfflineUserNameList, _OfflineUserSessions} =
        lists:unzip(OfflineUserNameSessionsList),
    OnlineUserDomainList = [<<UserName/binary, "@", Domain/binary>> ||
                               UserName <- OnlineUserNameList],
    OfflineUserDomainList = [<<UserName/binary, "@", Domain/binary>> ||
                                UserName <- OfflineUserNameList],

    case Type of
        <<"group">> ->
            case app_config:is_offline_msg_limit(GroupBin) of
                false ->
                    %% Incr unread
                    easemob_group_cursor:write_message_index(
                      GroupBin,
                      [msync_msg:pb_jid_to_binary(J) || J <- UserJIDList]),

                    %% Log offline and incr apns
                    case msync_route:get_apns_users(
                           GroupJID,
                           [msync_msg:parse_jid(US) || US <- OfflineUserDomainList],
                           Meta) of
                        [] ->
                            ignore;
                        ApnsUserList ->
                            case IsInLargeGroup of
                                true ->
                                    case app_config:is_push_large_group(GroupBin) of
                                        true ->
                                            easemob_metrics_statistic:inc_counter(offline),
                                            msync_log:on_message_offline(
                                              GroupJID, ApnsUserList, Meta,
                                              [{largeGroup, true}]);
                                        false ->
                                            ignore
                                    end;
                                false ->
                                    AppKey = GroupJID#'JID'.app_key,
                                    Payload = msync_msg:get_apns_payload(Meta),
                                    lists:foreach(
                                      fun(ApnsUser) ->
                                              easemob_metrics_statistic:inc_counter(offline),
                                              msync_log:on_message_offline(
                                                GroupJID, ApnsUser, Meta, []),
                                              To1 = msync_msg:pb_jid_to_binary(ApnsUser#'JID'{client_resource = undefined }),
                                              %% for APNS
                                              case application:get_env(message_store, enable_redis_log_offline, false) of
                                                  true ->
                                                      easemob_message_log_redis:log_packet_offline(<<"groupchat">>, GroupBin, To1, AppKey, MID, Payload);
                                                  _ -> ok
                                              end
                                      end, ApnsUserList)
                            end,
                            ApnsUserBinList =
                                case app_config:is_apns_mute(GroupBin) of
                                    true ->
                                        lists:filtermap(
                                          fun(J) ->
                                                  ToIgnoreResB = msync_msg:pb_jid_to_binary(J),
                                                  case easemob_apns_mute:is_mute_apns_group(ToIgnoreResB, GroupBin) of
                                                      false ->
                                                          {true, ToIgnoreResB};
                                                      true ->
                                                          false
                                                  end
                                          end,
                                          ApnsUserList);
                                    false ->
                                        [msync_msg:pb_jid_to_binary(J) || J <- ApnsUserList]
                                end,
                            easemob_apns:incr_users_apnses(ApnsUserBinList, 1)
                    end;
                true ->
                    easemob_group_cursor:write_message_index(
                      GroupBin, OnlineUserDomainList),
                    move_cursor(GroupBin, OfflineUserDomainList, integer_to_binary(MID))
            end,
            maybe_produce_message_incr_outgoing_index(
              GroupBin, [msync_msg:pb_jid_to_binary(J) || J <- UserJIDList], Meta);
        <<"chatroom">> ->
            %% Incr unread
            easemob_group_cursor:write_message_index(GroupBin, OnlineUserDomainList),
            %% Move cursor for offline users
            move_cursor(GroupBin, OfflineUserDomainList, integer_to_binary(MID)),
            maybe_produce_message_incr_outgoing_index(GroupBin, OnlineUserDomainList, Meta)
    end,

    %% Send notice to online users
    OnlineUserDomainSessionsList =
        lists:zip(OnlineUserDomainList, OnlineUserSessions),
    lists:foreach(
      fun ({User, Sessions}) ->
              UserJID = msync_msg:parse_jid(User),
              msync_route:maybe_send_notice(Sessions, GroupJID,
                                            UserJID, Meta#'Meta'{to = UserJID})
      end, OnlineUserDomainSessionsList).


route_meta(_Type, GroupJID, UserJIDList, Meta, Domain) ->
    UserNameSessionsList =
        easemob_session_redis:get_all_sessions_pipeline(
          [msync_msg:pb_jid_to_long_username(J) || J <- UserJIDList]),
    lists:foreach(
      fun({UserName, Sessions}) ->
              User = <<UserName/binary, "@", Domain/binary>>,
              UserJID = msync_msg:parse_jid(User),
              msync_route:maybe_send_meta(Sessions, GroupJID,
                                            UserJID, Meta#'Meta'{to = UserJID})
      end, UserNameSessionsList),
    ok.

maybe_sync_multi_devices(GroupCID, FromBase, Meta) ->
    Resource = easemob_resource:get_user_resource(
                 msync_msg:pb_jid_to_binary(FromBase#'JID'{client_resource = undefined}),
                 FromBase#'JID'.client_resource),
    From = FromBase#'JID'{client_resource = Resource},
    FromBin = msync_msg:pb_jid_to_binary(From),
    case app_config:is_multi_resource_enabled(FromBin) of
        false ->
            ok;
        true ->
            FromUserDomainResList =
                easemob_resource:get_users_list(
                  [msync_msg:pb_jid_to_binary(
                     From#'JID'{client_resource = undefined})]),
            FromUserOtherDomainResList = FromUserDomainResList --
                [FromBin, msync_msg:pb_jid_to_binary(
                            From#'JID'{client_resource = ?DEFAULT_RESOURCE})],

            case FromUserOtherDomainResList of
                [] ->
                    ignore;
                _ ->
                    %% There should be one generic function for this job in
                    %% `easemob_offline_unread'
                    %% Incr unread for other resources
                    easemob_group_cursor:write_message_resource_index(GroupCID, FromUserOtherDomainResList, 1),

                    %% Send notice
                    FromUserOtherOnlineSessions =
                        lists:flatten([msync_route:get_online_sessions(
                                         msync_msg:parse_jid(UDR))
                                       || UDR <- FromUserOtherDomainResList]),
                    msync_route:maybe_send_notice(
                      FromUserOtherOnlineSessions,
                      msync_msg:parse_jid(GroupCID), From, Meta)
            end
    end.

write_large_group_message_cursor(From, To, Meta, JID) ->
    GroupBin = msync_msg:pb_jid_to_binary(To),
    %% Write to large group message cursor
    case easemob_group_msg_cursor:write_group_msg(
           GroupBin,
           msync_msg:pb_jid_to_binary(
             From#'JID'{client_resource = undefined}),
           integer_to_binary(msync_msg:get_meta_id(Meta)),
           From#'JID'.app_key) of
        true ->
            ok;
        false ->
            ?WARNING_MSG("fail to save large group msg index to "
                         "group cursor for ~s: Queue: ~p, "
                         "Meta = ~p, Reason = ~p~n",
                         [msync_msg:pb_jid_to_binary(JID),
                          msync_msg:pb_jid_to_binary(To),
                          Meta, <<"db error">>]),
            throw(db_error)
    end.

slice_do(Fun, SliceNum) ->
    lists:foreach(
      fun(Slice) ->
              spawn(fun()-> Fun(Slice) end)
      end, lists:seq(1, SliceNum)).

random_range_list(Max, Num) ->
    if
        Num =< 0 ->
            [];
        Num >= Max ->
            [{0,-1}];
        true ->
            Start = rand:uniform(Max) -1,
            if
                Start + Num =< Max ->
                    [{Start, Start+Num-1}];
                true ->
                    [{Start, Max-1},{0,Start+Num-Max-1}]
            end
    end.

maybe_produce_message_incr_outgoing_index(Queue, ToList, Meta) ->
    case app_config:is_data_sync_enabled(Queue) of
        true ->
            spawn(fun () ->
                          easemob_sync_incr_lib:produce_message_incr_index(
                            Queue,
                            lists:zip(ToList, lists:duplicate(length(ToList), undefined)),
                            integer_to_binary(msync_msg:get_meta_id(Meta)),
                            msync_msg:get_message_type(Meta))
                  end);
        false ->
            ignore
    end,
    ok.

write_message_roam(To, From, MID) ->
    spawn(fun() ->
              FromBin = msync_msg:pb_jid_to_binary(From),
              ToBin = msync_msg:pb_jid_to_binary(To),
              case app_config:is_roam(FromBin) of
                  true ->
                      ToUserDomain = message_store:get_user_domain(ToBin),
                      RoamMaxLen = app_config:get_roam_msg_len(FromBin),
                      easemob_message_roam:write(FromBin, ToUserDomain, MID, RoamMaxLen);
                  false ->
                      ok
              end
          end).

get_appkey(From, To) ->
    case From#'JID'.app_key of
        undefined ->
            To#'JID'.app_key;
        AppKey ->
            AppKey
    end.
