%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(msync_muc).
-export([handle/4, maybe_send_chatroom_history/2, send_chatroom_history/2]).
-include("logger.hrl").
-author("wcy123@gmail.com").
-include("pb_mucbody.hrl").

handle(#'JID'{}=JID, #'JID'{} = From, #'JID'{} = To, #'MUCBody'{} = MUCBody) ->
    handle_1(JID, From, To, MUCBody).

handle_1(JID, From, To, #'MUCBody'{ operation = 'CREATE' } = MUCBody ) ->
    handle_create(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'UPDATE' } = MUCBody ) ->
    handle_update(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'DESTROY' } = MUCBody ) ->
    handle_destroy(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'JOIN' } = MUCBody ) ->
    handle_join(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'LEAVE' } = MUCBody ) ->
    handle_leave(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'APPLY' } = MUCBody ) ->
    handle_apply(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'APPLY_ACCEPT' } = MUCBody ) ->
    handle_apply_accept(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'APPLY_DECLINE' } = MUCBody ) ->
    handle_apply_decline(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'INVITE' } = MUCBody ) ->
    handle_invite(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'INVITE_ACCEPT' } = MUCBody ) ->
    handle_invite_accept(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'INVITE_DECLINE' } = MUCBody ) ->
    handle_invite_decline(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'KICK' } = MUCBody ) ->
    handle_kick(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'BAN' } = MUCBody ) ->
    handle_ban(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'ALLOW' } = MUCBody ) ->
    handle_allow(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'BLOCK' } = MUCBody ) ->
    handle_block(JID, From, To, MUCBody);
handle_1(JID, From, To, #'MUCBody'{ operation = 'UNBLOCK' } = MUCBody ) ->
    handle_unblock(JID, From, To, MUCBody);
handle_1(_JID, _From, _To, #'MUCBody'{ operation = OP } = _MUCBody ) ->
    ?ERROR_MSG("unknown operation ~p~n", [OP]),
    {error, <<"unkown operation">>}.


handle_create(#'JID'{} = JID,
              #'JID'{} = MetaFrom,
              #'JID'{} = MetaTo,
              #'MUCBody'{
                 muc_id = MUCId,
                 from = From,
                 setting = Setting,
                 to = ToList,
                 is_chatroom = IsChatRoom,
                 reason = Reason
                }) ->
    OwnerJID =
        chain:apply(
          #'JID'{
             name = Setting#'MUCBody.Setting'.owner
            },
          [ { msync_msg, pb_jid_with_default_appkey, [From] },
            { msync_msg, pb_jid_with_default_appkey, [MetaFrom] },
            { msync_msg, pb_jid_with_default_appkey, [JID] },
            { msync_msg, pb_jid_with_default_name, [From] },
            { msync_msg, pb_jid_with_default_name, [MetaFrom] },
            { msync_msg, pb_jid_with_default_name, [JID] },
            { msync_msg, pb_jid_with_default_domain, [From] },
            { msync_msg, pb_jid_with_default_domain, [MetaFrom] },
            { msync_msg, pb_jid_with_default_domain, [JID] }
          ]),
    DefaultMUCDomainName = <<"conference.", (msync_msg:get_with_default(OwnerJID#'JID'.domain, <<"easemob.com">>))/binary>>,

    MUCJID =
        chain:apply(
          MUCId,
          [ { msync_msg, pb_jid_with_default_appkey, [From] },
            { msync_msg, pb_jid_with_default_appkey, [MetaFrom] },
            { msync_msg, pb_jid_with_default_appkey, [JID] },
            { msync_msg, pb_jid_with_default_name, [MetaTo] },
            { msync_msg, pb_jid_with_default_domain, [#'JID'{ domain = DefaultMUCDomainName }]}
          ]),

    DefaultType = get_default_type(IsChatRoom),
    JIDAffiliations = lists:map(
                     fun(To) ->
                             chain:apply(
                               To,
                               [ { msync_msg, pb_jid_with_default_appkey, [MUCJID] },
                                 { msync_msg, pb_jid_with_default_domain, [OwnerJID] }
                               ])
                     end,
                     ToList),
    %% Affiliations = lists:map(fun msync_msg:pb_jid_to_long_username/1, JIDAffiliations),
    DefaultOpts = [
                   %% wait until every affiliation accept the invitation.
                   {affiliations, []},
                   {type, DefaultType}],
    Opts =
        [{ owner, msync_msg:pb_jid_to_long_username(OwnerJID) }
         |  parse_setting(Setting) ++ DefaultOpts ],
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    case easemob_muc:create(GroupId, Opts) of
        {ok, _}  ->
            ?DEBUG("create muc room ~p ok owned by ~p reason = ~p~n.",[GroupId, OwnerJID, Reason]),
            ErrorCode = 'OK',
            send_create_feedback(JID, OwnerJID, MUCJID, ErrorCode, Reason),
            lists:foreach(
              fun(JIDAffiliation) ->
                      invite_init_members(OwnerJID, JIDAffiliation, MUCJID, Reason)
              end, JIDAffiliations);
        {error, Reason} ->
            ?ERROR_MSG("create muc room ~p failure. Reason=~p~n",[GroupId, Reason]),
            ErrorCode = 'UNKNOWN',
            Reason = <<"unknown">>,
            send_create_feedback(JID, OwnerJID, MUCJID, ErrorCode, Reason)
    end,

    init_group_cursor([OwnerJID#'JID'{client_resource = undefined}], MUCJID),
    ok.
invite_init_members(OwnerJID, OwnerJID, _MUCJID, _Reason) ->
    %% don't send invitation to owner.
    ok;
invite_init_members(OwnerJID, JIDAffiliation, MUCJID, Reason) ->
    MUCBody =
        #'MUCBody'{
           operation = 'INVITE',
           from = OwnerJID,
           to = [JIDAffiliation],
           muc_id = MUCJID,
           reason = Reason
          },
    handle_invite(OwnerJID, OwnerJID, MUCJID, MUCBody).

handle_update(#'JID'{} = JID,
              #'JID'{} = MetaFrom,
              #'JID'{} = MetaTo,
              #'MUCBody'{
                 muc_id = MUCId,
                 from = From,
                 setting = Setting
                }) ->
    {MUCJID, MUCFrom} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    %% it is not allowed to change the owner.
    Opts = proplists:delete(owner, parse_setting(Setting)),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        OwnerJID = read_owner_jid(GroupId, MUCFrom#'JID'.domain),
        case easemob_muc:update(GroupId, Opts) of
            {ok, _}  ->
                ?DEBUG("update muc room ~p ok owned by ~p~n.",[GroupId, MUCFrom]),
                ErrorCode = 'OK',
                Reason = undefined,
                send_update_feedback(JID, OwnerJID, MUCJID, ErrorCode, Reason);
            {error, Reason} ->
                ?ERROR_MSG("update muc room ~p failure. Reason=~p From = ~p~n",[GroupId, Reason, MUCFrom]),
                ErrorCode = 'UNKNOWN',
                Reason = <<"unknown">>,
                send_update_feedback(JID, OwnerJID, MUCJID, ErrorCode, Reason)
        end,
        maybe_restart_room(MUCJID),
        ok
    catch
        owner_not_found ->
            ?ERROR_MSG("update muc ~p fail, no such group, From = ~p ", [GroupId, MUCFrom]),
            Reason2 = undefined,
            send_update_feedback(JID, MUCFrom, MUCJID, 'MUC_NOT_EXIST', Reason2),
            ok
    end.
handle_destroy(#'JID'{} = _JID,
               _MetaFrom,
               _MetaTo,
               #'MUCBody'{muc_id = undefined}) ->
    MUCFrom = undefined,
    MUCJID = undefined,
    send_destroy_feedback(MUCFrom, [MUCFrom], MUCJID, 'MUC_NOT_EXIST', undefined),
    ok;
handle_destroy(#'JID'{} = JID,
               #'JID'{} = MetaFrom,
               #'JID'{} = MetaTo,
               #'MUCBody'{
                  from = From,
                  muc_id = MUCId,
                  reason = Reason
                 }) ->

    {MUCJID, MUCFrom} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% trigger group not found
        _Type = easemob_muc:read_group_type(GroupId),
        Affiliations = easemob_muc:read_group_affiliations(GroupId),
        JIDAffiliations =
            lists:map(
              fun (User) ->
                      [AppKey, Name] = binary:split(User, <<"_">>),
                      #'JID'{app_key  = AppKey, name = Name, domain = MUCFrom#'JID'.domain }
              end, Affiliations),
        ok = easemob_muc:destroy(GroupId),
        ?DEBUG("~p destroy muc ~p group,ok", [ msync_msg:pb_jid_to_long_username(MUCFrom) , GroupId]),
        send_destroy_feedback(MUCFrom, JIDAffiliations, MUCJID, 'OK', Reason),
        maybe_restart_room(MUCJID),
        clean_group_cursor(JIDAffiliations, MUCJID)
    catch
        group_not_found ->
            ?ERROR_MSG("destroy muc ~p fail, no such group,  From = ~p~n", [GroupId, MUCFrom]),
            send_destroy_feedback(MUCFrom, [MUCFrom], MUCJID, 'MUC_NOT_EXIST', Reason),
            ok
    end.
handle_join(#'JID'{} = JID,
            _MetaFrom,
            _MetaTo,
            #'MUCBody'{muc_id = undefined}) ->
    MUCFrom = undefined,
    MUCJID = undefined,
    send_join_feedback(JID, MUCFrom, MUCJID, 'MUC_NOT_EXIST', undefined);
handle_join(#'JID'{}= JID,
            #'JID'{} = MetaFrom,
            #'JID'{} = MetaTo,
            #'MUCBody'{
               from = From,
               muc_id = MUCId
              }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    WhoId = msync_msg:pb_jid_to_long_username(Who),
    case easemob_muc:join(GroupId, WhoId) of
        ok ->
            ?DEBUG("~p join ~p", [WhoId, GroupId]),
            Reason = undefined,
            init_group_cursor([Who#'JID'{client_resource = undefined}], MUCJID),
            send_join_feedback(JID, Who, MUCJID, 'OK', Reason),
            notify_members_for_presence(Who, MUCJID),
            %% when MSYNC is the first one in the chatroom, restart
            %% the chatroom to reload occupants.
            maybe_restart_chatroom_for_first_one(MUCJID),
            maybe_sync_affiliation(MUCJID),
            ok;
        %% todo check user does not exist
        %% todo check permission denied, in case of a private group
        %% todo check permission denied, if the user is in the backlist.
        {error, group_not_found} ->
            ?ERROR_MSG("join muc ~p fail, no such group, From = ~p~n", [GroupId, Who]),
            Reason = undefined,
            send_join_feedback(JID, Who, MUCJID, 'MUC_NOT_EXIST', Reason)
    end,
    ok.

handle_leave(#'JID'{} = JID,
             _MetaFrom,
             _MetaTo,
             #'MUCBody'{muc_id = undefined}) ->
    MUCFrom = undefined,
    MUCJID = undefined,
    send_leave_feedback(JID, MUCFrom, MUCJID, 'MUC_NOT_EXIST', undefined);
handle_leave(#'JID'{}= JID,
             #'JID'{} = MetaFrom,
             #'JID'{} = MetaTo,
             #'MUCBody'{
                from = From,
                muc_id = MUCId
               }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    WhoId = msync_msg:pb_jid_to_long_username(Who),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    case easemob_muc:leave(GroupId, WhoId) of
        ok ->
            ?DEBUG("~p leave ~p", [WhoId, GroupId]),
            Reason = undefined,
            send_leave_feedback(JID, Who, MUCJID, 'OK', Reason),
            notify_members_for_absence(Who,MUCJID),
            %% when MSYNC is the last one in the chatroom, restart
            %% the chatroom to reload occupants.
            maybe_restart_chatroom_for_first_one(MUCJID),
            maybe_sync_affiliation(MUCJID),
            clean_group_cursor([Who#'JID'{client_resource = undefined}], MUCJID),
            ok;
        %% todo check user does not exist
        %% todo check permission denied, in case of a private group
        %% todo check permission denied, if the user is in the backlist.
        {error, group_not_found} ->
            ?ERROR_MSG("leave muc ~p fail, no such group", [GroupId]),
            Reason = undefined,
            send_leave_feedback(JID, Who, MUCJID, 'MUC_NOT_EXIST', Reason)
    end,
    ok.

handle_apply(#'JID'{}= JID,
             #'JID'{} = MetaFrom,
             #'JID'{} = MetaTo,
             #'MUCBody'{
                from = From,
                muc_id = MUCId,
                reason = Reason
               }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        OwnerJID = read_owner_jid(GroupId, Who#'JID'.domain),
        Payload = #'MUCBody'{
                     operation = 'APPLY',
                     from = Who,
                     to = [OwnerJID],
                     muc_id = MUCJID,
                     reason = Reason
                    },
        Meta = msync_msg:new_meta(Who, OwnerJID, 'MUC', Payload),
        %% the return value is handled by module process_system_queue
        msync_route:save_and_route(Who, OwnerJID, Meta)
    catch
        %% todo, handle badmatch when owner is found.
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            Reason = <<"goup not found">>,
            send_apply_feedback(JID, Who, MUCJID, 'MUC_NOT_EXIST', Reason),
            {error, group_not_found}
    end,
    ok.
handle_apply_accept(#'JID'{}= JID,
                    #'JID'{} = MetaFrom,
                    #'JID'{} = MetaTo,
                    #'MUCBody'{} = MUCBody ) ->
    handle_apply_response(#'JID'{}= JID,
                          #'JID'{} = MetaFrom,
                          #'JID'{} = MetaTo,
                          #'MUCBody'{} = MUCBody,
                          'APPLY_ACCEPT').
handle_apply_decline(#'JID'{}= JID,
                     #'JID'{} = MetaFrom,
                     #'JID'{} = MetaTo,
                     #'MUCBody'{} = MUCBody ) ->
    handle_apply_response(#'JID'{}= JID,
                          #'JID'{} = MetaFrom,
                          #'JID'{} = MetaTo,
                          #'MUCBody'{} = MUCBody,
                          'APPLY_DECLINE').

handle_apply_response(#'JID'{}= JID,
                      #'JID'{} = MetaFrom,
                      #'JID'{} = MetaTo,
                      #'MUCBody'{
                         from = From,
                         to = [To],               % accept it one by one
                         muc_id = MUCId
                        },
                      OP) ->
    {MUCJID, Who} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% todo, only owner can accept it.
        _OwnerJID = read_owner_jid(GroupId, Who#'JID'.domain),
        ToJID =
            chain:apply(
              To,
              [{msync_msg, pb_jid_with_default_appkey, [Who]},
               {msync_msg, pb_jid_with_default_domain, [Who]}]
             ),
        Payload = #'MUCBody'{
                     operation = OP,
                     from = Who,
                     muc_id = MUCJID
                    },
        Meta = msync_msg:new_meta(MUCJID, ToJID, 'MUC', Payload),
        NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
        case msync_route:save_and_route(NewMUCJID, ToJID, Meta) of
            ok ->
                case OP of
                    'APPLY_ACCEPT' ->
                        easemob_muc:join(GroupId, msync_msg:pb_jid_to_long_username(ToJID)),
                        notify_members_for_presence(ToJID, MUCJID),
                        maybe_sync_affiliation(MUCJID),
                        init_group_cursor(
                          [ToJID#'JID'{client_resource = undefined}], MUCJID);
                    'APPLY_DECLINE' ->
                        ok
                end;
            {error, Error} ->
                {error, Error}
        end
    catch
        %% todo, handle badmatch when owner is found.
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            Reason = <<"goup not found">>,
            send_apply_feedback(JID, Who, MUCJID, 'MUC_NOT_EXIST', Reason),
            {error, group_not_found}
    end,
    ok.
handle_invite(#'JID'{}= JID,
              #'JID'{} = MetaFrom,
              #'JID'{} = MetaTo,
              #'MUCBody'{
                 from = From,
                 to = ToList,
                 muc_id = MUCId,
                 reason = Reason
                }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% _OwnerJID = read_owner_jid(GroupId, Who#'JID'.domain),
        %% trigger group not found
        _Type = easemob_muc:read_group_type(GroupId),
        lists:foldl(
          fun(To, Acc) ->
                  NewTo =
                  chain:apply(
                    To,
                    [{msync_msg, pb_jid_with_default_appkey, [Who]},
                     {msync_msg, pb_jid_with_default_domain, [Who]}]
                   ),
                  Ret = do_invite(Who, NewTo, MUCJID, Reason),
                  case Acc of
                      ok -> Ret;
                      _ -> Acc
                  end
          end, ok, ToList)
    catch
        %% todo, error handling here
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            Reason = <<"goup not found">>,
            send_invite_feedback(JID, Who, MUCJID, 'MUC_NOT_EXIST', Reason),
            {error, group_not_found}
    end,
    ok.
do_invite(From, To, MUCJID, Reason) ->
    %% todo check user
    Payload = #'MUCBody'{
                 operation = 'INVITE',
                 from = From,
                 to = [To],
                 muc_id = MUCJID,
                 reason = Reason
                },
    Meta = msync_msg:new_meta(MUCJID, To, 'MUC', Payload),
    NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
    msync_route:save_and_route(NewMUCJID, To, Meta).

handle_invite_accept(#'JID'{}= JID,
                     #'JID'{} = MetaFrom,
                     #'JID'{} = MetaTo,
                     #'MUCBody'{} = MUCBody ) ->
    handle_invite_response(#'JID'{}= JID,
                           #'JID'{} = MetaFrom,
                           #'JID'{} = MetaTo,
                           #'MUCBody'{} = MUCBody,
                           'INVITE_ACCEPT').
handle_invite_decline(#'JID'{}= JID,
                      #'JID'{} = MetaFrom,
                      #'JID'{} = MetaTo,
                      #'MUCBody'{} = MUCBody ) ->
    handle_invite_response(#'JID'{}= JID,
                           #'JID'{} = MetaFrom,
                           #'JID'{} = MetaTo,
                           #'MUCBody'{} = MUCBody,
                           'INVITE_DECLINE').

handle_invite_response(#'JID'{}= JID,
                       #'JID'{} = MetaFrom,
                       #'JID'{} = MetaTo,
                       #'MUCBody'{
                          from = From,
                          to = [To],               % accept it one by one
                          muc_id = MUCId
                         },
                       OP) ->
    {MUCJID, Who} = get_muc_id_and_from(JID,MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% todo, only owner can accept it.
        _OwnerJID = read_owner_jid(GroupId, Who#'JID'.domain),
        ToJID =
            chain:apply(
              To,
              [{msync_msg, pb_jid_with_default_appkey, [Who]},
               {msync_msg, pb_jid_with_default_domain, [Who]}]
             ),
        case OP of
            'INVITE_ACCEPT' ->
                %% TODO.  potential privacy leak, if user fake a
                %% 'INVITE_ACCEPT' without an 'INVATION', he could be
                %% able to join a private group.
                %% notify everyone in the group.
                easemob_muc:join(GroupId, msync_msg:pb_jid_to_long_username(Who)),
                Payload = #'MUCBody'{
                     operation = OP,
                     from = Who,
                     muc_id = MUCJID,
                     to = [ ToJID ]
                    },
                Meta = msync_msg:new_meta(MUCJID, ToJID, 'MUC', Payload),
                NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
                Ret = msync_route:save_and_route(NewMUCJID, ToJID, Meta),
                notify_members_for_presence(Who, MUCJID),
                maybe_sync_affiliation(MUCJID),
                init_group_cursor(
                  [Who#'JID'{client_resource = undefined}], MUCJID),
                Ret;
            'INVITE_DECLINE' ->
                Payload = #'MUCBody'{
                     operation = OP,
                     from = Who,
                     muc_id = MUCJID,
                     to = [ ToJID ]
                    },
                Meta = msync_msg:new_meta(MUCJID, ToJID, 'MUC', Payload),
                NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
                msync_route:save_and_route(NewMUCJID, ToJID, Meta)
        end
    catch
        owner_not_found ->
            ?ERROR_MSG("owner not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, <<"muc_not_found">>};
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, <<"muc_not_found">>}
    end.


handle_kick(#'JID'{}= JID,
            #'JID'{} = MetaFrom,
            #'JID'{} = MetaTo,
            #'MUCBody'{
               from = From,
               to = ToList,               % accept it one by one
               muc_id = MUCId,
               reason = Reason
              }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID, MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% todo, error handling, only owner is able to kick others.
        %% todo, error handling in case the other is not a member.
        lists:foreach(
          fun(To) ->
                  NewTo =
                      chain:apply(
                        To,
                        [{msync_msg, pb_jid_with_default_appkey, [Who]},
                         {msync_msg, pb_jid_with_default_domain, [Who]}]
                       ),
                  do_kick(Who, NewTo, MUCJID,Reason)
          end, ToList),
        maybe_sync_affiliation(MUCJID)
    catch
        %% todo, error handling here
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end,
    ok.

do_kick(From, To, MUCJID, Reason) ->
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    ToId = msync_msg:pb_jid_to_long_username(To),
    case easemob_muc:leave(GroupId,ToId) of
        ok ->
            %% SystemQueue = From#'JID'{
            %%                 app_key = undefined, name = undefined,
            %%                 client_resource = undefined
            %%                },
            Payload = #'MUCBody'{
                         operation = 'KICK',
                         from = From,
                         muc_id = MUCJID,
                         to = [To],
                         reason = Reason
                        },
            %% To will be overwriten by process_muc_queue:muc_forward_meta
            Meta = msync_msg:new_meta(MUCJID, To, 'MUC', Payload),
            NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
            Ret = msync_route:save_and_route(NewMUCJID, To, Meta),
            notify_members_for_absence(To,MUCJID),
            clean_group_cursor(
              [To#'JID'{client_resource = undefined}], MUCJID),
            Ret;
        {error, _Reason} ->
            %% return value is not used yet.
            {error, "internal error"}
    end.

handle_ban(#'JID'{}= JID,
            #'JID'{} = MetaFrom,
            #'JID'{} = MetaTo,
            #'MUCBody'{
               from = From,
               to = ToList,               % accept it one by one
               muc_id = MUCId,
               reason = Reason
              }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID, MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        lists:foreach(
          fun(To) ->
                  NewTo =
                      chain:apply(
                        To,
                        [{msync_msg, pb_jid_with_default_appkey, [Who]},
                         {msync_msg, pb_jid_with_default_domain, [Who]}]
                       ),
                  do_ban(Who, NewTo, MUCJID,Reason)
          end, ToList),
        maybe_restart_room(MUCJID)
    catch
        %% todo, error handling here
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end,
    ok.

do_ban(From, To, MUCJID, Reason) ->
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    ToId = msync_msg:pb_jid_to_long_username(To),
    case easemob_muc:ban(GroupId,ToId) of
        ok ->
            %% SystemQueue = From#'JID'{
            %%                 app_key = undefined, name = undefined,
            %%                 client_resource = undefined
            %%                },
            Payload = #'MUCBody'{
                         operation = 'BAN',
                         from = From,
                         muc_id = MUCJID,
                         to = [To],
                         reason = Reason
                        },
            %% To will be overwriten by process_muc_queue:muc_forward_meta
            Meta = msync_msg:new_meta(MUCJID, To, 'MUC', Payload),
            NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
            msync_route:save_and_route(NewMUCJID, To, Meta);
        {error, _Reason} ->
            %% return value is not used yet.
            {error, "internal error"}
    end.

handle_allow(#'JID'{}= JID,
            #'JID'{} = MetaFrom,
            #'JID'{} = MetaTo,
            #'MUCBody'{
               from = From,
               to = ToList,               % accept it one by one
               muc_id = MUCId,
               reason = Reason
              }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID, MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% todo, error handling, only owner is able to kick others.
        %% todo, error handling in case the other is not a member.
        lists:foreach(
          fun(To) ->
                  NewTo =
                      chain:apply(
                        To,
                        [{msync_msg, pb_jid_with_default_appkey, [Who]},
                         {msync_msg, pb_jid_with_default_domain, [Who]}]
                       ),
                  do_allow(Who, NewTo, MUCJID,Reason)
          end, ToList),
        maybe_restart_room(MUCJID)
    catch
        %% todo, error handling here
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end,
    ok.


do_allow(From, To, MUCJID, Reason) ->
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    ToId = msync_msg:pb_jid_to_long_username(To),
    case easemob_muc:allow(GroupId,ToId) of
        ok ->
            %% SystemQueue = From#'JID'{
            %%                 app_key = undefined, name = undefined,
            %%                 client_resource = undefined
            %%                },
            Payload = #'MUCBody'{
                         operation = 'ALLOW',
                         from = From,
                         muc_id = MUCJID,
                         to = [To],
                         reason = Reason
                        },
            %% To will be overwriten by process_muc_queue:muc_forward_meta
            Meta = msync_msg:new_meta(MUCJID, To, 'MUC', Payload),
            NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
            msync_route:save_and_route(NewMUCJID, To, Meta);
        {error, _Reason} ->
            %% return value is not used yet.
            {error, "internal error"}
    end.

handle_block(#'JID'{}= JID,
             #'JID'{} = MetaFrom,
             #'JID'{} = MetaTo,
             #'MUCBody'{
                from = From,
                %%to = ToList,               % accept it one by one
                muc_id = MUCId,
                reason = Reason
               }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID, MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% todo, error handling, only owner is able to kick others.
        %% todo, error handling in case the other is not a member.
        do_block(Who, Who, MUCJID,Reason),
        maybe_restart_room(MUCJID)
    catch
        %% todo, error handling here
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end,
    ok.

do_block(From, To, MUCJID, Reason) ->
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    ToId = msync_msg:pb_jid_to_long_username(To),
    case easemob_muc:block(GroupId,ToId) of
        ok ->
            %% SystemQueue = From#'JID'{
            %%                 app_key = undefined, name = undefined,
            %%                 client_resource = undefined
            %%                },
            Payload = #'MUCBody'{
                         operation = 'BLOCK',
                         from = From,
                         muc_id = MUCJID,
                         to = [To],
                         reason = Reason
                        },
            %% To will be overwriten by process_muc_queue:muc_forward_meta
            Meta = msync_msg:new_meta(MUCJID, To, 'MUC', Payload),
            NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
            msync_route:save_and_route(NewMUCJID, To, Meta);
        {error, _Reason} ->
            %% return value is not used yet.
            {error, "internal error"}
    end.
handle_unblock(#'JID'{}= JID,
               #'JID'{} = MetaFrom,
               #'JID'{} = MetaTo,
               #'MUCBody'{
                  from = From,
                  %% to = ToList,               % accept it one by one
                  muc_id = MUCId,
                  reason = Reason
                 }) ->
    {MUCJID, Who} = get_muc_id_and_from(JID, MetaFrom, MetaTo, From, MUCId),
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    try
        %% todo, error handling, only owner is able to kick others.
        %% todo, error handling in case the other is not a member.
        do_unblock(Who, Who, MUCJID,Reason),
        maybe_restart_room(MUCJID)
    catch
        %% todo, error handling here
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end,
    ok.

do_unblock(From, To, MUCJID, Reason) ->
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    ToId = msync_msg:pb_jid_to_long_username(To),
    case easemob_muc:unblock(GroupId,ToId) of
        ok ->
            %% SystemQueue = From#'JID'{
            %%                 app_key = undefined, name = undefined,
            %%                 client_resource = undefined
            %%                },
            Payload = #'MUCBody'{
                         operation = 'UNBLOCK',
                         from = From,
                         muc_id = MUCJID,
                         to = [To],
                         reason = Reason
                        },
            %% To will be overwriten by process_muc_queue:muc_forward_meta
            Meta = msync_msg:new_meta(MUCJID, To, 'MUC', Payload),
            NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
            msync_route:save_and_route(NewMUCJID, To, Meta);
        {error, _Reason} ->
            %% return value is not used yet.
            {error, "internal error"}
    end.


get_muc_id_and_from(JID, MetaFrom, MetaTo, From, MUCId) ->
    Who =
        chain:apply(
          From,
          [ { msync_msg, pb_jid_with_default_appkey, [From] },
            { msync_msg, pb_jid_with_default_appkey, [MetaFrom] },
            { msync_msg, pb_jid_with_default_appkey, [JID] },
            { msync_msg, pb_jid_with_default_name, [JID] },
            { msync_msg, pb_jid_with_default_domain, [MetaFrom] },
            { msync_msg, pb_jid_with_default_domain, [JID] }
          ]),
    DefaultMUCDomainName = <<"conference.", (msync_msg:get_with_default(Who#'JID'.domain, <<"easemob.com">>))/binary>>,
    MUCJID =
        chain:apply(
          MUCId,
          [ { msync_msg, pb_jid_with_default_appkey, [From] },
            { msync_msg, pb_jid_with_default_appkey, [MetaFrom] },
            { msync_msg, pb_jid_with_default_appkey, [JID] },
            { msync_msg, pb_jid_with_default_name, [MetaTo] },
            { msync_msg, pb_jid_with_default_domain, [#'JID'{ domain = DefaultMUCDomainName }]}
          ]),
    {MUCJID, Who}.


parse_setting(undefined) ->
    [];
parse_setting(#'MUCBody.Setting'{
                 name = Name,
                 desc = Desc,
                 type = Type,
                 max_users = MaxUsers,
                 owner = Owner
                }) ->
    lists:flatmap(
      fun
          ({_Field, undefined})  ->
                         [];
          ({type, Type2})  ->
                         type_to_prop_list(Type2);
          ({Field, Value})  ->
                         [{Field, Value}]
                 end,
      [
       {title, Name},
       {description, Desc},
       {type, Type},
       {max_users, MaxUsers},
       {owner, Owner}
      ]).

type_to_prop_list(undefined) ->
    type_to_prop_list('PUBLIC_JOIN_OPEN');
type_to_prop_list('PRIVATE_OWNER_INVITE') ->
    [ {members_by_default, true},
      {members_only, true},
      {allow_user_invites, false},
      {public, false}];
type_to_prop_list('PRIVATE_MEMBER_INVITE') ->
    [ {members_by_default, true},
      {members_only, true},
      {allow_user_invites, true},
      {public, false}];
type_to_prop_list('PUBLIC_JOIN_APPROVAL') ->
    [ {members_by_default, true},
      {members_only, true},
      {allow_user_invites, false},
      {public, true}];
type_to_prop_list('PUBLIC_JOIN_OPEN') ->
    [ {members_by_default, true},
      {members_only, false},
      {allow_user_invites, false},
      {public, true}];
type_to_prop_list('PUBLIC_ANONYMOUS') ->
    [ {members_by_default, true},
      {members_only, false},
      {allow_user_invites, false},
      {public, true} ].

get_default_type(undefined) ->
    <<"group">>;
get_default_type(true = _IsChatRoom) ->
    <<"chatroom">>;
get_default_type(false = _IsChatRoom) ->
    <<"group">>.


send_create_feedback(Dest, MUCFrom, MUCJID, ErrorCode, Reason) ->
    ToList = [],
    MUCBody = feedback(MUCFrom, ToList, MUCJID, 'CREATE', ErrorCode, Reason),
    send_muc_body(Dest, MUCBody).

send_update_feedback(Dest, MUCFrom, MUCJID, ErrorCode, Reason) ->
    ToList = [],
    MUCBody = feedback(MUCFrom, ToList, MUCJID, 'UPDATE', ErrorCode, Reason),
    send_muc_body(Dest, MUCBody).

send_destroy_feedback(MUCFrom, JIDAffiliations, MUCJID, ErrorCode, Reason) ->
    NewMUCFrom = MUCFrom#'JID'{ client_resource = undefined},
    lists:foreach(
      fun (User) ->
              case User of
                  NewMUCFrom ->
                      ToList = [MUCFrom],
                      MUCBody = #'MUCBody'{
                                   operation = 'DESTROY',
                                   from = MUCFrom,
                                   muc_id = MUCJID,
                                   to = ToList,
                                   reason = Reason,
                                   status =
                                       #'MUCBody.Status'{
                                          error_code = ErrorCode
                                         }
                                  },
                      send_muc_body(MUCFrom, MUCBody);
                  OtherUser ->
                      ToList = [OtherUser],
                      MUCBody = #'MUCBody'{
                                   operation = 'DESTROY',
                                   from = MUCFrom,
                                   muc_id = MUCJID,
                                   to = ToList,
                                   reason = Reason
                                  },
                      send_muc_body(OtherUser, MUCBody)
              end
      end, JIDAffiliations).

send_join_feedback(Dest, MUCFrom, MUCJID, ErrorCode, Reason) ->
    ToList = [],
    MUCBody = feedback(MUCFrom, ToList, MUCJID, 'JOIN', ErrorCode, Reason),
    send_muc_body(Dest, MUCBody),
    maybe_send_chatroom_history(MUCJID, Dest).


send_leave_feedback(Dest, MUCFrom, MUCJID, ErrorCode, Reason) ->
    ToList = [],
    MUCBody = feedback(MUCFrom, ToList, MUCJID, 'LEAVE', ErrorCode, Reason),
    send_muc_body(Dest, MUCBody).

%% notify an error
send_apply_feedback(Dest, MUCFrom, MUCJID, ErrorCode, Reason) ->
    ToList = [],
    MUCBody = feedback(MUCFrom, ToList, MUCJID, 'APPLY', ErrorCode, Reason),
    send_muc_body(Dest, MUCBody).
send_invite_feedback(Dest, MUCFrom, MUCJID, ErrorCode, Reason) ->
    ToList = [],
    MUCBody = feedback(MUCFrom, ToList, MUCJID, 'INVITE', ErrorCode, Reason),
    send_muc_body(Dest, MUCBody).

feedback(MUCFrom, ToList, MUCJID, OP, ErrorCode, Reason) ->
    #'MUCBody'{
       operation = OP,
       from = MUCFrom,
       muc_id = MUCJID,
       to = ToList,
       status = #'MUCBody.Status'{
                   error_code = ErrorCode,
                   description = Reason
                  }
      }.

notify_members_for_presence(MUCFrom, MUCJID) ->
    %% process_muc_queue:do_route get user list from redis, so that
    %% the resource is not included.
    Exclude = [],
    Reason = undefined,
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    Type = easemob_muc:read_group_type(GroupId),
    IsChatRoom = is_chat_room(Type),
    MUCBody = muc_presence(MUCFrom,MUCJID, Reason, IsChatRoom),
    broadcast_muc_body(MUCFrom, MUCJID, MUCBody, Exclude).
is_chat_room(<<"chatroom">>) ->
    true;
is_chat_room(_) ->
    false.

notify_members_for_absence(MUCFrom, MUCJID) ->
    %% process_muc_queue:do_route get user list from redis, so that
    %% the resource is not included.
    Exclude = [],
    Reason = undefined,
    GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
    Type = easemob_muc:read_group_type(GroupId),
    IsChatRoom = is_chat_room(Type),
    MUCBody = muc_absence(MUCFrom, MUCJID, Reason, IsChatRoom),
    MUCAdmin = msync_msg:pb_jid(undefined, <<"admin">>, <<"easemob.com">>, undefined),
    broadcast_muc_body(MUCAdmin, MUCJID, MUCBody, Exclude).

muc_absence(MUCFrom,MUCJID, Reason, IsChatRoom) ->
    #'MUCBody'{
       operation = 'ABSENCE',
       from = MUCFrom,
       muc_id = MUCJID,
       to = [],
       is_chatroom = IsChatRoom,
       reason = Reason
      }.

muc_presence(MUCFrom,MUCJID, Reason, IsChatRoom) ->
    #'MUCBody'{
       operation = 'PRESENCE',
       from = MUCFrom,
       muc_id = MUCJID,
       to = [],
       is_chatroom = IsChatRoom,
       reason = Reason
      }.

broadcast_muc_body(From, MUCJID, MUCBody, Exclude) ->
    %% To will be overwriten by process_muc_queue:muc_forward_meta
    To = undefined,
    Meta = msync_msg:new_meta(MUCJID, To, 'MUC', MUCBody),
    %% broadcast
    NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
    msync_route:save(From, NewMUCJID, Meta),
    process_muc_queue:do_route(From, From, MUCJID, Meta, Exclude).

send_muc_body(ToJID, #'MUCBody'{ muc_id = MUCJID } = MUCBody) ->
    Meta = msync_msg:new_meta(MUCJID, ToJID, 'MUC', MUCBody),
    NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
    msync_route:save_and_route(NewMUCJID, ToJID, Meta).

read_owner_jid(GroupId, Domain) ->
    Owner = easemob_muc:read_group_owner(GroupId),
    {true, _} = {is_binary(Owner), Owner},
    [OwnerAppKey, OwnerName] = binary:split(Owner, <<"_">>),
    OwnerJID =
        #'JID'{app_key = OwnerAppKey, name = OwnerName, domain = Domain},
    OwnerJID.

%% system_queue(Domain) ->
%%     #'JID'{
%%        app_key = undefined,
%%        name = undefined,
%%        domain = Domain,
%%        client_resource = undefined
%%       }.

maybe_send_chatroom_history(MUCJID, Dest) ->
    try
        GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
        Type = easemob_muc:read_group_type(GroupId),
        ?DEBUG("maybe_send_chatroom_history GroupId = ~p, Type =~p~n",[GroupId, Type]),
        case Type of
            <<"chatroom">> ->
                send_chatroom_history(MUCJID#'JID'{client_resource = undefined}, Dest);
            _ ->
                ok
        end
    catch
        Class:Error ->
            ?WARNING_MSG("cannot send chatroom history. ~p:~p MUCJID = ~p, DEST = ~p~n\tStack = ~p~n",
                         [Class, Error,
                          msync_msg:pb_jid_to_binary(MUCJID),
                          msync_msg:pb_jid_to_binary(Dest),
                          erlang:get_stacktrace()]),
            {error, {Class, Error}}
    end.

send_chatroom_history(MUCJID, Dest) ->
    MUCBin = msync_msg:pb_jid_to_binary(MUCJID),
    case app_config:is_send_chatroom_history(MUCBin) of
        true ->
          case easemob_group_cursor:is_large_group(MUCBin) of
              true ->
                  %% Don't send chat history for large chatroom
                  %% send history msg for cursor chatroom
                  send_chatroom_history_elem_cursor(MUCJID, Dest);
              false ->
                  HistoryNum = app_config:get_chat_history_num(MUCBin),
                  Hist = easemob_group_msg:read_group_msg(MUCBin, HistoryNum),
                  send_chatroom_history_elem(MUCJID, Dest, Hist)
          end;
      false ->
          ignore
  end.

send_chatroom_history_elem_cursor(MUCJID, Dest) ->
    MUCJIDDomain = msync_msg:pb_jid_to_binary(MUCJID),
    UserDomain = msync_msg:pb_jid_to_binary(msync_offline_msg:ignore_resource(Dest)),
    Num = app_config:get_chat_history_num(UserDomain),
    Messages = message_store:read_chatroom_history_message(MUCJIDDomain, Num),
    Metas = [msync_msg:decode_meta(M) || M <- Messages],
    msync_route:route_meta(MUCJID, Dest, Metas).

send_chatroom_history_elem(_MUCJID, _Dest, []) ->
    ok;
send_chatroom_history_elem(MUCJID, Dest, Hist) ->
    Metas =[msync_msg:decode_meta(M) || M <- Hist],
    msync_route:route_meta(MUCJID, Dest, Metas).




maybe_restart_room(MUCJID) ->
    mod_muc_admin:stop_room(
      msync_msg:pb_jid_to_long_username(MUCJID), MUCJID#'JID'.domain).

maybe_sync_affiliation(MUCJID) ->
    mod_muc_admin:sync_affiliation(MUCJID).

%% this is a dirty hack.
maybe_restart_chatroom_for_first_one(MUCJID) ->
    try
        GroupId = msync_msg:pb_jid_to_long_username(MUCJID),
        Type = easemob_muc:read_group_type(GroupId),
        case Type of
            <<"chatroom">> ->
                N = (catch easemob_muc:read_num_of_affiliations(msync_msg:pb_jid_to_long_username(MUCJID))),
                case N of
                    %% BUG: by default, XMPP has one ghost user and an onwer.
                    _ when is_integer(N) andalso N =< 3 ->
                        maybe_restart_room(MUCJID);
                    _Else -> ok
                end;
            _ ->
                ok
        end
    catch
        Class:Error ->
            ?WARNING_MSG("cannot restart the chatroom. ~p:~p MUCJID = ~p~n\tStack = ~p~n",
                         [Class, Error,
                          msync_msg:pb_jid_to_binary(MUCJID),
                          erlang:get_stacktrace()]),
            {error, {Class, Error}}
    end.

%% Large group: init group message cursor
init_group_cursor(UserJIDList, MUCJID) ->
    MUCBin = msync_msg:pb_jid_to_binary(MUCJID),
    case app_config:is_read_group_cursor(MUCBin) of
        true ->
            easemob_group_cursor:init_group_cursor(
              [msync_msg:pb_jid_to_binary(J) || J <- UserJIDList], MUCBin),
            ok;
        false ->
            ok
    end.

%% Large group: clean group message cursor
clean_group_cursor(UserJIDList, MUCJID) ->
    MUCBin = msync_msg:pb_jid_to_binary(MUCJID),
    case app_config:is_read_group_cursor(MUCBin) of
        true ->
            easemob_group_cursor:clean_group_cursor(
              [msync_msg:pb_jid_to_binary(J) || J <- UserJIDList], MUCBin),
            ok;
        false ->
            ok
    end.
