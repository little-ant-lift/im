-module(process_unread).
-export([handle/3]).
-include("logger.hrl").
-include("pb_msync.hrl").
handle(Request, Response, JID) ->
    ReceiveTimeStamp = time_compat:erlang_system_time(milli_seconds),
    Response1 = handle_get_unread(Request,Response,JID),
    Response2 = set_timestamp(Response1, ReceiveTimeStamp),
    Response2.

handle_get_unread(Request,Response,JID) ->
    case msync_offline_msg:get_unread_numbers(JID) of
        {0, _} ->
            return_no_unread(Request, Response, JID);
        {Total, List } ->
            return_unread_list(Total,List, Response, JID)
    end.
return_no_unread(_Request, Response, JID) ->
    ?DEBUG("process getunread for ~p, no unread message",
           [msync_msg:pb_jid_to_binary(JID)]),
    chain:apply(
      Response,
      [
       {msync_msg, set_status,['OK', undefined]}
      ]).
return_unread_list(Total, List, Response, JID) ->
    ?DEBUG("process getunread for ~p, ~p unread messages in ~p queues",
           [msync_msg:pb_jid_to_binary(JID), Total, erlang:length(List)]),
    chain:apply(
      Response,
      [
       {msync_msg, set_number_of_unread_metas, [Total, List]},
       {msync_msg, set_status, ['OK',undefined]}
      ]).
set_timestamp(#'MSync'{ payload = #'CommUnreadDL'{} = UnreadDL} = MSync, ReceiveTimeStamp) ->
    Now = time_compat:erlang_system_time(milli_seconds),
    ResponseTimestamp = (Now + ReceiveTimeStamp) div 2,
    MSync#'MSync'{
      payload = UnreadDL#'CommUnreadDL'{timestamp = ResponseTimestamp}}.
