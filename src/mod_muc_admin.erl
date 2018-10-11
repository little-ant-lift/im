-module(mod_muc_admin).
-include("logger.hrl").
-include("pb_jid.hrl").
-export([stop_room/2, sync_affiliation/1]).

stop_room(Name, Host) ->
    %% check if the room process is already exists on server. in muc_online_room
    %% If the room does not exist yet in the muc_online_room
    case muc_mnesia:rpc_get_online_room(Name, Host) of
        [{_,_,Pid}] ->

            ?DEBUG("try to destroy room:~p, pid:~p", [Name, Pid]),
            muc_mnesia:rpc_delete_online_room(Host, Name, Pid),
            Pid ! shutdown,
            ?DEBUG("room ~p is deleted from processes", [Name]);
        [] ->
            ?DEBUG("room ~p is not running, exit", [Name]),
            ok
    end.


sync_affiliation(#'JID'{} = MUCJID) ->
    Service = MUCJID#'JID'.domain,
    RoomName = msync_msg:pb_jid_to_long_username(MUCJID),
    sync_affiliation(RoomName, Service).

sync_affiliation(GroupId, Service) ->
    [_, Domain]  = binary:split(Service, <<".">>),
    case muc_mnesia:rpc_get_online_room(GroupId, Service) of
        [{_,_,Pid}] ->
            Affs = get_affiliations(Domain, GroupId),
            case is_list(Affs) of
                true ->
                    gen_fsm:send_all_state_event(Pid, {set_all_affiliations, dict:from_list(Affs)});
                _ ->
                    ok
            end;
        _ ->
            ok
    end.


get_affiliations(Server, GroupId) ->
    try
        Owner = easemob_muc:read_group_owner(GroupId),
        Members = easemob_muc:read_group_affiliations(GroupId),
        MuteMembers = easemob_muc:read_group_mute_list(GroupId),
        Outcasts = easemob_muc:read_group_outcast(GroupId),
        Affiliations = lists:filtermap(
                         fun(Member) ->
                                 case Owner == Member of
                                     true ->
                                         {true, {{Member, Server, <<>>}, {owner, <<>>}}};
                                     false ->
                                         case (lists:member(Member, MuteMembers)) of
                                             true ->
                                                 {true, {{Member, Server, <<>>}, {admin, <<>>}}};
                                             _ ->
                                                 {true, {{Member, Server, <<>>}, {member, <<>>}}}
                                         end
                                 end
                         end,
                         Members),

        AffWithOutcasts = lists:foldl(
                            fun(Outcast, Affs) ->
                                    [{{Outcast, Server, <<>>}, {outcast, <<>>}} | Affs]
                            end,
                            Affiliations,
                            Outcasts),
        AffWithOutcasts
    catch
        Class:Type ->
            ?WARNING_MSG("~p:~p Server = ~p, GroupId = ~p, StackTrace: ~p", [Class, Type, Server, GroupId, erlang:get_stacktrace()])
    end.
