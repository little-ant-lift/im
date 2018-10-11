%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(easemob_muc).
-export([create/2,
         update/2,
         destroy/1,
         join/2,
         leave/2,
         ban/2,
         allow/2,
         block/2,
         unblock/2,
         read_group_type/1,
         read_group_pq_size/1,
         read_group_public/1,
         read_group_affiliations/1,
         read_num_of_affiliations/1,
         read_app_groups/1,
         read_user_groups/1,
         read_group_owner/1,
         read_users_in_group/1,
         read_group_outcast/1,
         read_group_mute_list/1,
         read_user_chatrooms/1
        ]).
-include("logger.hrl").
-author("wcy123@gmail.com").

%% export for testing purpose
-export([redis_query_for_create/2,
         redis_query_for_destroy/4,
         redis_query_for_join/2,
         redis_query_for_leave/2
        ]).

-define(PROCNAME, ejabberd_easemob_cache).
-define(GROUP, <<":groups">>).
-define(PUBLICGROUP, <<":publicgroups">>).
-define(AFFILIATIONS, <<":affiliations">>).
-define(MUTE, <<":mute">>).
-define(OUTCAST, <<":outcast">>).
-define(KEYPREFIX, <<"im:">>).
-define(CHATROOM, <<":chatrooms">>).
-define(USERS, <<":users">>).
-define(DEFAULT_ZADD_SCORE, 1).
%% -record(group_info,
%%         {
%%           type                    = <<"group">> :: binary(),
%%           title                   = <<"">> :: binary(),
%%           desc                    = <<"">> :: binary(),
%%           public                  = false  :: boolean(),
%%           members_only            = true :: boolean(),
%%           allow_user_invites      = true :: boolean(),
%%           max_users               = <<"200">> :: binary(),
%%           affiliations_count      = 0 :: integer(),
%%           owner                   = <<"">> :: binary(),
%%           last_modified           = <<"">> :: binary()
%%         }).

-define(TYPE_GROUP, <<"group">>).
-define(TYPE_CHATROOM, <<"chatroom">>).
-define(NS_ROOMTYPE, <<"easemob:x:roomtype">>).

create(GroupId, Opts) ->
    Q = redis_query_for_create(GroupId, Opts),
    Client = cuesport:get_worker(muc),
    case redis_qp(Client, Q) of
        {ok, _} ->
            {ok, GroupId};
        {error, Reason} ->
            {error, Reason}
    end.

update(GroupId, Opts) ->
    Q = redis_query_for_update(GroupId, Opts),
    Client = cuesport:get_worker(muc),
    case redis_qp(Client, Q) of
        {ok, _} ->
            {ok, GroupId};
        {error, Reason} ->
            {error, Reason}
    end.

destroy(GroupId) ->
    try
        Type = read_group_type(GroupId),
        IsPublic = read_group_public(GroupId),
        Affiliations = read_group_affiliations(GroupId),
        Q = redis_query_for_destroy(GroupId, Type, IsPublic, Affiliations),
        Client = cuesport:get_worker(muc),
        case redis_qp(Client, Q) of
            {ok, _} -> ok;
            {error, Reason} -> {error, Reason}
        end
    catch
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end.
join(GroupId,Who) ->
    try
        MaxUsers = read_group_max_users(GroupId),
        MemberNumber = read_num_of_affiliations(GroupId),
        if MaxUsers > MemberNumber ->
               %% to trigger group_not_found in case
               _Type = read_group_type(GroupId),
               Q = redis_query_for_join(GroupId, Who),
               Client = cuesport:get_worker(muc),
               case redis_qp(Client, Q) of
                   {ok, _} -> ok;
                   {error, Reason} -> {error, Reason}
               end;
           true ->
               {error, reach_max_users}
        end
    catch
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end.
leave(GroupId,Who) ->
    try
        %% to trigger group_not_found in case
        _Type = read_group_type(GroupId),
        Q = redis_query_for_leave(GroupId, Who),
        Client = cuesport:get_worker(muc),
        case redis_qp(Client, Q) of
            {ok, _} -> ok;
            {error, Reason} ->
                ?ERROR_MSG("error when ~p leave ~p",[Who, GroupId]),
                {error, Reason}
        end
    catch
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end.
ban(GroupId,Who) ->
    try
        %% to trigger group_not_found in case
        _Type = read_group_type(GroupId),
        Q = redis_query_for_ban(GroupId, Who),
        Client = cuesport:get_worker(muc),
        case redis_qp(Client, Q) of
            {ok, _} -> ok;
            {error, Reason} ->
                ?ERROR_MSG("error when ~p ban ~p",[Who, GroupId]),
                {error, Reason}
        end
    catch
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end.
allow(GroupId,Who) ->
    try
        %% to trigger group_not_found in case
        _Type = read_group_type(GroupId),
        Q = redis_query_for_allow(GroupId, Who),
        Client = cuesport:get_worker(muc),
        case redis_qp(Client, Q) of
            {ok, _} -> ok;
            {error, Reason} ->
                ?ERROR_MSG("error when ~p allow ~p",[Who, GroupId]),
                {error, Reason}
        end
    catch
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end.


block(GroupId,Who) ->
    try
        %% to trigger group_not_found in case
        _Type = read_group_type(GroupId),
        Q = redis_query_for_block(GroupId, Who),
        Client = cuesport:get_worker(muc),
        case redis_qp(Client, Q) of
            {ok, _} -> ok;
            {error, Reason} ->
                ?ERROR_MSG("error when ~p leave ~p",[Who, GroupId]),
                {error, Reason}
        end
    catch
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end.
unblock(GroupId,Who) ->
    try
        %% to trigger group_not_found in case
        _Type = read_group_type(GroupId),
        Q = redis_query_for_unblock(GroupId, Who),
        Client = cuesport:get_worker(muc),
        case redis_qp(Client, Q) of
            {ok, _} -> ok;
            {error, Reason} ->
                ?ERROR_MSG("error when ~p leave ~p",[Who, GroupId]),
                {error, Reason}
        end
    catch
        group_not_found ->
            ?ERROR_MSG("group not found ~p~n**stack ~p~n",
                       [GroupId, erlang:get_stacktrace()]),
            {error, group_not_found}
    end.


redis_query_for_create(GroupId, Opts) ->
    OldAffiliations = proplists:get_value(affiliations, Opts, []),
    Owner = proplists:get_value(owner, Opts, undefined),
    %%io:format("~s:~p: [~p] -- ~p~n",[?FILE, ?LINE, ?MODULE, {Owner, OldAffiliations}]),
    Affiliations =
        case lists:member(Owner, OldAffiliations) of
            true -> OldAffiliations;
            false -> [Owner | OldAffiliations]
        end,
    Type = proplists:get_value(type, Opts, ?TYPE_GROUP),
    IsPublic = proplists:get_value(public, Opts, true),
    redis_query_for_create_hmset(GroupId, Opts)
        ++
        redis_query_for_set_group_affiliations(GroupId, Affiliations)
        ++
        redis_query_for_add_groups(GroupId, Type, IsPublic)
        ++
        redis_query_for_add_user_groups(GroupId, Affiliations).


redis_query_for_update(GroupId, Opts) ->
    redis_query_for_update_hmset(GroupId, Opts).


redis_query_for_update_hmset(GroupId, Opts) ->
    [lists:flatten(
       [hmset, get_key(GroupId),
        [[ K, V] || {K,V} <- Opts ],
        last_modified, time_compat:erlang_system_time(milli_seconds)]
       )].

redis_query_for_create_hmset(GroupId, Opts) ->
    Type = proplists:get_value(type, Opts, ?TYPE_GROUP),
    Title = proplists:get_value(title, Opts, <<>>),
    Desc = proplists:get_value(description, Opts, <<>>),
    Public = proplists:get_value(public, Opts, true),
    MembersOnly = proplists:get_value(members_only, Opts, true),
    AllowUserInvites = proplists:get_value(allow_user_invites, Opts, false),
    MaxUsers = proplists:get_value(max_users, Opts, 200),
    Owner = proplists:get_value(owner, Opts, undefined),
    is_binary(Owner) orelse error(ownermissing, [GroupId, Opts]),
    [["HMSET", get_key(GroupId),
     title, Title,
     description, Desc,
     public, Public,
     members_only, MembersOnly,
     allow_user_invites, AllowUserInvites,
     max_users, MaxUsers,
      last_modified, time_compat:erlang_system_time(milli_seconds),
     type, Type,
     created, time_compat:erlang_system_time(milli_seconds),
     owner, Owner
     ]].

redis_query_for_set_group_affiliations(GroupId, Affiliations) ->
    Key = get_key(GroupId, ?AFFILIATIONS),
    [[ del, Key],
     [ zadd, Key | to_zadd_members(Affiliations) ]].
redis_query_for_add_groups(GroupId, Type, IsPublic) ->
    AppKey = get_app_key(GroupId),
    case Type of
        <<"group">> ->
            [[zadd, get_key(AppKey, ?GROUP), ?DEFAULT_ZADD_SCORE, GroupId]] ++
                case IsPublic of
                    true ->
                        [[zadd, get_key(AppKey, ?PUBLICGROUP), ?DEFAULT_ZADD_SCORE, GroupId]];
                    false ->
                        []
                end;
        <<"chatroom">> ->
            [[zadd, get_key(AppKey, ?CHATROOM), ?DEFAULT_ZADD_SCORE, GroupId]]
    end.
redis_query_for_add_user_groups(GroupId, Affiliations) ->
    lists:map(
      fun(User) ->
              [zadd, get_key(User, ?GROUP), ?DEFAULT_ZADD_SCORE, GroupId ]
      end, Affiliations).

redis_query_for_destroy(GroupId, Type, IsPublic, Affiliations) ->
    redis_query_for_destroy_del(GroupId)
        ++
        redis_query_for_destroy_del_groups(GroupId,Type, IsPublic)
        ++
        redis_query_for_destroy_del_affiliations(GroupId)
        ++
        redis_query_for_destroy_del_user_groups(GroupId, Affiliations).
redis_query_for_destroy_del(GroupId)  ->
    [[del, get_key(GroupId)]].
redis_query_for_destroy_del_groups(GroupId,Type, IsPublic) ->
    AppKey = get_app_key(GroupId),
    case Type of
        <<"group">> ->
            [[zrem, get_key(AppKey, ?GROUP), GroupId]] ++
                case IsPublic of
                    true ->
                        [[zrem, get_key(AppKey, ?PUBLICGROUP), GroupId]];
                    false ->
                        []
                end;
        <<"chatroom">> ->
            [[zrem, get_key(AppKey, ?CHATROOM), GroupId]]
    end.
redis_query_for_destroy_del_affiliations(GroupId) ->
    Key = get_key(GroupId, ?AFFILIATIONS),
    [[ del, Key]].
redis_query_for_destroy_del_user_groups(GroupId, Affiliations) ->
    lists:map(
      fun(User) ->
              [zrem, get_key(User, ?GROUP), GroupId ]
      end, Affiliations).

redis_query_for_join(GroupId, Who) ->
    [[zadd, get_key(GroupId, ?AFFILIATIONS), ?DEFAULT_ZADD_SCORE, Who],
     [zadd, get_key(Who, ?GROUP), ?DEFAULT_ZADD_SCORE, GroupId],
     [zrem, get_key(GroupId, ?OUTCAST), Who],
     [zrem, get_key(GroupId, ?MUTE), Who]
    ].
redis_query_for_leave(GroupId, Who) ->
    [[zrem, get_key(GroupId, ?AFFILIATIONS), Who],
     [zrem, get_key(Who, ?GROUP), GroupId],
     [zrem, get_key(GroupId, ?MUTE), Who]
    ].


redis_query_for_ban(GroupId, Who) ->
    [[zadd, get_key(GroupId, ?OUTCAST), ?DEFAULT_ZADD_SCORE, Who],
     [zrem, get_key(GroupId, ?AFFILIATIONS), Who]
    ].
redis_query_for_allow(GroupId, Who) ->
    [[zrem, get_key(GroupId, ?OUTCAST), Who],
     [zadd, get_key(GroupId, ?AFFILIATIONS), ?DEFAULT_ZADD_SCORE, Who]
    ].

redis_query_for_block(GroupId, Who) ->
    [[zadd, get_key(GroupId, ?MUTE), ?DEFAULT_ZADD_SCORE, Who]
     %% [zrem, get_key(Who, ?GROUP), GroupId]
    ].
redis_query_for_unblock(GroupId, Who) ->
    [[zrem, get_key(GroupId, ?MUTE), Who]
     %% [zrem, get_key(Who, ?GROUP), GroupId]
    ].


%% --------------- internal functions below ------------
read_group_type(GroupId) ->
    case read_group_prop(GroupId,type) of
        {ok, <<"group">>} ->
            <<"group">>;
        {ok, <<"chatroom">>} ->
            <<"chatroom">>;
        {ok, undefined} ->
            <<"group">>;
        {error,no_connection} ->
            throw(group_not_found)
    end.
read_group_pq_size(GroupId) ->
    try case read_group_prop(GroupId,pq_size) of
            {ok, B} when is_binary(B) ->
                binary_to_integer(B)
        end
    catch
        _:_ ->
            100
    end.
read_group_public(GroupId) ->
    case read_group_prop(GroupId,public) of
        {ok, <<"true">>} ->
            true;
        {ok, <<"false">>} ->
            false;
        {ok, undefined} ->
            throw(group_not_found);
        {error,no_connection} ->
            throw(group_not_found)
    end.
read_group_owner(GroupId) ->
    case read_group_prop(GroupId,owner) of
        {ok, Owner} when is_binary(Owner)->
            Owner;
        {ok, undefined} ->
            throw(owner_not_found);
        {error,no_connection} ->
            throw(group_not_found)
    end.

read_group_affiliations(GroupId) ->
    easemob_muc_redis:read_group_affiliations(GroupId).

read_num_of_affiliations(GroupId) ->
    easemob_muc_redis:read_num_of_affiliations(GroupId).

read_group_max_users(GroupId) ->
    Key = get_key(GroupId, ?AFFILIATIONS),
    case read_group_prop(GroupId, max_users) of
        {ok, N} when is_binary(N) ->
            binary_to_integer(N);
        {ok, undefined} ->
            throw(group_not_found);
        {error, no_connection} ->
            throw(group_not_found)
    end.

read_user_groups(User) ->
    Key = get_key(User, ?GROUP),
    Q = [ zrange, Key, 0, -1],
    Client = cuesport:get_worker(muc),
    case redis_q(Client, Q) of
        {ok, Groups}
          when is_list(Groups)->
            Groups;
        {error,no_connection} ->
            throw(group_not_found)
    end.

read_users_in_group(GroupId) ->
    Q = [zrange, get_key(GroupId, ?USERS), 0, -1],
    Client = cuesport:get_worker(muc),
    case redis_q(Client, Q) of
        {ok, Users }
          when is_list(Users) ->
            Users
    end.

read_group_outcast(GroupId) ->
    Q = [zrange, get_key(GroupId, ?OUTCAST), 0, -1],
    Client = cuesport:get_worker(muc),
    case redis_q(Client, Q) of
        {ok, Users }
          when is_list(Users) ->
            Users
    end.

read_group_mute_list(GroupId) ->
    Q = [zrange, get_key(GroupId, ?MUTE), 0, -1],
    Client = cuesport:get_worker(muc),
    case redis_q(Client, Q) of
        {ok, Users }
          when is_list(Users) ->
            Users
    end.



read_group_prop(GroupId,Prop) ->
    Q = [hget, get_key(GroupId), Prop],
    Client = cuesport:get_worker(muc),
    redis_q(Client, Q).

read_app_groups(AppKey)
  when is_binary(AppKey) ->
    Key = get_key(AppKey, ?GROUP),
    Q = [zrange, Key, 0, -1],
    Client = cuesport:get_worker(muc),
    case redis_q(Client, Q) of
        {ok, Groups} when is_list(Groups)->
            Groups;
        {ok, undefined} ->
            %% todo: zrange return [] if Key does not exists, so
            %% never goes here.
            throw(group_not_found)
    end.

read_user_chatrooms(User) ->
    Key = get_key(User, ?CHATROOM),
    Q = ["ZRANGE", Key, 0, -1],
    Client = cuesport:get_worker(muc),
    case redis_q(Client, Q) of
        {ok, Chatrooms}
          when is_list(Chatrooms)->
            Chatrooms;
        {error,no_connection} ->
            []
    end.

get_key(GroupId) ->
   << ?KEYPREFIX/binary, GroupId/binary >>.

get_key(GroupId, Prefix) ->
   << ?KEYPREFIX/binary, GroupId/binary, Prefix/binary >>.

get_app_key(Jid) ->
    JidStr = binary_to_list(Jid),
    AppKey = string:substr(JidStr, 1, string:str(JidStr,"_") -1),
    list_to_binary(AppKey).

redis_q(Client, P) ->
    case eredis:q(Client, P) of
        {error, no_connection} ->
            ?ERROR_MSG("error to exec group redis operation:~p reason:no_connection", [P]),
            {error, no_connection};
        {error, Reason} ->
            ?ERROR_MSG("error to exec group redis operation:~p reason:~p", [P, Reason]),
            {error, Reason};
        Value ->
            ?DEBUG("muc redis op: ~ninput:~p~noutput:~p~n",
                   [P, Value]),
            Value
    end.
redis_qp(Client, P) ->
    case eredis:qp(Client, P) of
        {error, no_connection} ->
            ?ERROR_MSG("error to exec group redis operation:~p reason:no_connection", [P]),
            {error, no_connection};
        RetList when is_list(RetList) ->
            case lists:foldl(
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
                   RetList) of
                ok ->
                    ?DEBUG("muc redis op: ~ninput:~p~noutput:~p~n",
                           [P, RetList]),
                    {ok,RetList};
                {error, Reason} ->
                    {error, Reason}
            end;
        Value ->
            ?DEBUG("muc redis op: ~ninput:~p~noutput:~p~n",
                   [P, Value]),
            Value
    end.


to_zadd_members(List) ->
    lists:flatmap(fun(N) -> [?DEFAULT_ZADD_SCORE, N] end, List).
