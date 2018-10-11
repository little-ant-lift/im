%%%-------------------------------------------------------------------
%%% @author zhangchao <zhangchao@easemob.com>
%%% @copyright (C) 2016, zhangchao
%%% @doc
%%%
%%% @end
%%% Created : 26 Aug 2016 by zhangchao <zhangchao@easemob.com>
%%%-------------------------------------------------------------------
-module(msync_route_tests).

%% API
-include_lib("eunit/include/eunit.hrl").
-include("pb_msync.hrl").

%%%===================================================================
%%% API
%%%===================================================================
%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% TESTS DESCRIPTIONS %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%
easemob_apns_test_() ->
    {"This is EUnit Test for Msync Route",
     {setup,
      fun start/0,
      fun stop/1,
      fun(SetupData) ->
              {inorder,
               [
                msync_route_test_case(SetupData)
               ]}
      end}}.

%%%%%%%%%%%%%%%%%%%%%%%
%%% SETUP FUNCTIONS %%%
%%%%%%%%%%%%%%%%%%%%%%%
start() ->
    application:ensure_all_started(msync),
    del_apns_mute().

stop(_) ->
    ok.

%%%%%%%%%%%%%%%%%%%%
%%% ACTUAL TESTS %%%
%%%%%%%%%%%%%%%%%%%%
msync_route_test_case(_) ->
    [
     is_apns_mute()
    ].

is_apns_mute() ->
    UserJID1 = get_user_JID1(),
    UserJID2 = get_user_JID2(),
    GroupJID1 = get_group_JID1(),
    GroupJID2 = get_group_JID2(),
    [
     ?_assertEqual(true, disable_apns_mute()),
     ?_assertEqual(true, msync_route:is_apns_without_mute(UserJID2, UserJID1)),
     ?_assertEqual(true, msync_route:is_apns_without_mute(GroupJID1, UserJID1)),
     ?_assertEqual(true, msync_route:is_apns_without_mute(GroupJID2, UserJID1)),
     ?_assertEqual(true, enable_apns_mute()),
     ?_assertEqual(true, msync_route:is_apns_without_mute(UserJID2, UserJID1)),
     ?_assertEqual(true, msync_route:is_apns_without_mute(GroupJID1, UserJID1)),
     ?_assertEqual(true, add_apns_mute()),
     ?_assertEqual(false, msync_route:is_apns_without_mute(GroupJID2, UserJID1))
    ].

%%%%%%%%%%%%%%%%%%%%%%%%
%%% HELPER FUNCTIONS %%%
%%%%%%%%%%%%%%%%%%%%%%%%
get_user_JID1() ->
    #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
           name = <<"mt001">>,
           domain = <<"easemob.com">>,
           client_resource = <<"mobile">>}.

get_user_JID2() ->
    #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
           name = <<"mt002">>,
           domain = <<"easemob.com">>,
           client_resource = <<"mobile">>}.

get_group_JID1() ->
    #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
           name = <<"group1">>,
           domain = <<"conference.easemob.com">>,
           client_resource = undefined}.

get_group_JID2() ->
    #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
           name = <<"group2">>,
           domain = <<"conference.easemob.com">>,
           client_resource = undefined}.

add_apns_mute() ->
    User = <<"easemob-demo#chatdemoui_mt001">>,
    GroupID = <<"easemob-demo#chatdemoui_group2">>,
    Key = easemob_apns_mute:get_mute_apns_key(User),
    {ok, _} = easemob_redis:q(apns_mute, ["ZADD", Key, 1, GroupID]),
    true.

del_apns_mute() ->
    User = <<"easemob-demo#chatdemoui_mt001">>,
    Key = easemob_apns_mute:get_mute_apns_key(User),
    {ok, _} = easemob_redis:q(apns_mute, ["DEL", Key]),
    true.

enable_apns_mute() ->
    app_config:set_app_config(<<"easemob-demo#chatdemoui">>, apns_mute, true),
    true.

disable_apns_mute() ->
    app_config:set_app_config(<<"easemob-demo#chatdemoui">>, apns_mute, false),
    true.

%%%===================================================================
%%% Internal functions
%%%===================================================================
