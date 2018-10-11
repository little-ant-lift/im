-module(test_ns_muc2).
-compile([export_all]).
-include("pb_mucbody.hrl").

create_group() ->
    ToList =
        [
         #'JID'{
            %% app_key = <<"easemob-demo#chatdemoui">>
            name = <<"c1">>
                %% , domain = <<"easemob.com">>
           },
         #'JID'{
            %%app_key = <<"easemob-demo#chatdemoui">>,
            name  = <<"user2">>
                %%, domain = <<"easemob.com">>
           }
        ],
    #'MUCBody'{
       muc_id = #'JID'{
                   name = <<"1234567">>
                  },
       operation = 'CREATE',
       from = #'JID'{
                 %%app_key = <<"easemob-demo#chatdemoui">>,
                 name = <<"c1">>
                     %%, domain = <<"easemob.com">>
                },
       to = ToList,
       setting = #'MUCBody.Setting'{
                    name = <<"a test group">>
                   }
      }.
create_group(Owner, GroupPropList) ->
    ToList =
         lists:map(
           fun(Name) ->
                   #'JID'{name = iolist_to_binary(Name)}
           end,
           proplists:get_value(members, GroupPropList, [])),
    #'MUCBody'{
       muc_id = #'JID'{
                   name = iolist_to_binary(
                            proplists:get_value(
                              id,
                              GroupPropList,
                              integer_to_binary(erlang:system_time(milli_seconds))))},
       operation = 'CREATE',
       from = #'JID'{
                 name = iolist_to_binary(Owner)
                },
       to = ToList,
       setting = #'MUCBody.Setting'{
                    name = iolist_to_binary(proplists:get_value(name, GroupPropList, "a test group")),
                    desc = iolist_to_binary(proplists:get_value(desc, GroupPropList, "no description")),
                    type = erlang:list_to_atom(proplists:get_value(type, GroupPropList, "PUBLIC_JOIN_APPROVAL")),
                    max_users = proplists:get_value(max_users, GroupPropList, 200),
                    owner = iolist_to_binary(Owner)
                   },
       reason = iolist_to_binary(proplists:get_value(reason, GroupPropList, <<"please join the group">>))
      }.
destroy_group() ->
    destroy_group(<<"1234567">>).
destroy_group(Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group
                  },
       operation = 'DESTROY'
      }.
join_group() ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = <<"1234567">>
                  },
       from = #'JID' {
                 name = <<"c4">>
                },
       operation = 'JOIN'
      }.
join_group(Who, Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = Who,
       operation = 'JOIN'
      }.
muc_join(Who, Group) ->
    #'MUCBody'{
       muc_id = Group,
       from = Who,
       operation = 'JOIN'
      }.

leave_group() ->
    leave_group("c4","1234567").

leave_group(Who, MUC) ->
    #'MUCBody'{
       operation = 'LEAVE',
       muc_id = #'JID'{
                   name = iolist_to_binary(MUC)
                  },
       from = #'JID' {
                 name = iolist_to_binary(Who)
                }
      }.

muc_leave(Who, MUC) ->
    #'MUCBody'{
       operation = 'LEAVE',
       muc_id = MUC,
       from = Who
      }.

apply_group(Who, Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = Who,
       operation = 'APPLY',
       reason = <<"let me in">>
      }.
apply_accept_group(From, Group) ->
    apply_response_group(From, Group, 'APPLY_ACCEPT').
apply_decline_group(From, Group) ->
    apply_response_group(From, Group, 'APPLY_DECLINE').
apply_response_group(From, Group, OP) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = From,
       to = [#'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c2">>,
                domain = <<"easemob.com">>
               }],
       operation = OP
      }.
invite(Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [#'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c4">>,
                domain = <<"easemob.com">>
               }],
       operation = 'INVITE'
      }.
invite_accept_group(Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [#'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c1">>,
                domain = <<"easemob.com">>
               }],
       operation = 'INVITE_ACCEPT'
      }.
invite_decline_group(Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [#'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c1">>,
                domain = <<"easemob.com">>
               }],
       operation = 'INVITE_DECLINE'
      }.
kick(User, Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [
             #'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = User,
                domain = <<"easemob.com">>
               }],
       operation = 'KICK'
      }.
ban(User, Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [
             #'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = User,
                domain = <<"easemob.com">>
               }],
       operation = 'BAN'
      }.
allow(User, Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [
             #'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = User,
                domain = <<"easemob.com">>
               }],
       operation = 'ALLOW'
      }.
block(User, Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [
             #'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = User,
                domain = <<"easemob.com">>
               }],
       operation = 'BLOCK'
      }.
unblock(User, Group) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       to = [
             #'JID'{
                app_key = <<"easemob-demo#chatdemoui">>,
                name = User,
                domain = <<"easemob.com">>
               }],
       operation = 'UNBLOCK'
      }.

update_setting(desc, Value) ->
    #'MUCBody.Setting' {
       desc = Value
      };
update_setting(name, Value) ->
    #'MUCBody.Setting' {
       name = Value
      };
update_setting(max_users, Value) ->
    #'MUCBody.Setting' {
       max_users = Value
      }.
update(Group,Key,Value) ->
    #'MUCBody'{
       muc_id = #'JID'{
                   name = Group,
                   domain = <<"conference.easemob.com">>
                  },
       from = get(me),
       operation = 'UPDATE' ,
       setting = update_setting(Key, Value)
      }.
show(Payload) ->
    MUCBody = pb_mucbody:decode_msg(Payload, 'MUCBody'),
    io_lib:format("muc: ~p ~p ~p, ~n~p~n",
              [
               parse_jid(MUCBody#'MUCBody'.from),
               MUCBody#'MUCBody'.operation,
               msync_msg:pb_jid_to_binary(MUCBody#'MUCBody'.muc_id),
               MUCBody]).

parse_jid(undefined) ->
    undefined;
parse_jid(Other) ->
    msync_msg:pb_jid_to_binary(Other).
