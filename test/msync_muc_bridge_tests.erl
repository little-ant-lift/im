%%%-------------------------------------------------------------------
%%% @author clanchun <clanchun@gmail.com>
%%% @copyright (C) 2016, clanchun
%%% @doc
%%% EUnit test for msync_muc_bridge
%%% Cmd: rebar eunit suites=msync_muc_bridge
%%% @end
%%% Created : 4 Nov 2016 by clanchun <clanchun@gmail.com>
%%%-------------------------------------------------------------------
-module(msync_muc_bridge_tests).

-compile(export_all).

-include_lib("msync_proto/include/pb_mucbody.hrl").
-include_lib("eunit/include/eunit.hrl").

base_params_test_() ->
    [?_assert(msync_muc_bridge:get_app_key(body_from(u), from(a), jid(a)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(u), from(n), jid(a)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(u), from(a), jid(a)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(u), from(a), jid(n)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(n), from(a), jid(n)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(n), from(a), jid(a)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(n), from(n), jid(a)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(a), from(a), jid(a)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(a), from(n), jid(a)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(a), from(a), jid(n)) =:= <<"magic">>),
     ?_assert(msync_muc_bridge:get_app_key(body_from(a), from(n), jid(n)) =:= <<"magic">>),

     ?_assert(msync_muc_bridge:get_invoker(body_from(u), jid(n)) =:= <<"alice">>),
     ?_assert(msync_muc_bridge:get_invoker(body_from(a), jid(n)) =:= <<"alice">>),
     ?_assert(msync_muc_bridge:get_invoker(body_from(n), jid(n)) =:= <<"alice">>),
     ?_assert(msync_muc_bridge:get_invoker(body_from(n), jid(a)) =:= <<"alice">>),

     ?_assert(msync_muc_bridge:get_group_name(muc(n), to(n)) =:= <<"simpson">>),
     ?_assert(msync_muc_bridge:get_group_name(muc(a), to(n)) =:= <<"simpson">>)].

thrift_test_() ->
    msync:start(),
    %%msync_logger:set(5),
    muc_thrift_server_redis:start_link(),
    
    Res = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('CREATE'))),
    error_logger:info_msg("~n~n create test: ~p~n~n", [Res]),
    
    Res2 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('UPDATE'))),
    error_logger:info_msg("~n~n update test: ~p~n~n", [Res2]),
    
    Res3 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('JOIN'))),
    error_logger:info_msg("~n~n join test: ~p~n~n", [Res3]),
    
    Res4 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('LEAVE'))),
    error_logger:info_msg("~n~n leave test: ~p~n~n", [Res4]),
    
    Res5 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('APPLY'))),
    error_logger:info_msg("~n~n apply test: ~p~n~n", [Res5]),
    
    Res6 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('APPLY_ACCEPT'))),
    error_logger:info_msg("~n~n apply_accept test: ~p~n~n", [Res6]),
    
    Res7 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('APPLY_DECLINE'))),
    error_logger:info_msg("~n~n apply_decline test: ~p~n~n", [Res7]),
    
    Res8 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('INVITE'))),
    error_logger:info_msg("~n~n invite test: ~p~n~n", [Res8]),
    
    Res9 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('INVITE_ACCEPT'))),
    error_logger:info_msg("~n~n invite_accept test: ~p~n~n", [Res9]),
    
    Res10 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('INVITE_DECLINE'))),
    error_logger:info_msg("~n~n invite_decline test: ~p~n~n", [Res10]),
    
    Res11 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('KICK'))),
    error_logger:info_msg("~n~n kick test: ~p~n~n", [Res11]),
    
    Res12 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('BAN'))),
    error_logger:info_msg("~n~n ban test: ~p~n~n", [Res12]),
    
    Res13 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('ALLOW'))),
    error_logger:info_msg("~n~n allow test: ~p~n~n", [Res13]),
    
    Res14 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('BLOCK'))),
    error_logger:info_msg("~n~n block test: ~p~n~n", [Res14]),
    
    Res15 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('UNBLOCK'))),
    error_logger:info_msg("~n~n unblock test: ~p~n~n", [Res15]),
    
    Res16 = (catch msync_muc_bridge:handle(jid(an), from(an), to(an), muc_body('DESTROY'))),
    error_logger:info_msg("~n~n destroy test: ~p~n~n", [Res16]),

    [?_assert(Res =:= ok),
     ?_assert(Res2 =:= ok),
     ?_assert(Res3 =:= ok),
     ?_assert(Res4 =:= ok),
     ?_assert(Res5 =:= ok),
     ?_assert(Res6 =:= ok),
     ?_assert(Res7 =:= ok),
     ?_assert(Res8 =:= ok),
     ?_assert(Res9 =:= ok),
     ?_assert(Res10 =:= ok),
     ?_assert(Res11 =:= ok),
     ?_assert(Res12 =:= ok),
     ?_assert(Res13 =:= ok),
     ?_assert(Res14 =:= ok),
     ?_assert(Res15 =:= ok),
     ?_assert(Res16 =:= ok)
    ].

delay_test_() ->
    timer:sleep(10000),
    ?_assert(true).

%% redis_event_test_() ->
%%     [?_assert(msync_muc_bridge:handle_msg(host(), app_key(), group_id(), invoker("alice"),
%%                                           room_type(g), <<"create_group">>, opts(), role(o))
%%               == ok)].


jid(an) ->
    #'JID'{app_key = <<"magic">>, name = <<"alice">>};
jid(a) ->
    #'JID'{app_key = <<"magic">>};
jid(n) ->
    #'JID'{name = <<"alice">>}.

from(an) ->
    #'JID'{app_key = <<"magic">>, name = <<"alice">>};
from(a) ->
    #'JID'{app_key = <<"magic">>};
from(n) ->
    #'JID'{name = <<"alice">>}.

to(an) ->
    #'JID'{app_key = <<"magic">>, name = <<"simpson">>};
to(n) ->
    #'JID'{name = <<"simpson">>};
to(a) ->
    #'JID'{app_key = <<"magic">>}.

body_from(u) ->
    undefined;
body_from(an) ->
    #'JID'{app_key = <<"magic">>, name = <<"alice">>};
body_from(a) ->
    #'JID'{app_key = <<"magic">>};
body_from(n) ->
    #'JID'{name = <<"alice">>}.

muc(an) ->
    #'JID'{app_key = <<"magic">>, name = <<"simpson">>};
muc(n) ->
    #'JID'{name = <<"simpson">>};
muc(a) ->
    #'JID'{app_key = <<"magic">>}.

muc_body(Op) ->
    #'MUCBody'{
       muc_id = muc(an),
       operation = Op,
       is_chatroom = true,
       from = from(an),
       to = [bob()],
       setting = #'MUCBody.Setting'{
                    name = <<"farm">>,
                    desc = <<"every far away">>,
                    owner = <<"alice">>
                   }
     }.

bob() ->
    #'JID'{app_key = <<"magic">>, name = <<"bob">>}.

host() ->
    <<"easemob.com">>.

app_key() ->
    <<"magic">>.

group_id() ->
    <<"simpson">>.

invoker(Name) ->
    list_to_binary(Name).

room_type(g) ->
    <<"group">>;
room_type(ct) ->
    <<"chatroom">>.

role(o) ->
    [<<"owner">>];
role(a) ->
    [<<"admin">>];
role(m) ->
    [<<"member">>].

opts() ->
    [{<<"members">>, [<<"alice">>, <<"bob">>, <<"candy">>]},
     {<<"invitees">>, [<<"dave">>, <<"ellen">>]},
     {<<"appliers">>, [<<"frank">>, <<"grace">>]}].
     
