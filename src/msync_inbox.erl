-module(msync_inbox).
-include("pb_msync.hrl").                       % for JID
-export([push/3]).

push(#'JID'{} = Owner, #'JID'{} = Conversation, MID)
  when is_integer(MID) ->
    case easemob_redis:q(get_worker(),push_q(Owner, Conversation, MID)) of
        {ok, _NBinary} ->
            case easemob_redis:q(get_worker(),hincr_q(Owner, Conversation)) of
                {ok, _} ->
                    case easemob_redis:q(get_worker(),hincr_total_q(Owner)) of
                        {ok, TotalBinary} ->
                            Total = binary_to_integer(TotalBinary),
                            maybe_check_max_index(Owner, Total),
                            ok;
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.


push_q(#'JID'{} = Owner, #'JID'{} = Converstation, MID) ->
    [lpush, get_redis_key_inbox(Owner, Converstation), easemob_offline_index:maybe_translate_mid_integer(integer_to_binary(MID))].

%% pop_q(Owner, Converstation) ->
%%     [rpop, get_redis_key_inbox(Owner, Converstation)].

hincr_q(Owner, Converstation) ->
    Field = get_redis_key_counter_conversation(Converstation),
    [hincrby, get_redis_key_counter(Owner), easemob_offline_unread:get_unread_field(Field), 1].

hincr_total_q(Owner) ->
    [hincrby, get_redis_key_counter(Owner), <<"_total">>, 1].

get_redis_key_inbox(Owner, Converstation) ->
     User = msync_msg:pb_jid_to_binary(Owner),
     CID = get_redis_key_counter_conversation(Converstation),
     easemob_offline_index:get_index_key(User, CID).

get_redis_key_counter(Owner) ->
    User = msync_msg:pb_jid_to_binary(Owner),
    easemob_offline_unread:get_unread_key(User).

get_redis_key_counter_conversation(Converstation)  ->
    msync_msg:group_admin_cid(msync_msg:pb_jid_to_binary(msync_offline_msg:ignore_resource(Converstation))).

get_worker() ->
    easemob_offline_index:get_redis_worker().

maybe_check_max_index(Owner, Total) when Total > 1200 ->
    easemob_redis:q(get_worker(), [sadd, "to_be_clean", msync_msg:pb_jid_to_binary(Owner)]);
maybe_check_max_index(_Owner, _Total) ->
    ok.


%% check_random() ->
%%     {A1, A2, A3} = os:timestamp(),
%%     random:seed(A1, A2, A3),
%%     random:uniform(100) =< 1.
%% %% 1. check when the index more than total(1000)
%% %% 2. one percent to check max user when over 1200
%% maybe_check_max_index(Owner, Total) ->
%%     User = msync_msg:pb_jid_to_binary(Owner),
%%     Worker = cuesport:get_worker(index),
%%     case Total > 1200 of
%%         true ->
%%             case check_random() of
%%                 true ->
%%                     spawn(fun() -> easemob_remove_overflow_index:remove_index(Worker, [User]) end);
%%                 false ->
%%                     ignore
%%             end;
%%         _ ->
%%             ignore
%%     end.
