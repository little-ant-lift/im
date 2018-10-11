%%%-------------------------------------------------------------------
%%% @author clanchun <clanchun@gmail.com>
%%% @copyright (C) 2017, clanchun
%%% @doc
%%%
%%% @end
%%% Created : 28 Aug 2017 by clanchun <clanchun@gmail.com>
%%%-------------------------------------------------------------------
-module(easemob_sync_lib).

%% API

%% Producer side
-export([produce_message_full/3,
         produce_roster_full/3,
         produce_privacy_full/3
        ]).

%% Consumer side
-export([consume_message_full/1,
         consume_roster_full/1,
         consume_privacy_full/1,
         consume_message_incr/1,
         consume_roster_incr/1,
         consume_privacy_incr/1
        ]).

-export([producer_name/1,
         consumer_name/1
        ]).

-define(DOMAIN, <<"easemob.com">>).

%%%===================================================================
%%% API
%%%===================================================================
produce_message_full(ClientID, Topic, User) ->
    UserDomain = <<User/binary, "@", ?DOMAIN/binary>>,
    Resources = easemob_resource:get_resources(UserDomain),

    lists:foreach(fun (Resource) ->
                          UserDomainRes = <<UserDomain/binary, "/", Resource/binary>>,
                          UnreadCIDLenList = easemob_offline_unread:get_unread(UserDomainRes),
                          UnreadCIDList = [UnreadCID || {UnreadCID, _} <- UnreadCIDLenList],

                          lists:foreach(fun (CID) ->
                                                Indices = get_indices(UserDomainRes, CID),
                                                Bodies = get_bodies(Indices),
                                                lists:foreach(
                                                  fun ({_, not_found}) ->
                                                          ignore;
                                                      ({MID, Body}) ->
                                                          Data = [{user, UserDomainRes},
                                                                  {cid, CID},
                                                                  {mid, MID},
                                                                  {body, Body}],
                                                          easemob_kafka:produce_sync(
                                                            ClientID,
                                                            Topic,
                                                            fun easemob_kafka:which_partition/4,
                                                            User,
                                                            term_to_binary(Data))
                                                  end, lists:zip(Indices, Bodies))
                                        end, UnreadCIDList)
                  end, Resources),
    ok.

produce_roster_full(ClientID, Topic, User) ->
    case easemob_roster:get_roster(User, ?DOMAIN) of
        error ->
            ignored;
        [] ->
            ignored;
        Rosters ->
            Data = [{user, User}, {rosters, Rosters}],
            easemob_kafka:produce_sync(ClientID,
                                       Topic,
                                       fun easemob_kafka:which_partition/4,
                                       User,
                                       term_to_binary(Data)),
            ok
    end.

produce_privacy_full(ClientID, Topic, User) ->
    case easemob_privacy:read_privacy(User, ?DOMAIN) of
        not_found ->
            ignored;
        Privacy ->
            Data = [{user, User}, {privacy, Privacy}],
            easemob_kafka:produce_sync(ClientID,
                                       Topic,
                                       fun easemob_kafka:which_partition/4,
                                       User,
                                       term_to_binary(Data)),
            ok
    end.

consume_message_full(Data) ->
    User = proplists:get_value(user, Data),
    CID = proplists:get_value(cid, Data),
    MID = proplists:get_value(mid, Data),
    Body = proplists:get_value(body, Data),

    case utils:is_group(CID) of
        true ->
            case easemob_group_cursor:is_large_group(CID) of
                true ->
                    easemob_group_msg_cursor:write_group_msg(
                      CID, undefined, MID, undefined),
                    easemob_offline_unread:inc_unread(User, CID),
                    easemob_offline_unread:inc_total(User);
                false ->
                    case is_member(MID, User, CID) of
                        true ->
                            ignore;
                        false ->
                            easemob_offline_index:write_message_index(CID, User, MID, 200)
                    end
            end;
        false ->
            case is_member(MID, User, CID) of
                true ->
                    ignore;
                false ->
                    easemob_offline_index:write_message_index(CID, User, MID, 200)
            end
    end,
    easemob_message_body:write_message(MID, Body),
    ok.

consume_roster_full(Data) ->
    User = proplists:get_value(user, Data),
    Rosters = proplists:get_value(rosters, Data),
    easemob_roster_cache:write_rosters(User, Rosters),
    ok.

consume_privacy_full(Data) ->
    User = proplists:get_value(user, Data),
    Privacy = proplists:get_value(privacy, Data),
    easemob_privacy:write_privacy(User, ?DOMAIN, Privacy),
    ok.

consume_message_incr(Data) ->
    Direction = proplists:get_value(direction, Data),
    case Direction of
        outgoing_body ->
            consume_message_incr_outgoing_body(Data);
        outgoing_index ->
            consume_message_incr_outgoing_index(Data);
        ack ->
            consume_message_incr_ack(Data)
    end,
    ok.

consume_roster_incr(Data) ->
    User = proplists:get_value(user, Data),
    Type = proplists:get_value(type, Data),
    RosterList = proplists:get_value(list, Data),
    msync_roster:handle_sync(User, Type, RosterList),
    ok.

consume_privacy_incr(Data) ->
    User = proplists:get_value(user, Data),
    Type = proplists:get_value(type, Data),
    PrivacyList = proplists:get_value(list, Data),
    msync_roster:handle_sync(User, Type, PrivacyList),
    ok.

producer_name(ClientID) ->
    binary_to_atom(<<(atom_to_binary(ClientID, utf8))/binary, "_producer">>, utf8).

consumer_name(ClientID) ->
    binary_to_atom(<<(atom_to_binary(ClientID, utf8))/binary, "_consumer">>, utf8).

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------

%%%===================================================================
%%% Internal functions
%%%===================================================================
get_indices(User, CID) ->
    case utils:is_group(CID) of
        true ->
            case easemob_group_cursor:is_large_group(CID) of
                true ->
                    CurCursor =
                        case easemob_user_cursor:get_cursor(User, CID) of
                            undefined ->
                                <<>>;
                            <<"undefined">> ->
                                <<>>;
                            Cur -> Cur
                        end,
                    easemob_group_msg_cursor:get_index_after_mid(CID, CurCursor, 200);
                false ->
                    easemob_offline_index:read_message_index(User, CID, 200)
            end;
        false ->
            easemob_offline_index:read_message_index(User, CID, 200)
    end.

get_bodies(Indices) ->
    [message_store:read_message(MID) || MID <- Indices].

consume_message_incr_outgoing_body(Data) ->
    From = proplists:get_value(from, Data),
    To = proplists:get_value(to, Data),
    MID = proplists:get_value(mid, Data),
    Packet = proplists:get_value(packet, Data),
    ChatType = proplists:get_value(type, Data),
    AppKey = proplists:get_value(appkey, Data),
    message_store:user_send_message(From, To, Packet, MID, ChatType, AppKey),
    ok.

consume_message_incr_outgoing_index(Data) ->
    From = proplists:get_value(from, Data),
    To = proplists:get_value(to, Data),
    ChatType = proplists:get_value(type, Data),
    MID = proplists:get_value(mid, Data),
    AppKey = proplists:get_value(appkey, Data),
    case utils:is_group(From) andalso easemob_group_cursor:is_large_group(From) of
        true ->
            easemob_group_msg_cursor:write_group_msg(From, From, MID, AppKey),
            easemob_offline_unread:inc_unread(To, From),
            easemob_offline_unread:inc_total(To);
        false ->
            case is_member(MID, To, From) of
                true ->
                    ignore;
                false ->
                    MaxLen = easemob_offline_shard:get_maxlen(ChatType),
                    easemob_offline_index:write_message_index(From, To, MID, MaxLen)
            end
    end,
    ok.

consume_message_incr_ack(Data) ->
    User = proplists:get_value(user, Data),
    Resource = proplists:get_value(resource, Data),
    CID = proplists:get_value(cid, Data),
    MID = proplists:get_value(mid, Data),
    message_store:delete_message(User, Resource, CID, MID).

is_member(MID, User, CID) ->
    IndexKey = easemob_offline_index:get_index_key(User, CID),
    {ok, List} = easemob_redis:q(index, [lrange, IndexKey, 0, -1]),
    lists:member(MID, List).
