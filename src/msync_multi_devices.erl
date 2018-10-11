%%%-------------------------------------------------------------------
%%% @author zhangchao <zhangchao@easemob.com>
%%% @copyright (C) 2017, zhangchao
%%% @doc
%%%
%%% @end
%%% Created :  7 Apr 2017 by zhangchao <zhangchao@easemob.com>
%%%-------------------------------------------------------------------
-module(msync_multi_devices).

%% API
-export([
         send_multi_devices_muc_msg/5
        ,send_multi_devices_roster_msg/4
        ]).

-include("logger.hrl").
-include("pb_rosterbody.hrl").

%%%===================================================================
%%% API
%%%===================================================================
send_multi_devices_muc_msg(InvokerJID, MUCJIDBase, Op, Ext, Reason) ->
    MUCJID = MUCJIDBase#'JID'{domain = <<"conference.easemob.com">>},
    case application:get_env(message_store, enable_multi_devices_roster_and_group, false) of
        true ->
            InvokerBin = msync_msg:pb_jid_to_binary(InvokerJID),
            case app_config:is_multi_resource_enabled(InvokerBin) of
                true ->
                    Meta = msync_multi_devices_muc:make_muc_meta(InvokerJID, Ext, MUCJID, Op, Reason),
                    ?DEBUG("msync muc multi devices send msg to: ~p, meta: ~p~n, muc jid: ~p",
                           [InvokerJID, Meta, MUCJID]),
                    NewMUCJID = msync_msg:admin_muc_jid(MUCJID),
                    save_and_route_msg(NewMUCJID, InvokerJID, Meta);
                false ->
                    ignore
            end;
        false ->
            ignore
    end.

send_multi_devices_roster_msg(InvokerJID, TargetJID, Op, Ext) ->
    case application:get_env(message_store, enable_multi_devices_roster_and_group, false) of
        true ->
            InvokerBin = msync_msg:pb_jid_to_binary(InvokerJID),
            case app_config:is_multi_resource_enabled(InvokerBin) of
                true ->
                    Meta = msync_multi_device_roster:make_roster_meta(Op, TargetJID, InvokerJID, Ext),
                    ?DEBUG("msync roster multi devices send msg to: ~p, meta: ~p~n, target jid: ~p",
                           [InvokerJID, Meta, TargetJID]),
                    SystemQueue = InvokerJID#'JID'{
                                    app_key = undefined, name = undefined,
                                    client_resource = undefined
                                   },
                    save_and_route_msg(SystemQueue, InvokerJID, Meta);
                false ->
                    ignore
            end;
        false ->
            ignore
    end.

save_and_route_msg(FromJID, ToJID, Meta) ->
    msync_route:save(FromJID, ToJID, Meta),
    ul_packet_filter:multi_devices(ToJID, FromJID, Meta).

%%%===================================================================
%%% Internal functions
%%%===================================================================
