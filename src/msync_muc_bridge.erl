%%%-------------------------------------------------------------------
%%% @author clanchun <clanchun@gmail.com>
%%% @copyright (C) 2016, clanchun
%%% @doc
%%% Transfer MUC calls from SDK to REST by Thrift
%%% Transfer MUC Redis messages from REST to SDK
%%%
%%% Design strategy of REST notification:
%%% Only successful Thrift events will generate a notification sent to
%%% Redis queue, failed events may include RPC failure or actual logic
%%% of each event.
%%% @end
%%% Created : 1 Nov 2016 by clanchun <clanchun@gmail.com>
%%%-------------------------------------------------------------------
-module(msync_muc_bridge).
-compile(export_all).
%% API
-export([handle/4,    %% handle calls from SDK
         handle_msg/8 %% handle messages from REST
        ]).

-include("logger.hrl").
-include_lib("msync_proto/include/pb_mucbody.hrl").

-ifdef(TEST).
-export([get_app_key/3,
         get_invoker/2,
         get_group_name/2
        ]).
-endif.

%%%===================================================================
%%% API
%%%===================================================================

handle(JID, From, To, #'MUCBody'{operation = 'CREATE'} = Body) ->
    create(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'UPDATE'} = Body) ->
    update(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'DESTROY'} = Body) ->
    destroy(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'JOIN'} = Body) ->
    join(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'LEAVE'} = Body) ->
    leave(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'APPLY'} = Body) ->
    apply(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'APPLY_ACCEPT'} = Body) ->
    apply_accept(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'APPLY_DECLINE'} = Body) ->
    apply_decline(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'INVITE'} = Body) ->
    invite(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'INVITE_ACCEPT'} = Body) ->
    invite_accept(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'INVITE_DECLINE'} = Body) ->
    invite_decline(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'KICK'} = Body) ->
    kick(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'BAN'} = Body) ->
    ban(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'ALLOW'} = Body) ->
    allow(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'BLOCK'} = Body) ->
    block(JID, From, To, Body);
handle(JID, From, To, #'MUCBody'{operation = 'UNBLOCK'} = Body) ->
    unblock(JID, From, To, Body);

handle(_, _, _, #'MUCBody'{operation = Op}) ->
    ?ERROR_MSG("unknown operation ~p~n", [Op]),
    {error, <<"unknown operation">>}.

handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"create_group">>, Opts, Roles) ->
    reply_create(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"modify_group">>, Opts, Roles) ->
    reply_update(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"delete_group">>, Opts, Roles) ->
    reply_destroy(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"chatroom_direct_join">>, Opts, Roles) ->
    reply_join(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"quit_group">>, Opts, Roles) ->
    reply_leave(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"apply">>, Opts, Roles) ->
    reply_apply(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"apply_verify">>, Opts, Roles) ->
    case proplists:get_value(<<"result">>, Opts) of
        true ->
            reply_apply_accept(Host, AppKey, GroupID, Invoker,
                               RoomType,  Opts, Roles, undefined, <<>>);
        false ->
            reply_apply_decline(Host, AppKey, GroupID, Invoker,
                                RoomType, Opts, Roles, undefined, <<>>)
    end;
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"invite">>, Opts, Roles) ->
    reply_invite(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"invite_verify">>, Opts, Roles) ->
    case proplists:get_value(<<"result">>, Opts) of
        true ->
            reply_invite_accept(Host, AppKey, GroupID, Invoker,
                                RoomType, Opts, Roles, undefined, <<>>);
        false ->
            reply_invite_decline(Host, AppKey, GroupID, Invoker,
                                 RoomType, Opts, Roles, undefined, <<>>)
    end;
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"kick_member">>, Opts, Roles) ->
    reply_kick(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"add_blacklist">>, Opts, Roles) ->
    reply_ban(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"remove_blacklist">>, Opts, Roles) ->
    reply_allow(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"add_block">>, Opts, Roles) ->
    reply_block(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"remove_block">>, Opts, Roles) ->
    reply_unblock(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);

%% some new events
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"assign_owner">>, Opts, Roles) ->
    reply_assign_owner(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"add_admin">>, Opts, Roles) ->
    reply_add_admin(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"remove_admin">>, Opts, Roles) ->
    reply_remove_admin(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"add_mute">>, Opts, Roles) ->
    reply_add_mute(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"remove_mute">>, Opts, Roles) ->
    reply_remove_mute(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"app_admin_direct_join">>, Opts, Roles) ->
    reply_app_admin_direct_join(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);

%% this event is triggered by ejabberd only
handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"invite_direct_join">>, Opts, Roles) ->
    reply_invite_direct_join(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);

handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"live_close_kick">>, Opts, Roles) ->
    reply_live_close_kick(Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles, 'OK', <<>>);

handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"update_announcement">>,
           Opts, Roles) ->
    reply_update_announcement(Host, AppKey, GroupID, Invoker, RoomType, Opts,
                              Roles, 'OK', <<>>);

handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"delete_announcement">>,
           Opts, Roles) ->
    reply_delete_announcement(Host, AppKey, GroupID, Invoker, RoomType, Opts,
                              Roles, 'OK', <<>>);

handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"upload_share_file">>,
           Opts, Roles) ->
    reply_upload_share_file(Host, AppKey, GroupID, Invoker, RoomType, Opts,
                            Roles, 'OK', <<>>);

handle_msg(Host, AppKey, GroupID, Invoker, RoomType, <<"delete_share_file">>,
           Opts, Roles) ->
    reply_delete_share_file(Host, AppKey, GroupID, Invoker, RoomType, Opts,
                            Roles, 'OK', <<>>);

handle_msg(_, _, _, _, _, Event, _, _) ->
    ?ERROR_MSG("unknown event ~p~n", [Event]),
    {error, <<"unknown event">>}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

create(JID, From, To, #'MUCBody'{
                         muc_id = MUCJID,
                         is_chatroom = IsChatRoom,
                         from = BodyFrom,
                         to = Affiliations,
                         reason = Reason,
                         setting = Setting
                        }) ->
    RoomType = get_room_type(IsChatRoom),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    InviteeList = [Name || #'JID'{name = Name} <- Affiliations],
    Opts = parse_setting(Setting) ++ extra_setting(Setting#'MUCBody.Setting'.type),
    InvokerJID = get_invoker_jid(BodyFrom, JID, From),

    case easemob_muc_opt:create(BaseParams, Opts, []) of
        {ok, GroupID} ->
            ?INFO_MSG("msync muc bridge create ok, invoker jid: ~p~n", [InvokerJID]),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'CREATE', 'OK', <<>>),
            send_msg(InvokerJID, MUCBody),

            %% invite initial members after creating returns ok
            #'JID'{app_key = AppKey, domain = Domain} = InvokerJID,
            lists:foreach(fun (Name) ->
                                  RecipientJID = make_jid(AppKey, Name, Domain),
                                  NewMUCJID = MUCJID#'JID'{name = GroupID},
                                  InviteMUCBody =
                                      make_muc_body(InvokerJID, [RecipientJID],
                                                    NewMUCJID, 'INVITE',
                                                    undefined, <<>>, reason(Reason)),
                                  ?INFO_MSG("invite invoker: ~p, muc: ~p, body: ~p~n",
                                            [InvokerJID, NewMUCJID, InviteMUCBody]),
                                  invite(InvokerJID, InvokerJID, NewMUCJID, InviteMUCBody)
                          end, InviteeList),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'CREATE', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

update(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
update(JID, From, To, #'MUCBody'{
                         muc_id = MUCJID,
                         from = BodyFrom,
                         setting = Setting
                        }) ->
    #'JID'{app_key = AppKey} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    Opts = proplists:delete(owner, parse_setting(Setting)),

    case easemob_muc_opt:set(BaseParams, Opts) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge update ok, invoker jid: ~p~n", [InvokerJID]),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'UPDATE', 'OK', <<>>),
            send_msg(InvokerJID, MUCBody),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'UPDATE', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

destroy(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
destroy(JID, From, To, #'MUCBody'{
                          muc_id = MUCJID,
                          from = BodyFrom
                         }) ->
    #'JID'{app_key = AppKey} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:delete(BaseParams) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge destroy ok, invoker jid: ~p~n", [InvokerJID]),
            MUCBody = make_muc_body(InvokerJID, [InvokerJID], MUCJID,
                                    'DESTROY', 'OK', <<>>),
            send_msg(InvokerJID, MUCBody),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [InvokerJID], MUCJID,
                                    'DESTROY', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

%% 'join' goes the same as 'apply', let REST-side decide
join(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
join(JID, From, To, #'MUCBody'{
                       muc_id = MUCJID,
                       reason = Reason,
                       from = BodyFrom
                      }) ->
    #'JID'{app_key = AppKey,
           domain = Domain} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:apply(BaseParams, reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge join ok, invoker jid: ~p~n", [InvokerJID]),
            GroupID = get_group_name(MUCJID, To),
            NewMUCJID = make_jid(AppKey, GroupID, conference_host(Domain)),
            init_group_cursor([InvokerJID], NewMUCJID),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'JOIN', 'OK', <<>>),
            send_msg(InvokerJID, MUCBody),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'JOIN', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

leave(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
leave(JID, From, To, #'MUCBody'{
                        muc_id = MUCJID,
                        from = BodyFrom
                       }) ->
    #'JID'{app_key = AppKey} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:quit(BaseParams) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge leave ok, invoker jid: ~p~n", [InvokerJID]),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'LEAVE', 'OK', <<>>),
            send_msg(InvokerJID, MUCBody),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'LEAVE', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

apply(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
apply(JID, From, To, #'MUCBody'{
                        muc_id = MUCJID,
                        reason = Reason,
                        from = BodyFrom
                       }) ->
    #'JID'{app_key = AppKey} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:apply(BaseParams, reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge apply ok, invoker jid: ~p~n", [InvokerJID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'APPLY', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

apply_accept(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
apply_accept(JID, From, To, #'MUCBody'{
                               muc_id = MUCJID,
                               from = BodyFrom,
                               reason = Reason,
                               to = [Applicant]
                              }) ->
    #'JID'{app_key = AppKey} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:apply_accept(BaseParams, Applicant#'JID'.name, reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge apply accept ok, invoker jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'APPLY_ACCEPT', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

apply_decline(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
apply_decline(JID, From, To, #'MUCBody'{
                                muc_id = MUCJID,
                                from = BodyFrom,
                                reason = Reason,
                                to = [Applicant]
                               }) ->
    #'JID'{app_key = AppKey} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:apply_decline(
           BaseParams, Applicant#'JID'.name, reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge decline ok, jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'APPLY_DECLINE', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

invite(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
invite(JID, From, To, #'MUCBody'{
                         muc_id = MUCJID,
                         from = BodyFrom,
                         reason = Reason,
                         to = InviteeList
                        }) ->
    #'JID'{app_key = AppKey} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:invite(
           BaseParams, [Name || #'JID'{name = Name} <- InviteeList], reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge invite ok, jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                                    'INVITE', ErrorCode, <<"unknown">>),
            send_msg(InvokerJID, MUCBody)
    end.

invite_accept(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
invite_accept(JID, From, To, #'MUCBody'{
                                muc_id = MUCJID,
                                reason = Reason,
                                from = BodyFrom
                               }) ->
    #'JID'{app_key = AppKey, name = Inviter} = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:invite_accept(BaseParams, [Inviter], reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge invite accept ok, jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            {error, ErrorCode}
    end.

invite_decline(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
invite_decline(JID, From, To, #'MUCBody'{
                                 muc_id = MUCJID,
                                 reason = Reason,
                                 from = BodyFrom
                                }) ->
    #'JID'{app_key = AppKey, name = Inviter} = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:invite_decline(BaseParams, [Inviter], reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge invite decline ok, jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            {error, ErrorCode}
    end.

kick(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
kick(JID, From, To, #'MUCBody'{
                       muc_id = MUCJID,
                       from = BodyFrom,
                       to = KickList
                      }) ->
    #'JID'{app_key = AppKey} = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:kick(
           BaseParams, [Name || #'JID'{name = Name} <- KickList]) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge kick ok, jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            {error, ErrorCode}
    end.

%% move a user into outcast
ban(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
ban(JID, From, To, #'MUCBody'{
                      muc_id = MUCJID,
                      from = BodyFrom,
                      reason = Reason,
                      to = BanList
                     }) ->
    #'JID'{app_key = AppKey} = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:ban(
           BaseParams, [Name || #'JID'{name = Name} <- BanList], reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge ban ok, jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            {error, ErrorCode}
    end.

%% move a user out from outcast
allow(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
allow(JID, From, To, #'MUCBody'{
                        muc_id = MUCJID,
                        from = BodyFrom,
                        reason = Reason,
                        to = AllowList
                       }) ->
    #'JID'{app_key = AppKey} = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:allow(
           BaseParams, [Name || #'JID'{name = Name} <- AllowList], reason(Reason)) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge allow ok, jid: ~p~n", [JID]),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            {error, ErrorCode}
    end.

%% user blocks a group/chatroom's notifications
block(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
block(JID, From, To, #'MUCBody'{
                        muc_id = MUCJID,
                        from = BodyFrom
                       }) ->
    #'JID'{app_key = AppKey,
           domain = Domain} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:block(BaseParams) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge block ok, invoker jid: ~p~n", [InvokerJID]),
            MUCBody = make_muc_body(InvokerJID, [InvokerJID], MUCJID,
                                    'BLOCK', 'OK', <<>>),
            send_msg(InvokerJID, MUCBody),

            GroupID = get_group_name(MUCJID, To),
            NewMUCJID = make_jid(AppKey, GroupID, conference_host(Domain)),
            restart_room(NewMUCJID),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            {error, ErrorCode}
    end.

%% user unblocks a group/chatroom's notifications
unblock(_, _, _, #'MUCBody'{muc_id = undefined}) ->
    {error, muc_not_exist};
unblock(JID, From, To, #'MUCBody'{
                          muc_id = MUCJID,
                          from = BodyFrom
                         }) ->
    #'JID'{app_key = AppKey,
           domain = Domain} = InvokerJID = get_invoker_jid(BodyFrom, JID, From),
    RoomType = get_room_type(AppKey, MUCJID#'JID'.name),
    BaseParams = make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType),
    case easemob_muc_opt:unblock(BaseParams) of
        {ok, _} ->
            ?INFO_MSG("msync muc bridge unblock ok, invoker jid: ~p~n", [InvokerJID]),
            MUCBody = make_muc_body(InvokerJID, [InvokerJID], MUCJID,
                                    'UNBLOCK', 'OK', <<>>),
            send_msg(InvokerJID, MUCBody),

            GroupID = get_group_name(MUCJID, To),
            NewMUCJID = make_jid(AppKey, GroupID, conference_host(Domain)),
            restart_room(NewMUCJID),
            ok;
        Error ->
            ErrorCode = decode_error(Error),
            {error, ErrorCode}
    end.

reply_create(Host, AppKey, GroupID, Invoker, RoomType,
             Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply create: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Invitees = get_members(Opts),
    InviteeJIDList =
        [make_jid(AppKey, Invitee, Host) || Invitee <- Invitees],
    init_group_cursor([InvokerJID | InviteeJIDList], MUCJID),
    %% do some multi device 
    do_multi_device(RoomType, InvokerJID, MUCJID, 'CREATE', [], Opts),
        
    case proplists:get_value(<<"notify">>, Opts) of
        true ->
            Op =
                case RoomType of
                    <<"chatroom">> ->
                        'PRESENCE';
                    _ ->
                        'DIRECT_JOINED'
                end,
            lists:foreach(fun (InviteeJID) ->
                                  MUCBody = make_muc_body(InvokerJID, [],
                                                          MUCJID, Op,
                                                          ErrorCode, ErrorDesc),
                                  NewMUCBody =
                                      MUCBody#'MUCBody'{
                                        status = undefined,
                                        is_chatroom = is_chatroom(RoomType)},
                                  send_msg(InviteeJID, NewMUCBody),
                                  case is_send_presence(RoomType, AppKey) of
                                      true ->
                                          send_presence(InviteeJID, MUCJID, RoomType);
                                      false ->
                                          ignore
                                  end
                          end, InviteeJIDList),

            restart_room_for_first_one(GroupID, MUCJID, RoomType),
            mod_muc_admin:sync_affiliation(MUCJID);
        false ->
            ignore
    end.

reply_update(Host, AppKey, GroupID, Invoker, RoomType,
             Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply update: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),

    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'UPDATE', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    Recipients = get_recipients(MUCJID, Roles),
    %% do some multi device 
    do_multi_device(RoomType, InvokerJID, MUCJID, 'UPDATE', [], Opts),
    notify_recipients([Invoker], Recipients, AppKey, Host, NewMUCBody, none),
    restart_room(MUCJID).

reply_destroy(Host, AppKey, GroupID, Invoker, RoomType,
              Opts, _Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply destroy: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, _Roles]),
    Applicants = get_applicants(Opts),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Recipients = get_members(Opts),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                            'DESTROY', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    %% do some multi device 
    do_multi_device(RoomType, InvokerJID, MUCJID, 'DESTROY', [], Opts),
    notify_recipients([Invoker], Applicants ++ Recipients,
                      AppKey, Host, NewMUCBody, recipient),

    %% Large group: clean group message cursor
    RecipientJIDList =
        [make_jid(AppKey, Recipient, Host) || Recipient <- Recipients],
    clean_group_cursor(RecipientJIDList, MUCJID),
    restart_room(MUCJID).

reply_join(Host, AppKey, GroupID, Invoker, RoomType,
           Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply join: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'JOIN', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    Recipients = get_recipients(MUCJID, Roles),

    init_group_cursor([InvokerJID], MUCJID),
    msync_muc:maybe_send_chatroom_history(MUCJID, InvokerJID),
    %% do some multi device 
    do_multi_device(RoomType, InvokerJID, MUCJID, 'JOIN', [], Opts),

    case is_send_presence(RoomType, AppKey) of
        true ->
            send_presence(InvokerJID, MUCJID, RoomType);
        false ->
            ignore
    end,

    notify_recipients([Invoker], Recipients, AppKey, Host, NewMUCBody, none),
    restart_room_for_first_one(GroupID, MUCJID, RoomType),
    mod_muc_admin:sync_affiliation(MUCJID).

reply_leave(Host, AppKey, GroupID, Invoker, RoomType,
            Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply leave: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'LEAVE', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    Recipients = get_recipients(MUCJID, Roles),

    %% do some multi device 
    do_multi_device(RoomType, InvokerJID, MUCJID, 'LEAVE', [], Opts),
    
    restart_room_for_first_one(GroupID, MUCJID, RoomType),
    mod_muc_admin:sync_affiliation(MUCJID),
    case is_send_presence(RoomType, AppKey) of
        true ->
            send_absence(InvokerJID, MUCJID, RoomType);
        false ->
            ignore
    end,
    notify_recipients([Invoker], Recipients, AppKey, Host, NewMUCBody, none),
    clean_group_cursor([InvokerJID], MUCJID).

reply_apply(Host, AppKey, GroupID, Invoker, RoomType,
            Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply apply: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    Applicants = get_applicants(Opts),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Reason = proplists:get_value(<<"reason">>, Opts),

    try
        Recipients =
            case get_recipients(MUCJID, Roles) of
                [] ->
                    Owner = easemob_muc_redis:read_group_owner(
                              msync_msg:pb_jid_to_long_username(MUCJID)),
                    [_AppKey, Name] = binary:split(Owner, <<"_">>),
                    [Name];
                Result ->
                    Result
            end,

        lists:foreach(fun (Applicant) ->
                              ApplicantJID = make_jid(AppKey, Applicant, Host),
                              do_multi_device(RoomType, InvokerJID, MUCJID, 'APPLY', [], Opts),
                              %% notice: here From is applicant, not MUCJID
                              %% send_msg(OwnerJID, MUCBody)
                              lists:foreach(fun (Recipient) ->
                                                    To = make_jid(AppKey, Recipient, Host),
                                                    MUCBody =
                                                        make_muc_body(ApplicantJID, [To],
                                                                      MUCJID, 'APPLY',
                                                                      ErrorCode, ErrorDesc,
                                                                      reason(Reason)),
                                                    NewMUCBody =
                                                        MUCBody#'MUCBody'{
                                                          is_chatroom =
                                                              is_chatroom(RoomType)},
                                                    Meta = msync_msg:new_meta(
                                                             ApplicantJID, To,
                                                             'MUC', NewMUCBody),
                                                    ?INFO_MSG("apply meta: ~p~n", [Meta]),
                                                    msync_route:save_and_route(
                                                      ApplicantJID, To, Meta)
                                            end, Recipients)
                      end, Applicants)
    catch
        C:E ->
            ?ERROR_MSG("reply apply event error: ~p reason: ~p, "
                       "muc jid: ~p~n", [C, E, MUCJID])
    end.

reply_apply_accept(Host, AppKey, GroupID, Invoker, RoomType, Opts,
                   Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply apply accept: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Applicants = get_applicants(Opts),    
    ApplicantJIDList =
        [make_jid(AppKey, Applicant, Host) || Applicant <- Applicants],
    init_group_cursor(ApplicantJIDList, MUCJID),

    Reason = proplists:get_value(<<"reason">>, Opts),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'APPLY_ACCEPT',
                            ErrorCode, ErrorDesc, reason(Reason)),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},

    do_multi_device(RoomType, InvokerJID, MUCJID, 'APPLY_ACCEPT', ApplicantJIDList, Opts, reason(Reason)),

    lists:foreach(fun (ApplicantJID) ->
                          case send_msg(ApplicantJID, NewMUCBody) of
                              ok ->
                                  case is_send_presence(RoomType, AppKey) of
                                      true ->
                                          send_presence(ApplicantJID, MUCJID, RoomType);
                                      false ->
                                          ignore
                                  end;
                              _ ->
                                  ignore
                          end
                      end, ApplicantJIDList),

    %% notify_recipients([Invoker], Recipients -- Applicants,
    %%                   AppKey, Host, MUCBody, none),
    mod_muc_admin:sync_affiliation(MUCJID).

reply_apply_decline(Host, AppKey, GroupID, Invoker, RoomType, Opts,
                    Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply apply decline: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Applicants = get_applicants(Opts),

    %%due to SDK's implementation, reason field in #MUCBody{} must be undefined,
    %%or SDK won't prompt a right notification.
    %%Reason = proplists:get_value(<<"reason">>, Opts),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                            'APPLY_DECLINE', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    Recipients = get_recipients(MUCJID, Roles),
    ApplicantJIDList = [make_jid(AppKey, Applicant, Host) || Applicant <- Applicants],
    do_multi_device(RoomType, InvokerJID, MUCJID, 'APPLY_DECLINE', ApplicantJIDList, Opts),
    lists:foreach(fun (To) ->
                          send_msg(To, NewMUCBody)
                  end, ApplicantJIDList),
    notify_recipients([Invoker], Recipients -- Applicants,
                      AppKey, Host, NewMUCBody, none).

reply_invite(Host, AppKey, GroupID, Invoker, RoomType,
             Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply invite: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    Inviter = proplists:get_value(<<"inviter">>, Opts),
    InviterJID = make_jid(AppKey, Inviter, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    InviteeList = get_invitees(Opts),
    InviteeJIDList = [make_jid(AppKey, Name, Host) || Name <- InviteeList],
    Reason = proplists:get_value(<<"reason">>, Opts),
    MUCBody = make_muc_body(InviterJID, [], MUCJID, 'INVITE',
                            ErrorCode, ErrorDesc, reason(Reason)),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},

    init_group_cursor(InviteeJIDList, MUCJID),

    Recipients = get_recipients(MUCJID, Roles),
    do_multi_device(RoomType, InviterJID, MUCJID, 'INVITE', InviteeJIDList, Opts),
    lists:foreach(fun (To) ->
                          send_msg(To, NewMUCBody#'MUCBody'{to = [To]})
                  end, InviteeJIDList),
    notify_recipients([Invoker], Recipients -- InviteeList,
                      AppKey, Host, NewMUCBody, recipient).

reply_invite_accept(Host, AppKey, GroupID, Invoker, RoomType,
                    Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply invite accept: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    Inviter = proplists:get_value(<<"inviter">>, Opts),
    InviterJID = make_jid(AppKey, Inviter, Host),
    Invitees = get_invitees(Opts),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    InviteeJIDList =
        [make_jid(AppKey, Invitee, Host) || Invitee <- Invitees],

    %%init cursor again
    init_group_cursor(InviteeJIDList, MUCJID),

    Recipients = get_recipients(MUCJID, Roles),
    lists:foreach(fun (InviteeJID) ->
                          MUCBody = make_muc_body(InviteeJID, [InviterJID],
                                                  MUCJID, 'INVITE_ACCEPT',
                                                  ErrorCode, ErrorDesc),
                          NewMUCBody = MUCBody#'MUCBody'{
                                         is_chatroom = is_chatroom(RoomType)},
                          do_multi_device(RoomType, InviteeJID, MUCJID, 'INVITE_ACCEPT', [InviterJID], Opts),
                          send_msg(InviterJID, NewMUCBody),
                          notify_recipients(Invitees, Recipients, AppKey,
                                            Host, NewMUCBody, recipient),
                          case is_send_presence(RoomType, AppKey) of
                              true ->
                                  send_presence(InviteeJID, MUCJID, RoomType);
                              false ->
                                  ignore
                          end
                  end, InviteeJIDList),
    mod_muc_admin:sync_affiliation(MUCJID).

reply_invite_decline(Host, AppKey, GroupID, Invoker, RoomType,
                     Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply invite decline: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    Inviter = proplists:get_value(<<"inviter">>, Opts),
    InviterJID = make_jid(AppKey, Inviter, Host),
    Invitees = get_invitees(Opts),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    InviteeJID = make_jid(AppKey, Invitees, Host),
    Recipients = get_recipients(MUCJID, Roles),
    Reason = proplists:get_value(<<"reason">>, Opts),

    MUCBody = make_muc_body(InviteeJID, [InviterJID], MUCJID,
                            'INVITE_DECLINE', ErrorCode,
                            ErrorDesc, reason(Reason)),
    NewMUCBody = MUCBody#'MUCBody'{
                   is_chatroom = is_chatroom(RoomType)},

    do_multi_device(RoomType, InviteeJID, MUCJID, 'INVITE_DECLINE', [InviterJID], Opts),
    send_msg(InviterJID, NewMUCBody),
    notify_recipients([Invoker], Recipients, AppKey,
                      Host, NewMUCBody, recipient),

    clean_group_cursor([InviteeJID], MUCJID).

reply_kick(Host, AppKey, GroupID, Invoker, RoomType,
           Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply kick: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    KickList = get_kick_list(Opts),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Recipients = get_recipients(MUCJID, Roles),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                            'KICK', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},

    KickJIDList = [make_jid(AppKey, K, Host) || K <- KickList],
    do_multi_device(RoomType, InvokerJID, MUCJID, 'KICK', KickJIDList, Opts),
    lists:foreach(fun (KickJID) ->
                          send_msg(KickJID, NewMUCBody#'MUCBody'{to = [KickJID]}),
                          case is_send_presence(RoomType, AppKey) of
                              true ->
                                  send_absence(KickJID, MUCJID, RoomType);
                              false ->
                                  ignore
                          end
                  end, KickJIDList),
    notify_recipients([Invoker], Recipients -- KickList,
                      AppKey, Host, NewMUCBody, recipient),
    mod_muc_admin:sync_affiliation(MUCJID),
    clean_group_cursor(KickJIDList, MUCJID).

reply_ban(Host, AppKey, GroupID, Invoker, RoomType,
          Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply ban: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    BanList = get_ban_list(Opts),
    
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    BanJIDList = [make_jid(AppKey, BanID, Host) || BanID <- BanList],
    do_multi_device(RoomType, InvokerJID, MUCJID, 'BAN', BanJIDList, Opts),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                            'KICK', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    Recipients = get_recipients(MUCJID, Roles),

    notify_recipients([], BanList, AppKey, Host, NewMUCBody, recipient),
    notify_recipients([Invoker], Recipients -- BanList,
                      AppKey, Host, NewMUCBody, recipient),
    restart_room(MUCJID),
    mod_muc_admin:sync_affiliation(MUCJID).

reply_allow(Host, AppKey, GroupID, Invoker, RoomType,
            Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply allow: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    AllowList = get_allow_list(Opts),
    Reason = proplists:get_value(<<"reason">>, Opts),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'ALLOW',
                            ErrorCode, ErrorDesc, reason(Reason)),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    Recipients = get_recipients(MUCJID, Roles),
    AllowJIDList = [make_jid(AppKey, Name, Host) || Name <- AllowList],
    do_multi_device(RoomType, InvokerJID, MUCJID, 'ALLOW', AllowJIDList, Opts),
    lists:foreach(fun (To) ->
                          send_msg(To, NewMUCBody#'MUCBody'{to = [To]})
                  end, AllowJIDList),
    notify_recipients([Invoker], Recipients -- AllowList,
                      AppKey, Host, NewMUCBody, recipient),
    restart_room(MUCJID).

reply_block(Host, AppKey, GroupID, Invoker, RoomType,
            Opts, Roles, _ErrorCode, _ErrorDesc) ->
    ?INFO_MSG("reply block: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    do_multi_device(RoomType, InvokerJID, MUCJID, 'BLOCK', [], Opts),
    restart_room(MUCJID).

reply_unblock(Host, AppKey, GroupID, Invoker, RoomType,
              Opts, Roles, _ErrorCode, _ErrorDesc) ->
    ?INFO_MSG("reply unblock: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    do_multi_device(RoomType, InvokerJID, MUCJID, 'UNBLOCK', [], Opts),
    restart_room(MUCJID).

reply_assign_owner(Host, AppKey, GroupID, Invoker, RoomType, Opts,
                   Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply assign owner: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    NewOwner = proplists:get_value(<<"newowner">>, Opts),
    OldOwner = proplists:get_value(<<"oldowner">>, Opts),
    NewOwnerJID = make_jid(AppKey, NewOwner, Host),
    OldOwnerJID = make_jid(AppKey, OldOwner, Host),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Resource = get_resource_from_opts(Opts),
    MUCBody = make_muc_body(OldOwnerJID#'JID'{client_resource = Resource}, [NewOwnerJID], MUCJID,
                            'ASSIGN_OWNER', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    
    send_msg(OldOwnerJID, NewMUCBody),
    send_msg(NewOwnerJID, NewMUCBody),
    case get_recipients2(MUCJID, Roles) of
        all_members ->
            broadcast_msg(InvokerJID, MUCJID, NewMUCBody,
                          [InvokerJID, OldOwnerJID, NewOwnerJID]);
        Recipients ->
            notify_recipients([Invoker, OldOwner, NewOwner],
                              Recipients, AppKey, Host, NewMUCBody, none)
    end,
    restart_room(MUCJID).

reply_add_admin(Host, AppKey, GroupID, Invoker, RoomType,
                Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply add admin: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    case proplists:get_value(<<"result">>, Opts) of
        true ->
            NewAdmin = proplists:get_value(<<"newadmin">>, Opts),
            NewAdminJID = make_jid(AppKey, NewAdmin, Host),
            InvokerJID = make_jid(AppKey, Invoker, Host),
            MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
            MUCBody = make_muc_body(InvokerJID, [NewAdminJID], MUCJID,
                                    'ADD_ADMIN', ErrorCode, ErrorDesc),
            NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
            do_multi_device(RoomType, InvokerJID, MUCJID, 'ADD_ADMIN', [NewAdminJID], Opts),
            send_msg(NewAdminJID, NewMUCBody),
            case get_recipients2(MUCJID, Roles) of
                all_members ->
                    broadcast_msg(InvokerJID, MUCJID, NewMUCBody,
                                  [InvokerJID, NewAdminJID]);
                Recipients ->
                    notify_recipients([Invoker, NewAdmin], Recipients,
                                      AppKey, Host, NewMUCBody, none)
            end,
            restart_room(MUCJID);
        false ->
            ok
    end.

reply_remove_admin(Host, AppKey, GroupID, Invoker, RoomType,
                   Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply remove admin: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    case proplists:get_value(<<"result">>, Opts) of
        true ->
            OldAdmin = proplists:get_value(<<"oldadmin">>, Opts),
            OldAdminJID = make_jid(AppKey, OldAdmin, Host),
            InvokerJID = make_jid(AppKey, Invoker, Host),
            MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
            MUCBody = make_muc_body(InvokerJID, [OldAdminJID], MUCJID,
                                    'REMOVE_ADMIN', ErrorCode, ErrorDesc),
            NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
            do_multi_device(RoomType, InvokerJID, MUCJID, 'REMOVE_ADMIN', [OldAdminJID], Opts),
            send_msg(OldAdminJID, NewMUCBody),
            case get_recipients2(MUCJID, Roles) of
                all_members ->
                    broadcast_msg(InvokerJID, MUCJID, NewMUCBody,
                                  [InvokerJID, OldAdminJID]);
                Recipients ->
                    notify_recipients([Invoker, OldAdmin], Recipients,
                                      AppKey, Host, NewMUCBody, none)
            end,
            restart_room(MUCJID);
        false ->
            ok
    end.

reply_add_mute(Host, AppKey, GroupID, Invoker, RoomType,
               Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply add mute: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    RawMuteList = get_mute_list(Opts),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MuteList = [Name || {Name, _Timestamp} <- RawMuteList],
    MuteJIDList = [make_jid(AppKey, Name, Host) || Name <- MuteList],

    MUCBody = make_muc_body(InvokerJID, MuteJIDList, MUCJID,
                            'ADD_MUTE', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    do_multi_device(RoomType, InvokerJID, MUCJID, 'ADD_MUTE', MuteJIDList, Opts), 
    [ send_msg(J, NewMUCBody) || J <- MuteJIDList],
    case get_recipients2(MUCJID, Roles) of
        all_members ->
            broadcast_msg(InvokerJID, MUCJID, MUCBody,
                          [InvokerJID | MuteJIDList]);
        Recipients ->
            notify_recipients([Invoker | MuteList], Recipients,
                              AppKey, Host, MUCBody, none)
    end,
    restart_room(MUCJID).

reply_remove_mute(Host, AppKey, GroupID, Invoker, RoomType,
                  Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply remove mute: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    UnmuteList = get_members(Opts),
    UnmuteJIDList = [make_jid(AppKey, M, Host) || M <- UnmuteList],
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MUCBody = make_muc_body(InvokerJID, UnmuteJIDList, MUCJID,
                            'REMOVE_MUTE', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    do_multi_device(RoomType, InvokerJID, MUCJID, 'REMOVE_MUTE', UnmuteJIDList, Opts),
    [ send_msg(J, NewMUCBody) || J <- UnmuteJIDList],
    case get_recipients2(MUCJID, Roles) of
        all_members ->
            broadcast_msg(InvokerJID, MUCJID, NewMUCBody,
                          [InvokerJID | UnmuteJIDList]);
        Recipients ->
            notify_recipients([Invoker | UnmuteList], Recipients,
                              AppKey, Host, NewMUCBody, none)
    end,
    restart_room(MUCJID).

reply_app_admin_direct_join(Host, AppKey, GroupID, Invoker, RoomType,
                            Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply app admin direct join: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    Invitees = get_members(Opts),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    InviteeJIDList = [make_jid(AppKey, Invitee, Host) || Invitee <- Invitees],
    init_group_cursor(InviteeJIDList, MUCJID),

    Recipients = get_recipients(MUCJID, Roles),
    Op =
        case RoomType of
            <<"chatroom">> ->
                'PRESENCE';
            _ ->
                'DIRECT_JOINED'
        end,
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, Op, ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    lists:foreach(fun (InviteeJID) ->
                          send_msg(InviteeJID, NewMUCBody),
                          case is_send_presence(RoomType, AppKey) of
                              true ->
                                  send_presence(InviteeJID, MUCJID, RoomType);
                              false ->
                                  ignore
                          end,
                          notify_recipients([InvokerJID], Recipients -- Invitees,
                                            AppKey, Host, NewMUCBody, none),
                          send_chat_history(InviteeJID, MUCJID, RoomType)
                  end, InviteeJIDList),

    restart_room_for_first_one(GroupID, MUCJID, RoomType),
    mod_muc_admin:sync_affiliation(MUCJID).

%% this event is triggered by ejabberd only
reply_invite_direct_join(Host, AppKey, GroupID, Invoker, RoomType,
                         Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply invite direct join: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    Invitees = get_members(Opts),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    %% Recipients = get_recipients(MUCJID, Roles),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID,
                            'DIRECT_JOINED', ErrorCode, ErrorDesc),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    InviteeJIDList = [make_jid(AppKey, Invitee, Host) || Invitee <- Invitees],
    init_group_cursor(InviteeJIDList, MUCJID),

    lists:foreach(fun (InviteeJID) ->
                          send_msg(InviteeJID, NewMUCBody),
                          case is_send_presence(RoomType, AppKey) of
                              true ->
                                  send_presence(InviteeJID, MUCJID, RoomType);
                              false ->
                                  ignore
                          end,

                          %% notify_recipients([InvokerJID], Recipients -- Invitees,
                          %%                   AppKey, Host, MUCBody, none),

                          %% Currently, large group is open for MSync only
                          %% init_group_cursor(AppKey, InviteeJID, MUCJID)
                          send_chat_history(InviteeJID, MUCJID, RoomType)
                  end, InviteeJIDList),
    restart_room_for_first_one(GroupID, MUCJID, RoomType),
    mod_muc_admin:sync_affiliation(MUCJID).

reply_live_close_kick(Host, AppKey, GroupID, Invoker, RoomType,
                      Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply live close kick: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    KickList = get_kick_list(Opts),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'KICK',
                            ErrorCode, ErrorDesc, <<"live close kick">>),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    KickJIDList = [make_jid(AppKey, K, Host) || K <- KickList],

    do_multi_device(RoomType, InvokerJID, MUCJID, 'KICK', KickJIDList, Opts, <<"live close kick">>),
    lists:foreach(fun (KickJID) ->
                          send_msg(KickJID, NewMUCBody#'MUCBody'{to = [KickJID]})
                  end, KickJIDList),
    mod_muc_admin:sync_affiliation(MUCJID),
    clean_group_cursor(KickJIDList, MUCJID).

reply_update_announcement(Host, AppKey, GroupID, Invoker, RoomType,
                          Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply update announcement: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    Announcement = proplists:get_value(<<"announcement">>, Opts, <<>>),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'UPDATE_ANNOUNCEMENT',
                            ErrorCode, ErrorDesc, Announcement),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    do_multi_device(RoomType, InvokerJID, MUCJID, 'UPDATE_ANNOUNCEMENT', [], Opts, Announcement),
    case get_recipients2(MUCJID, Roles) of
        all_members ->
            broadcast_msg(InvokerJID, MUCJID, NewMUCBody, [InvokerJID]);
        Recipients ->
            notify_recipients([Invoker], Recipients,
                              AppKey, Host, NewMUCBody, none)
    end.

reply_delete_announcement(Host, AppKey, GroupID, Invoker, RoomType,
                          Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply delete announcement: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'DELETE_ANNOUNCEMENT',
                            ErrorCode, ErrorDesc, <<>>),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    do_multi_device(RoomType, InvokerJID, MUCJID, 'DELETE_ANNOUNCEMENT', [], Opts),
    case get_recipients2(MUCJID, Roles) of
        all_members ->
            broadcast_msg(InvokerJID, MUCJID, NewMUCBody, [InvokerJID]);
        Recipients ->
            notify_recipients([Invoker], Recipients,
                              AppKey, Host, NewMUCBody, none)
    end.

reply_upload_share_file(Host, AppKey, GroupID, Invoker, RoomType,
                          Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply upload share file: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    FileID = proplists:get_value(<<"file_id">>, Opts, <<>>),
    FileName = proplists:get_value(<<"file_name">>, Opts, <<>>),
    FileOwner = proplists:get_value(<<"file_owner">>, Opts, <<>>),
    FileSize = proplists:get_value(<<"file_size">>, Opts, <<>>),
    FileCreateTime = proplists:get_value(<<"created">>, Opts, <<>>),

    FileStr = jsx:encode([{<<"data">>, [{<<"file_id">>, FileID},
                                        {<<"file_name">>, FileName},
                                        {<<"file_owner">>, FileOwner},
                                        {<<"file_size">>, FileSize},
                                        {<<"created">>, FileCreateTime}]}]),

    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'UPLOAD_FILE',
                            ErrorCode, ErrorDesc, FileStr),
    do_multi_device(RoomType, InvokerJID, MUCJID, 'UPLOAD_FILE', [], Opts, FileStr),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},

    case get_recipients2(MUCJID, Roles) of
        all_members ->
            broadcast_msg(InvokerJID, MUCJID, NewMUCBody, [InvokerJID]);
        Recipients ->
            notify_recipients([Invoker], Recipients,
                              AppKey, Host, NewMUCBody, none)
    end.

reply_delete_share_file(Host, AppKey, GroupID, Invoker, RoomType,
                          Opts, Roles, ErrorCode, ErrorDesc) ->
    ?INFO_MSG("reply delete share file: host: ~p, app_key: ~p, group_id: ~p"
              "invoker: ~p, room_type: ~p, details: ~p, roles: ~p~n",
              [Host, AppKey, GroupID, Invoker, RoomType, Opts, Roles]),
    InvokerJID = make_jid(AppKey, Invoker, Host),
    MUCJID = make_jid(AppKey, GroupID, conference_host(Host)),
    FileID = proplists:get_value(<<"file_id">>, Opts, <<>>),
    MUCBody = make_muc_body(InvokerJID, [], MUCJID, 'DELETE_FILE',
                            ErrorCode, ErrorDesc, FileID),
    NewMUCBody = MUCBody#'MUCBody'{is_chatroom = is_chatroom(RoomType)},
    do_multi_device(RoomType, InvokerJID, MUCJID, 'DELETE_FILE', [], Opts, FileID),
    case get_recipients2(MUCJID, Roles) of
        all_members ->
            broadcast_msg(InvokerJID, MUCJID, NewMUCBody, [InvokerJID]);
        Recipients ->
            notify_recipients([Invoker], Recipients,
                              AppKey, Host, NewMUCBody, none)
    end.

%%--------------------------------------------------------------------
%% Contract with REST
%% AppKey/Invoker/RoomType/GroupID are params that must be included,
%% and also, Invoker/GroupID are only #'JID'.name indeed.
%%
%% According to msync_muc:get_muc_id_and_from/5, the generation of
%% AppKey/Invoker/GroupID is very confusing, so without digging into
%% the chaos, the existing logic is maintained.
%%
%% Reasonably speaking, AppKey should be JID#'JID'.app_key, Invoker
%% should be JID#'JID'.name, GroupID should be MUCJID#'JID'.name, but
%% probably params from upstream are not well or fully constructed due
%% to some historical facts or design flaws, this abnormal way exists.
%%
%% By design, #basicParm{} in module easemob_muc_opt won't be exposed
%% to this module, to specify an accurate spec, uncomment line below:
%% -include_lib("message_store/src/gen-erl/groupservice_types.hrl").
%%--------------------------------------------------------------------
-spec make_base_params(JID:: #'JID'{},
                       From :: #'JID'{},
                       To :: #'JID'{},
                       MUCJID :: #'JID'{},
                       BodyFrom :: #'JID'{} | undefined,
                       IsChatRoom :: true | false | undefined) ->
                              any(). %% #basicParm{}, see above
make_base_params(JID, From, To, MUCJID, BodyFrom, RoomType) ->
    ResAppKey = get_app_key(BodyFrom, From, JID),
    Invoker = get_invoker(BodyFrom, JID),
    GroupID = get_group_name(MUCJID, To),
    easemob_muc_opt:make_params(ResAppKey, Invoker, RoomType, GroupID).

-spec get_app_key(BodyFrom :: #'JID'{} | undefined,
                  From :: #'JID'{},
                  JID :: #'JID'{}) -> binary().
get_app_key(#'JID'{app_key = undefined}, #'JID'{app_key = AppKey}, _)
  when is_binary(AppKey) ->
    AppKey;
get_app_key(#'JID'{app_key = undefined}, _, #'JID'{app_key = AppKey})
  when is_binary(AppKey) ->
    AppKey;
get_app_key(undefined, #'JID'{app_key = AppKey}, _)
  when is_binary(AppKey) ->
    AppKey;
get_app_key(undefined, _, #'JID'{app_key = AppKey})
  when is_binary(AppKey) ->
    AppKey;
get_app_key(#'JID'{app_key = AppKey}, _, _) ->
    AppKey.

-spec get_invoker(BodyFrom :: #'JID'{} | undefined, JID :: #'JID'{}) -> binary().
get_invoker(#'JID'{name = undefined}, #'JID'{name = Name}) when is_binary(Name) ->
    Name;
get_invoker(#'JID'{name = Name}, _) ->
    Name;
get_invoker(undefined, #'JID'{name = Name}) when is_binary(Name) ->
    Name;
get_invoker(Name, _) ->
    Name.

-spec get_invoker_jid(BodyFrom :: #'JID'{} | undefined, JID :: #'JID'{}) -> binary().
get_invoker_jid(#'JID'{name = undefined} = BodyFrom,
                #'JID'{name = Name}) when is_binary(Name) ->
    BodyFrom#'JID'{name = Name};
get_invoker_jid(#'JID'{} = BodyFrom, _) ->
    BodyFrom;
get_invoker_jid(undefined, #'JID'{name = Name} = JID) when is_binary(Name) ->
    JID;
get_invoker_jid(BodyFrom, _) ->
    BodyFrom.

get_invoker_jid(BodyFrom, JID, From) ->
    J = get_invoker_jid(BodyFrom, JID),
    R = chain:apply(J, [{msync_msg, pb_jid_with_default_domain, [BodyFrom]},
                        {msync_msg, pb_jid_with_default_domain, [From]},
                        {msync_msg, pb_jid_with_default_domain, [JID]}]),
    ?INFO_MSG("get invoker jid bf: ~p, jid: ~p, from: ~p, j: ~p, r: ~p~n",
              [BodyFrom, JID, From, J, R]),

    chain:apply(R, [{msync_msg, pb_jid_with_default_appkey, [BodyFrom]},
                    {msync_msg, pb_jid_with_default_appkey, [From]},
                    {msync_msg, pb_jid_with_default_appkey, [JID]}]).



-spec get_group_name(MUCJID :: #'JID'{}, To :: #'JID'{}) -> binary().
get_group_name(#'JID'{name = undefined}, #'JID'{name = Name}) when is_binary(Name) ->
    Name;
get_group_name(#'JID'{name = Name}, _) ->
    Name.

get_room_type(true) ->
    chatroom;
get_room_type(_) ->
    group.

get_room_type(AppKey, GroupID) ->
    get_room_type(AppKey, GroupID, atom).

get_room_type(AppKey, GroupID, Type) ->
    RoomType = easemob_muc_redis:read_group_type(
                 <<AppKey/binary, "_", GroupID/binary>>),
    case Type of
        atom ->
            binary_to_atom(RoomType, latin1);
        binary ->
            RoomType
    end.

parse_setting(#'MUCBody.Setting'{
                 name = Name,
                 desc = Desc,
                 max_users = MaxUsers,
                 owner = Owner
                }) ->
    lists:flatmap(fun({_, undefined})  ->
                          [];
                     ({Field, Value})  ->
                          [{Field, Value}]
                  end,
                  [{title, Name}, {description, Desc},
                   {owner, Owner}, {max_users, MaxUsers}]).

extra_setting(undefined) ->
    extra_setting('PUBLIC_JOIN_OPEN');
extra_setting('PRIVATE_OWNER_INVITE') ->
    [{members_by_default, true},
     {members_only, true},
     {allow_user_invites, false},
     {public, false}];
extra_setting('PRIVATE_MEMBER_INVITE') ->
    [{members_by_default, true},
     {members_only, true},
     {allow_user_invites, true},
     {public, false}];
extra_setting('PUBLIC_JOIN_APPROVAL') ->
    [{members_by_default, true},
     {members_only, true},
     {allow_user_invites, false},
     {public, true}];
extra_setting('PUBLIC_JOIN_OPEN') ->
    [{members_by_default, true},
     {members_only, false},
     {allow_user_invites, false},
     {public, true}];
extra_setting('PUBLIC_ANONYMOUS') ->
    [{members_by_default, true},
     {members_only, false},
     {allow_user_invites, false},
     {public, true}].

decode_error({error, Code, _}) ->
    decode_error(Code);
decode_error({exception, _Code}) ->
    'UNKNOWN';
decode_error({failed, _Code, _}) ->
    'UNKNOWN';
decode_error('RESOURCE_OP_EXCEPTION') ->
    'UNKOWN';
decode_error('DUPLICATED_OP_EXCEPTION') ->
    'UNKNOWN';
decode_error('INTERNAL_SERVER_EXCEPTION') ->
    'UNKNOWN';
decode_error('EXCEED_LIMIT_EXCEPTION') ->
    'WRONG_PARAMETER';
decode_error('INVALID_PARAMETER_EXCEPTION') ->
    'WRONG_PARAMETER';
decode_error('FORBIDDEN_OP_EXCEPTION') ->
    'PERMISSION_DENIED';
decode_error('AUTHORIZATION_FAIL_EXCEPTION') ->
    'PERMISSION_DENIED';
decode_error('RESOURCE_NOT_FOUND_EXCEPTION') ->
    'MUC_NOT_EXIST';
decode_error(_Error) ->
    'UNKNOWN'.

get_members(Opts) ->
    proplists:get_value(<<"members">>, Opts, []).

get_applicants(Opts) ->
    proplists:get_value(<<"appliers">>, Opts, []).

get_invitees(Opts) ->
    proplists:get_value(<<"invitees">>, Opts, []).

get_kick_list(Opts) ->
    proplists:get_value(<<"members">>, Opts, []).

get_ban_list(Opts) ->
    proplists:get_value(<<"members">>, Opts, []).

get_allow_list(Opts) ->
    proplists:get_value(<<"members">>, Opts, []).

get_block_list(Opts) ->
    proplists:get_value(<<"members">>, Opts, []).

get_unblock_list(Opts) ->
    proplists:get_value(<<"members">>, Opts, []).

get_mute_list(Opts) ->
    proplists:get_value(<<"mute_list">>, Opts, []).

make_jid(AppKey, Name, Host) ->
    #'JID'{
       app_key = AppKey,
       name = Name,
       domain = Host
      }.

make_muc_body(From, To, MUCJID, Op, ErrorCode, ErrorDesc) ->
    make_muc_body(From, To, MUCJID, Op, ErrorCode, ErrorDesc, undefined).

make_muc_body(From, To, MUCJID, Op, ErrorCode, ErrorDesc, Reason) ->
    DefaultMUCDomainName = <<"conference.easemob.com">>,
    #'MUCBody'{
       muc_id = MUCJID#'JID'{domain = DefaultMUCDomainName},
       from = From,
       to = To,
       operation = Op,
       reason = Reason,
       status = #'MUCBody.Status'{
                   error_code = ErrorCode,
                   description = ErrorDesc
                  }
      }.

is_chatroom(<<"chatroom">>) ->
    true;
is_chatroom(_) ->
    false.

send_msg(To, #'MUCBody'{muc_id = MUCJID} = Msg) ->
    Meta = msync_msg:new_meta(MUCJID, To, 'MUC', Msg),
    ?INFO_MSG("msync muc bridge send msg to: ~p, meta: ~p~n, muc jid: ~p",
              [To, Meta, MUCJID]),
    NewMUCJID = msync_msg:add_admin_domain(MUCJID),
    msync_route:save_and_route(NewMUCJID, To, Meta).

restart_room(MUCJID) ->
    mod_muc_admin:stop_room(
      msync_msg:pb_jid_to_long_username(MUCJID), MUCJID#'JID'.domain).

send_chat_history(To, MUCJID, <<"chatroom">>) ->
    msync_muc:send_chatroom_history(MUCJID, To);
send_chat_history(_, _, _) ->
    ignore.

send_presence(From, MUCJID, RoomType) ->
    IsChatRoom = is_chatroom(RoomType),
    MUCBody = make_muc_body(From, [], MUCJID, 'PRESENCE', 'OK', <<>>),
    broadcast_msg(From, MUCJID,
                  MUCBody#'MUCBody'{is_chatroom = IsChatRoom, status = undefined},
                  []).

send_absence(From, MUCJID, RoomType) ->
    IsChatRoom = is_chatroom(RoomType),
    MUCBody = make_muc_body(From, [], MUCJID, 'ABSENCE', 'OK', <<>>),
    MUCAdmin = msync_msg:pb_jid(undefined, <<"admin">>, <<"easemob.com">>, undefined),
    broadcast_msg(MUCAdmin, MUCJID,
                  MUCBody#'MUCBody'{status = undefined, is_chatroom = IsChatRoom},
                  [From]).

broadcast_msg(From, MUCJID, MUCBody, Exclude) ->
    To = undefined,
    Meta = msync_msg:new_meta(MUCJID, To, 'MUC', MUCBody),
    NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
    case easemob_traffic_control:get_ticket(traffic_control_muc_presence) of
        ok ->
            msync_route:save(From, NewMUCJID, Meta),
            process_muc_queue:do_route(From, From, MUCJID, Meta, Exclude);
        {error, Reason} ->
            ?WARNING_MSG("muc presence traffic control happened,JID:~p,Reason:~p", [MUCJID, Reason])
    end.

restart_room_for_first_one(GroupID, MUCJID, <<"chatroom">>) ->
    try
        easemob_muc_redis:read_num_of_affiliations(GroupID)
    of
        N when is_integer(N) andalso N =< 3 ->
            restart_room(MUCJID)
    catch
        _: _ ->
            ok
    end;
restart_room_for_first_one(_, _, _) ->
    ok.

get_recipients(#'JID'{app_key = AppKey,
                      name = GroupName} = MUCJID,
               Roles) ->
    try
        case lists:member(<<"member">>, Roles) of
            true ->
                GroupID = msync_msg:pb_jid_to_long_username(MUCJID),
                Members = easemob_muc_redis:read_group_affiliations(GroupID),
                lists:map(fun (Member) ->
                                  [_AppKey, Name] = binary:split(Member, <<"_">>),
                                  Name
                          end, Members);
            false ->
                GroupID = <<AppKey/binary, "_", GroupName/binary>>,
                {ok, Result} = easemob_muc_redis:get_roles(GroupID),
                Members = [Name || {Name, _Role} <- Result],
                lists:map(fun (Member) ->
                                  case binary:split(Member, <<"_">>) of
                                      [_AppKey, Name] ->
                                          Name;
                                      _ ->
                                          Member
                                  end
                          end, Members)
        end
    catch
        C: E ->
            ?ERROR_MSG("get recipient error: ~p, reason: ~p, muc jid: ~p "
                       "stacktrace: ~p~n", [C, E, MUCJID, erlang:get_stacktrace()]),
            []
    end.

get_recipients2(#'JID'{app_key = AppKey,
                      name = GroupName} = MUCJID,
               Roles) ->
    try
        case lists:member(<<"member">>, Roles) of
            true ->
                all_members;
            false ->
                GroupID = <<AppKey/binary, "_", GroupName/binary>>,
                {ok, Result} = easemob_muc_redis:get_roles(GroupID),
                Members = [Name || {Name, _Role} <- Result],
                lists:map(fun (Member) ->
                                  case binary:split(Member, <<"_">>) of
                                      [_AppKey, Name] ->
                                          Name;
                                      _ ->
                                          Member
                                  end
                          end, Members)
        end
    catch
        C: E ->
            ?ERROR_MSG("get recipients2 error: ~p, reason: ~p, muc jid: ~p "
                       "stacktrace: ~p~n", [C, E, MUCJID, erlang:get_stacktrace()]),
            []
    end.

notify_recipients(Excludes, Recipients, AppKey, Host, MUCBody, To) ->
    lists:foreach(fun (Recipient) ->
                          RecipientJID = make_jid(AppKey, Recipient, Host),
                          NewMUCBody =
                              case To of
                                  none ->
                                      MUCBody;
                                  recipient ->
                                      MUCBody#'MUCBody'{to = [RecipientJID]}
                              end,
                          send_msg(RecipientJID, NewMUCBody)
                  end, Recipients -- Excludes).

conference_host(Host) ->
    <<"conference.", Host/binary>>.

reason(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason, latin1);
reason(Reason) ->
    Reason.

init_group_cursor(UserJIDList, MUCJID) ->
    MUCBin = msync_msg:pb_jid_to_binary(MUCJID),
    case app_config:is_read_group_cursor(MUCBin) of
        true ->
            easemob_group_cursor:init_group_cursor(
              [msync_msg:pb_jid_to_binary(J) || J <- UserJIDList], MUCBin);
        false ->
            ok
    end.

clean_group_cursor(UserJIDList, MUCJID) ->
    MUCBin = msync_msg:pb_jid_to_binary(MUCJID),
    case app_config:is_read_group_cursor(MUCBin) of
        true ->
            easemob_group_cursor:clean_group_cursor(
              [msync_msg:pb_jid_to_binary(J) || J <- UserJIDList], MUCBin);
        false ->
            ok
    end.


is_group_type(group) ->
    true;
is_group_type(_) ->
    false.


is_send_presence(<<"group">>, AppKey) ->
    app_config:is_send_group_presence(AppKey);
is_send_presence(<<"chatroom">>, AppKey) ->
    app_config:is_send_chatroom_presence(AppKey)
        andalso (not easemob_downgrade_presence:is_downgrade(AppKey)).

%% do some multi device 
do_multi_device(<<"chatroom">>, _InvokerJID, _MUCJID, _Op, _Ext, _Opts, _Reason) ->
    ignore;
do_multi_device(<<"group">>, InvokerJID, MUCJID, Op, Ext, Opts, Reason) ->
    case get_resource_from_opts(Opts) of
        undefined ->
            ignore;
        Resource ->
            InvokerJIDWithResource = InvokerJID#'JID'{client_resource = Resource},
            msync_multi_devices:send_multi_devices_muc_msg(InvokerJIDWithResource, MUCJID, Op, Ext, Reason)
    end.
do_multi_device(RoomType, InvokerJID, MUCJID, Op, Ext, Opts) ->
    do_multi_device(RoomType, InvokerJID, MUCJID, Op, Ext, Opts, <<>>).

get_resource_from_opts(Opts) ->
    case proplists:get_value(<<"resource">>, Opts) of
        false ->
            undefined;
        <<>> ->
            undefined;
        Resource ->
            Resource
    end.
