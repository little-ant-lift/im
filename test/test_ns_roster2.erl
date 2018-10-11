-module(test_ns_roster2).
-compile([export_all]).
-include("pb_rosterbody.hrl").
-compile([{parse_transform, lager_transform}]).
invite() ->
    From = #'JID'{
              app_key = <<"easemob-demo#chatdemoui">>,
              name = <<"c1">>,
              domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    To = #'JID'{
            app_key = <<"easemob-demo#chatdemoui">>,
            name = <<"c2">>,
            domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    Reason = <<"I'm c1, my dear.">>,
    invite(From, To, Reason).
invite(From, To, Reason) ->
    #'RosterBody'{
       from = From,
       to = [ To ],
       operation = 'ADD',
       reason = iolist_to_binary(Reason)
      }.

accept() ->
    Inviter = #'JID'{
                 app_key = <<"easemob-demo#chatdemoui">>,
                 name = <<"c1">>,
                 domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    Invitee = #'JID'{
                 app_key = <<"easemob-demo#chatdemoui">>,
                 name = <<"c2">>,
                 domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    accept(Inviter, Invitee).
accept(Inviter, Invitee) ->
    #'RosterBody'{
       from = Invitee,
       to = [Inviter],
       operation = 'ACCEPT'
      }.
accept(Who) ->
    Inviter = get(me),
    Invitee = Who,
    #'RosterBody'{
       from = Invitee,
       to = [Inviter],
       operation = 'ACCEPT'
      }.

remove() ->
    From = #'JID'{
                 app_key = <<"easemob-demo#chatdemoui">>,
                 name = <<"c1">>,
                 domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    To = #'JID'{
                 app_key = <<"easemob-demo#chatdemoui">>,
                 name = <<"c2">>,
                 domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    remove(From, To).

remove(From, To) ->
    #'RosterBody'{
       from = From,
       to = [To],
       operation = 'REMOVE'
      }.

reject() ->
    Inviter = #'JID'{
                 app_key = <<"easemob-demo#chatdemoui">>,
                 name = <<"c1">>,
                 domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    Invitee = #'JID'{
                 app_key = <<"easemob-demo#chatdemoui">>,
                 name = <<"c2">>,
                 domain = <<"easemob.com">>,client_resource = <<"mobile">>},
    reject(Invitee, Inviter).
reject(Invitee, Inviter) ->
    #'RosterBody'{
       from = Invitee,
       to = [Inviter],
       operation = 'DECLINE'
      }.

ban(User, From) ->
    #'RosterBody'{
       from = From,
       to = [From#'JID'{ name = User } ],
       operation = 'BAN'
      }.

allow(User, From) ->
    #'RosterBody'{
       from = From,
       to = [From#'JID'{ name = User } ],
       operation = 'ALLOW'
      }.

show(Payload) ->
    #'RosterBody'{from = Inviter, operation = OP, to = [Invitee], reason = Reason } = pb_rosterbody:decode_msg(Payload,'RosterBody'),
    io_lib:format("          > ~s ~p ~s: ~s~n",
                  [ msync_msg:pb_jid_to_binary(Inviter),
                    OP,
                    msync_msg:pb_jid_to_binary(Invitee),
                    Reason]).
process_payload(Payload) ->
    RosterBody = pb_rosterbody:decode_msg(Payload,'RosterBody'),
    process_roster_body(RosterBody).

process_roster_body(#'RosterBody'{from = From, operation = 'ADD', to = [To], reason = Reason}) ->
    im_client:on_roster_add(msync_msg:pb_jid_to_binary(From),
                            msync_msg:pb_jid_to_binary(To),
                            Reason);
process_roster_body(#'RosterBody'{from = From, operation = 'REMOVE', to = [To]}) ->
    im_client:on_roster_remove(msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To));
process_roster_body(#'RosterBody'{from = From, operation = 'ACCEPT', to = [To]}) ->
    im_client:on_roster_accept(msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To));
process_roster_body(#'RosterBody'{from = From, operation = 'REMOTE_ACCEPT', to = [To]}) ->
    im_client:on_roster_remote_accept(msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To));
process_roster_body(#'RosterBody'{from = From, operation = 'REMOTE_DECLINE', to = [To]}) ->
    im_client:on_roster_remote_decline(msync_msg:pb_jid_to_binary(From), msync_msg:pb_jid_to_binary(To));
process_roster_body(#'RosterBody'{} = RosterBody) ->
    lager:error("unknown roster body: RosterBody = ~p~n",[RosterBody]).
