-module(process_roam).

-export([handle/3]).

-include("pb_msync.hrl").

handle(#'CommSyncUL'{queue = undefined}, Response, _JID) ->
    CommSyncDL = #'CommSyncDL'{is_roam = true},
    msync_msg:set_status(Response#'MSync'{payload = CommSyncDL},
                         'FAIL', <<"no queue">>);

handle(#'CommSyncUL'{meta = undefined}, Response, _JID) ->
    CommSyncDL = #'CommSyncDL'{is_roam = true},
    msync_msg:set_status(Response#'MSync'{payload = CommSyncDL},
                         'FAIL', <<"no meta">>);

handle(#'CommSyncUL'{
          meta = #'Meta'{id = MetaID},
          queue = Queue,
          key = Start,
          last_full_roam_key = End},
       Response, JID) ->
    case
        message_store:read_roam_message(
          msync_msg:pb_jid_to_binary(Queue#'JID'{client_resource = undefined}),
          msync_msg:pb_jid_to_binary(JID#'JID'{client_resource = undefined}),
          get_key(Start),
          get_key(End))
    of
        {error, Error} ->
            CommSyncDL = #'CommSyncDL'{is_roam = true},
            msync_msg:set_status(Response#'MSync'{payload = CommSyncDL},
                                 'FAIL', Error);
        {Messages, NextKey} ->
            Metas = [msync_msg:decode_meta(M) || M <- Messages],
            CommSyncDL = #'CommSyncDL'{
                            is_roam = true,
                            meta_id = MetaID,
                            server_id = msync_uuid:generate_msg_id(),
                            queue = Queue,
                            metas = Metas,
                            next_key = NextKey,
                            is_last = is_last(NextKey),
                            timestamp = time_compat:erlang_system_time(milli_seconds)
                           },
            msync_msg:set_status(Response#'MSync'{payload = CommSyncDL},
                                 'OK', <<>>)
    end.

get_key(undefined) ->
    undefined;
get_key(Key) ->
    integer_to_binary(Key).

is_last(undefined) ->
    true;
is_last(_) ->
    false.
