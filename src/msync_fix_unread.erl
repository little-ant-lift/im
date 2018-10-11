-module(msync_fix_unread).
-export([dec/2, inc/2, set/3, get/1, get/2, clr/2]).
-include("pb_msync.hrl").
dec(JIDOwnerBase, JIDConversation) ->
    JIDOwner = get_user_resource_owner(JIDOwnerBase),
    KOwner = get_redis_key(msync_msg:pb_jid_to_binary(JIDOwner)),
    KConversation = msync_msg:pb_jid_to_binary(JIDConversation#'JID'{client_resource = undefined}),
    case msync_redis:q(index, [hincrby, KOwner, KConversation, -1]) of
        {ok, <<"0">>} ->
            msync_redis:q(index, [hdel, KOwner, KConversation]),
            {ok, <<"0">>};
        Other ->
            %% no error handling. see msync_redis_q
            Other
    end.

inc(JIDOwnerBase, JIDConversation) ->
    JIDOwner = get_user_resource_owner(JIDOwnerBase),
    KOwner = get_redis_key(msync_msg:pb_jid_to_binary(JIDOwner)),
    KConversation = msync_msg:pb_jid_to_binary(JIDConversation#'JID'{client_resource = undefined}),
    case msync_redis:q(index, [hincrby, KOwner, KConversation, 1]) of
        {ok, <<"0">>} ->
            msync_redis:q(index, [hdel, KOwner, KConversation]);
        Other ->
            %% no error handling. see msync_redis_q
            Other
    end.

set(JIDOwnerBase, JIDConversation, N) ->
    JIDOwner = get_user_resource_owner(JIDOwnerBase),
    KOwner = get_redis_key(msync_msg:pb_jid_to_binary(JIDOwner)),
    KConversation = msync_msg:pb_jid_to_binary(JIDConversation#'JID'{client_resource = undefined}),
    msync_redis:q(index, [hset, KOwner, KConversation, N]).


get(JIDOwnerBase,JIDConversation) ->
    JIDOwner = get_user_resource_owner(JIDOwnerBase),
    KOwner = get_redis_key(msync_msg:pb_jid_to_binary(JIDOwner)),
    KConversation = msync_msg:pb_jid_to_binary(JIDConversation#'JID'{client_resource = undefined}),
    case msync_redis:q(index, [hget, KOwner, KConversation]) of
        {ok, N} ->
            {ok, binary_to_integer(N)};
        Other ->
            %% no error handling. see msync_redis_q
            Other
    end.

get(JIDOwnerBase) ->
    JIDOwner = get_user_resource_owner(JIDOwnerBase),
    KOwner = get_redis_key(msync_msg:pb_jid_to_binary(JIDOwner)),
    case msync_redis:q(index, [hgetall, KOwner]) of
        {ok, R} when is_list(R) ->
            {ok,
             lists:filtermap(
               fun({<<"_", _Other/binary>>, _N2}) ->
                       false;
                  ({Name, N}) ->
                       {true, {msync_msg:parse_jid(Name), binary_to_integer(N)}}
               end, list2plist(R))};
        Other ->
            %% no error handling. see msync_redis_q
            Other
    end.

clr(JIDOwnerBase, JIDConversation) ->
    JIDOwner = get_user_resource_owner(JIDOwnerBase),
    KOwner = get_redis_key(msync_msg:pb_jid_to_binary(JIDOwner)),
    KConversation = msync_msg:pb_jid_to_binary(JIDConversation#'JID'{client_resource = undefined}),
    msync_redis:q(index, [hdel, KOwner, KConversation]).


get_redis_key(User) ->
    <<"unread:", User/binary>>.


list2plist(L) ->
    list2plist(L,[]).
list2plist([], Acc) ->
    lists:reverse(Acc);
list2plist([K], Acc) ->
    lists:reverse([{K,undefined} | Acc]);
list2plist([K,V|T], Acc) ->
    list2plist(T, [{K,V} | Acc]).

get_user_resource_owner(JIDOwnerBase) ->
    JIDOwnerDomain = msync_msg:pb_jid_to_binary(JIDOwnerBase#'JID'{client_resource = undefined}),
    Resource = easemob_resource:get_user_resource(JIDOwnerDomain, JIDOwnerBase#'JID'.client_resource),
    JIDOwnerBase#'JID'{client_resource = Resource}.
