-module(msync_offline_msg).
-export([
         get_unread_numbers/1,
         get_unread_metas/4,
         route_offline/3,
         delete_read_messages/3,
         ignore_resource/1
         %% retrieve/3
        ]).

%% Large group (group cursor)
-export([get_large_group_unread_metas/4,
         delete_large_group_messages/3,
         delete_group_admin_messages/3
        ]).

%% Group migration API
-export([get_group_messages_migration/4,
         delete_group_messages_migration/3
        ]).

-include("logger.hrl").
-include("pb_msync.hrl").
-include_lib("message_store/include/message_store.hrl").

get_unread_numbers(#'JID'{} = JID) ->
    %% offline database does not includes resources
    To = msync_msg:pb_jid_to_binary(ignore_resource(JID)),
    UnreadList = message_store:load_unread_list(To, JID#'JID'.client_resource),
    UnreadList2 =
        lists:filtermap(
          fun
              ({From,N}) ->
                  try
                      {true, {msync_msg:parse_jid(From) , N}}
                  catch
                      error:{nonvalid_jid, Reason} ->
                          ?ERROR_MSG("cannot parse the queue '~s' of '~s'~n"
                                     "\tReason = ~p~n",
                                     [To, From, Reason]),
                        false
                end
        end,
        UnreadList),
    {ZeroUnreadList, NonZeroUnreadList} =
        lists:partition(
          fun({_, Nx}) when Nx =< 0 ->
                  true;
             ({_, _}) ->
                  false
          end, UnreadList2),
    %% don't care about whether it is fixed or not, fix it in next
    maybe_fix_unread(JID, ZeroUnreadList, application:get_env(msync, enable_fix_unread, false)),
    UnreadList3 = lists:map(fun({Jx, Nx}) ->
                                    {msync_msg:save_bw_jid(JID,Jx), Nx, undefined}
                            end, NonZeroUnreadList),
    ?DEBUG("get unread list: Owner = ~p, UnreadList = ~p UnreadList3(Filtered) = ~p ZeroUnreadList = ~p~n",[JID, UnreadList, UnreadList3, ZeroUnreadList]),
    Total = lists:foldl(
              fun
                  ({_From, N, _Key}, Acc)-> Acc + N
              end, 0,
              UnreadList3),
    { Total, UnreadList3}.

get_unread_metas(Owner,Queue,Key,N) ->
    Key2 =
        case Key of
            undefined -> undefined;
            _ -> integer_to_binary(Key)
        end,
    {Metas, NextKeyBinary} =
        message_store:get_unread_messages(
          msync_msg:pb_jid_to_binary(ignore_resource(Queue)), % From
          msync_msg:pb_jid_to_binary(ignore_resource(Owner)), % To
          Owner#'JID'.client_resource,
          Key2,
          N),

    NextKey = next_key(NextKeyBinary),
    ?DEBUG("get unread messages:~n"
           "\t Owner = ~p~n"
           "\t Queue = ~p~n"
           "\t Key = ~p~n"
           "\t N = ~p~n"
           "\t Metas = ~p~n"
           "\t NextKey = ~p~n",
           [Owner, Queue, Key, N, Metas, NextKey]),

    {decode_meta(Metas, Owner), NextKey}.

-spec get_large_group_unread_metas(Owner :: #'JID'{},
                                   Queue :: #'JID'{},
                                   Key :: binary() | undefined,
                                   N :: pos_integer()) ->
                                          {list(), pos_integer() | undefined}.
get_large_group_unread_metas(OwnerBase, Queue, Key, N) ->
    Resource = easemob_resource:get_user_resource(
                 msync_msg:pb_jid_to_binary(OwnerBase#'JID'{client_resource = undefined}),
                 OwnerBase#'JID'.client_resource),
    Owner = OwnerBase#'JID'{client_resource = Resource},
    {Metas, NextKey} =
        message_store:get_large_group_unread_messages(
          msync_msg:pb_jid_to_binary(ignore_resource(Queue)),
          msync_msg:pb_jid_to_binary(Owner),
          Key, N),

    ?DEBUG("get unread messages:~n"
           "\t Owner = ~p~n"
           "\t Queue = ~p~n"
           "\t Key = ~p~n"
           "\t N = ~p~n"
           "\t Metas = ~p~n"
           "\t NextKey = ~p~n",
           [Owner, Queue, Key, N, Metas, next_key(NextKey)]),

    {decode_meta(Metas, Owner), next_key(NextKey)}.

decode_meta(Metas, Owner) ->
    lists:filtermap(
      fun(M) ->
              try msync_msg:decode_meta(M) of
                  #'Meta'{from = Owner} ->
                      false;
                  #'Meta'{} = Meta ->
                      is_valid_meta(Meta) andalso {true, Meta}
              catch
                  error:{case_clause,Reason} ->
                      ?ERROR_MSG("lost message.\n"
                                 "\tOwner = ~p\n"
                                 "\tMeta = ~p\n"
                                 "\tReason = ~p\n",
                                 [Owner, M, Reason]),
                      false;
                  error:function_clause ->
                      ?ERROR_MSG("lost message.\n"
                                 "\tOwner = ~p\n"
                                 "\tMeta = ~p\n"
                                 "\tStack = ~p\n",
                                 [Owner, M, erlang:get_stacktrace()]),
                      false;
                  Class:Type ->
                      ?ERROR_MSG("~p:~p: lost message.\n"
                                 "\tOwner = ~p\n"
                                 "\tMeta = ~p\n"
                                 "\tStack = ~p\n",
                                 [Class, Type, Owner, M, erlang:get_stacktrace()]),
                      false

              end
      end, Metas).

next_key(undefined) ->
    undefined;
next_key(NextKeyBin) ->
    binary_to_integer(NextKeyBin).

is_valid_meta(Meta) ->
    lists:foldl(
      fun(F, Acc) ->
              Acc andalso F(Meta)
      end, true,
      [fun is_valid_meta_check_namespace/1,
       fun is_valid_meta_check_expiration/1]).
is_valid_meta_check_namespace(#'Meta'{ id = MID, ns = undefined }) ->
    ?ERROR_MSG("lost message. no ns. MID = ~p\n", [MID]),
    false;
is_valid_meta_check_namespace(_) ->
    true.

is_valid_meta_check_expiration(#'Meta'{ id = MID, timestamp = Timestamp, ns = 'CONFERENCE' })
  when is_integer(Timestamp)->
    Expiration_ms = application:get_env(msync, conference_expiration_ms, 10000),
    Now_ms = time_compat:erlang_system_time(milli_seconds),
    IsExpired = Timestamp + Expiration_ms <  Now_ms,
    case IsExpired of
        true ->
            ?INFO_MSG("lost message. expired. MID = ~p~n",[MID]),
            false;
        false ->
            true
    end;
is_valid_meta_check_expiration(_)->
    true.

%% initially, Key = undefined, SDK has no idea whic metas are deleted.
delete_read_messages(_Owner, _Queue, undefined = _Key) ->
    [];
delete_read_messages(_Owner, _Queue, <<"">> = _Key) ->
    [];
delete_read_messages(Owner, Queue, Key) ->
    From = msync_msg:pb_jid_to_binary(ignore_resource(Queue)),
    To = msync_msg:pb_jid_to_binary(ignore_resource(Owner)),
    Type  = guess_type(From, To),
    AppKey = Owner#'JID'.app_key,
    Result = message_store:delete_read_messages(From, To, Owner#'JID'.client_resource, integer_to_binary(Key), Type, AppKey),
    ?DEBUG("delete messages in queue(~p) of ~p to ~p, result=~p",
           [From,To, Key, Result]),
    Result.

-spec delete_group_admin_messages(Owner :: #'JID'{},
                                   Queue :: #'JID'{},
                                   Key :: pos_integer() | binary() | undefined) ->
                                          list().
delete_group_admin_messages(_Owner, _Queue, undefined) ->
    [];
delete_group_admin_messages(_Owner, _Queue, <<>>) ->
    [];
delete_group_admin_messages(Owner, Queue, Key) ->
    To = msync_msg:pb_jid_to_binary(ignore_resource(Owner)),
    From = msync_msg:pb_jid_to_binary(ignore_resource(Queue)),
    Type = guess_type(From, To),
    Resource = Owner#'JID'.client_resource,
    AppKey = Owner#'JID'.app_key,
    Result = message_store:delete_group_admin_messages(
               From, To, Resource,
               integer_to_binary(Key), Type, AppKey),
    Result.

-spec delete_large_group_messages(Owner :: #'JID'{},
                                  Queue :: #'JID'{},
                                  MID :: binary() | undefined) ->
                                         list().
%% Move cursor & decr unread, indeed
delete_large_group_messages(_Owner, _Queue, undefined) ->
    [];
delete_large_group_messages(_Owner, _Queue, <<>>) ->
    [];
delete_large_group_messages(OwnerBase, Queue, MID) ->
    Resource = easemob_resource:get_user_resource(
                 msync_msg:pb_jid_to_binary(OwnerBase#'JID'{client_resource = undefined}),
                 OwnerBase#'JID'.client_resource),
    Owner = OwnerBase#'JID'{client_resource = Resource},
    OwnerBin = msync_msg:pb_jid_to_binary(Owner),
    QueueBin = msync_msg:pb_jid_to_binary(Queue),
    CurCursor = easemob_user_cursor:get_cursor(OwnerBin, QueueBin),
    Indices = easemob_group_msg_cursor:get_msg_between_mid(
                QueueBin, CurCursor, MID),

    case Indices of
        [] ->
            [];
        _ ->
            AppKey = Owner#'JID'.app_key,
            %% Log receive for current resource
            lists:foreach(fun (Index) ->
                                  easemob_message_index:write_message_index(
                                    Index, ?TYPE_RECEIVE,
                                    OwnerBin, QueueBin, AppKey)
                          end, Indices),
            easemob_group_cursor:set_user_cursor_and_dec_unread(
              OwnerBin, QueueBin, MID),
            case easemob_resource:is_double_default() of
                true ->
                    BackupResource = easemob_resource:get_backup_resource(),
                    BackupOwnerBin =
                        msync_msg:pb_jid_to_binary(
                          Owner#'JID'{client_resource = BackupResource}),
                    easemob_group_cursor:set_user_cursor_and_dec_unread(
                      BackupOwnerBin, QueueBin, MID);
                false ->
                    ignore
            end,
            case Owner#'JID'.client_resource == ?DEFAULT_RESOURCE of
                true ->
                    ignore;
                false ->
                    %% Log receive for common resource
                    CommonOwnerBin =
                        msync_msg:pb_jid_to_binary(
                          Owner#'JID'{client_resource = ?DEFAULT_RESOURCE}),
                    lists:foreach(fun (Index) ->
                                          easemob_message_index:write_message_index(
                                            Index, ?TYPE_RECEIVE,
                                            CommonOwnerBin, QueueBin, AppKey)
                                  end, Indices),
                    easemob_group_cursor:set_user_cursor_and_dec_unread(
                      CommonOwnerBin, QueueBin, MID)
            end,
            Indices
    end.

-spec get_group_messages_migration(OwnerBase :: #'JID'{},
                                   Queue :: #'JID'{},
                                   Key :: undefined | binary(),
                                   N :: pos_integer()) ->
                                          {[#'Meta'{}], undefined | pos_integer()}.
get_group_messages_migration(OwnerBase, Queue, Key, N) ->
    Resource = easemob_resource:get_user_resource(
                 msync_msg:pb_jid_to_binary(OwnerBase#'JID'{client_resource = undefined}),
                 OwnerBase#'JID'.client_resource),
    Owner = OwnerBase#'JID'{client_resource = Resource},
    OwnerBin = msync_msg:pb_jid_to_binary(Owner),
    QueueBin = msync_msg:pb_jid_to_binary(Queue),
    {Messages, Last} =
        easemob_offline_index:get_group_messages_migration(
          OwnerBin, QueueBin, Key, N),
    {decode_meta(Messages, OwnerBase), next_key(Last)}.

-spec delete_group_messages_migration(Owner :: #'JID'{},
                                      Queue :: #'JID'{},
                                      Key :: undefined | binary()) ->
                                             [binary()].
delete_group_messages_migration(_Owner, _Queue, undefined) ->
    [];
delete_group_messages_migration(_Owner, _Queue, <<>>) ->
    [];
delete_group_messages_migration(OwnerBase, Queue, Key) ->
    %% Indices
    Resource = easemob_resource:get_user_resource(
                 msync_msg:pb_jid_to_binary(OwnerBase#'JID'{client_resource = undefined}),
                 OwnerBase#'JID'.client_resource),
    Owner = OwnerBase#'JID'{client_resource = Resource},
    OwnerBin = msync_msg:pb_jid_to_binary(Owner),
    QueueBin = msync_msg:pb_jid_to_binary(Queue),
    case easemob_resource:is_double_default() of
        true ->
            BackupResource = easemob_resource:get_backup_resource(),
            BackupOwnerBin =
                msync_msg:pb_jid_to_binary(
                  OwnerBase#'JID'{client_resource = BackupResource}),
            easemob_offline_index:delete_group_messages_migration(
              BackupOwnerBin, QueueBin, Key);
        false ->
            ignore
    end,
    case Owner#'JID'.client_resource == ?DEFAULT_RESOURCE of
        true ->
            easemob_offline_index:delete_group_messages_migration(
              OwnerBin, QueueBin, Key);
        false ->
            easemob_offline_index:delete_group_messages_migration(
              OwnerBin, QueueBin, Key),
            easemob_offline_index:delete_group_messages_migration(
              msync_msg:pb_jid_to_binary(
                Owner#'JID'{client_resource = ?DEFAULT_RESOURCE}),
              QueueBin, Key)
    end.

route_offline( #'JID'{} = From,  #'JID'{} = To, #'Meta'{id = MetaId } = Meta) ->
    Type = msync_msg:get_message_type(Meta),
    message_store:save_offline(
      msync_msg:pb_jid_to_binary(ignore_resource(From)),
      msync_msg:pb_jid_to_binary(ignore_resource(To)),
      To#'JID'.client_resource,
      integer_to_binary(MetaId),
      Type
     ).



ignore_resource(#'JID'{} = JID) ->
    JID#'JID'{
      %% offline database does not includes resources
      client_resource = undefined
     }.


guess_type(From, To) ->
    case (is_conference(From) or is_conference(To)) of
        true -> <<"groupchat">>;
        false -> <<"chat">>
    end.


is_conference(#'JID'{domain = <<"conference", _/binary>>}) ->
    true;
is_conference(_) ->
    false.

maybe_fix_unread(JID, ZeroUnreadList, true) ->
    ?INFO_MSG("maybe_fix_unread JID: ~p, ZeroUnreadList: ~p~n", [JID, ZeroUnreadList]),
    spawn(lists, foreach, [fun({L, 0}) -> msync_fix_unread:clr(JID, L) end, ZeroUnreadList]);
maybe_fix_unread(_,_,_) ->
    ok.
