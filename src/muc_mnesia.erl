-module(muc_mnesia).
-export([rpc_get_online_room/1, rpc_get_online_room/2, rpc_delete_online_room/3]).
-include("pb_jid.hrl").
-include("jlib.hrl").
-author('jma@easemob.com').

rpc_get_online_room(Room) when is_list(Room) ->
    rpc_get_online_room(list_to_binary(Room));
rpc_get_online_room(Room) when is_binary(Room) ->
    rpc_get_online_room(jlib:string_to_jid(Room));
rpc_get_online_room(#jid{} = Room) ->
    Name = Room#jid.user,
    Host = Room#jid.server,
    rpc_get_online_room(Name,Host);
rpc_get_online_room(#'JID'{} = Room) ->
    Name = msync_msg:pb_jid_to_long_username(Room),
    Host = Room#'JID'.domain,
    rpc_get_online_room(Name,Host).

rpc_get_online_room(Room, Host) ->
    ejabberd_store:store_rpc(muc, muc_mnesia, get_online_room, [Room, Host]).

rpc_delete_online_room(Host, Room, Pid) ->
    ejabberd_store:store_rpc(muc, muc_mnesia, delete_online_room, [Host, Room, Pid]).
