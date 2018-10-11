%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created :  2 Oct 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(msync_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("logger.hrl").
-include("pb_msync.hrl").
%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%%  Returns list of tuples to set default properties
%%  for the suite.
%%
%% Function: suite() -> Info
%%
%% Info = [tuple()]
%%   List of key/value pairs.
%%
%% Note: The suite/0 function is only meant to be used to return
%% default data values, not perform any other operations.
%%
%% @spec suite() -> Info
%% @end
%%--------------------------------------------------------------------
suite() ->
    [{timetrap,{seconds,30}}].

%%--------------------------------------------------------------------
%% @doc
%% Initialization before the whole suite
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the suite.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%
%% @spec init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    application:load(lager),
    application:load(ticktick),
    application:load(message_store),
    application:load(msync),
    application:set_env(ticktick, port, 18082),
    application:set_env(msync, port, 5444),
    application:set_env(msync, web_port, 9090),
    ct:log("application configuratioins~n"
           "[{ticktick, ~p},~n"
           " {msync, ~p},~n"
           " {message_store, ~p}]~n",
           [application:get_all_env(ticktick),
            application:get_all_env(msync),
            application:get_all_env(message_store)]),
    ConsoleLog = "console.log",
    ErrorLog = "error.log",
    application:set_env(
      lager, handlers,
      [{lager_console_backend, info},
       {lager_common_test_backend, debug},
       {lager_file_backend, [{file, ConsoleLog}, {level, info},
                             {size, 104857600}, {date, "$D0"},
                             {count, 10}, {sync_on, critical}]},
       {lager_file_backend, [{file, ErrorLog}, {level, error},
							 {count, 1}, {sync_on, critical}]}]),
    mnesia:create_schema([node()]),
    {ok,_} = application:ensure_all_started(msync),
    msync_logger:set(0),
    msync_logger:set(1),
    msync_logger:set(2),
    msync_logger:set(3),
    msync_logger:set(4),
    msync_logger:set(5),
    msync_logger:set(5),% for code coverage, set it twice
    ProjRoot = code:lib_dir(msync),
    PrivDir = code:lib_dir(msync,priv),
    MSyncTest = filename:join(PrivDir, "msync_test"),
    set([
         {proj_root, ProjRoot},
         {priv_dir,  PrivDir},
         {msync_test, MSyncTest}] ,
        Config).

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after the whole suite
%%
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% @spec end_per_suite(Config) -> _
%% @end
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    application:stop(msync).

%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case group.
%%
%% GroupName = atom()
%%   Name of the test case group that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%% Reason = term()
%%   The reason for skipping all test cases and subgroups in the group.
%%
%% @spec init_per_group(GroupName, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_group(_GroupName, Config) ->
    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case group.
%%
%% GroupName = atom()
%%   Name of the test case group that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%%
%% @spec end_per_group(GroupName, Config0) ->
%%               term() | {save_config,Config1}
%% @end
%%--------------------------------------------------------------------
end_per_group(_GroupName, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Initialization before each test case
%%
%% TestCase - atom()
%%   Name of the test case that is about to be run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%
%% @spec init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%% @end
%%--------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
    lager_common_test_backend:bounce(debug),
    Config.

%%--------------------------------------------------------------------
%% @doc
%% Cleanup after each test case
%%
%% TestCase - atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% @spec end_per_testcase(TestCase, Config0) ->
%%               term() | {save_config,Config1} | {fail,Reason}
%% @end
%%--------------------------------------------------------------------

find_pattern(Pattern) ->
    fun (Log) ->
            case binary:match(Log, Pattern,[]) of
                nomatch -> false;
                {S,I} when is_integer(S), is_integer(I) -> true
            end
    end.

get_expected_logs(ExpectedErrors, Logs) ->
    lists:foldl(
      fun(ExpectedError, {ExpectedLogs, LeftLogs}) ->
              {TmpExpectedLogs, TmpLeftLogs} = lists:partition(find_pattern(ExpectedError), LeftLogs),
              {ExpectedLogs ++ TmpExpectedLogs,  TmpLeftLogs}
      end,
      {[], Logs}, ExpectedErrors).

end_per_testcase(_TestCase, Config) ->
    Logs = lists:map(fun erlang:iolist_to_binary/1,
                     lager_common_test_backend:get_logs()),
    ExpectedErrors = get(expected_errors, get(save_config,Config,[]),[]),
    %%ct:log("~p~n",[ExpectedErrors]),
    {ExpectedErrorLog, LeftLogs} = get_expected_logs(ExpectedErrors, Logs),
    {UnexpectedErrorLog, _OtherLogs} = get_expected_logs([<<"[error]">>],LeftLogs),
    N_expected_error_logs = erlang:length(ExpectedErrorLog),
    N_expected_errors = erlang:length(ExpectedErrors),
    if  N_expected_error_logs >= N_expected_errors  ->
            N_unexpected_errors = erlang:length(UnexpectedErrorLog),
            case N_unexpected_errors of
                0 -> ok;
                _N ->
                    ct:log("~s~n",
                           [error_output(
                              [io_lib:format("~p unexpected errors~n",
                                             [N_unexpected_errors]),
                               UnexpectedErrorLog])]),
                    {fail, N_unexpected_errors}
            end;
        true ->
            ct:log("~s~n",[ error_output(
                              [io_lib:format("expected at least ~p errors, but only ~p errors found~n",
                                             [N_expected_errors, N_expected_error_logs]),
                               <<"test expected errors:\n">>,
                               ExpectedErrors,
                               <<"real expected errors:\n">>,
                               ExpectedErrorLog
                              ])]),
            {fail,{N_expected_errors, N_expected_error_logs}}
    end.
%%--------------------------------------------------------------------
%% @doc
%% Returns a list of test case group definitions.
%%
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%%   The name of the group.
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%%   Group properties that may be combined.
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%%   The name of a test case.
%% Shuffle = shuffle | {shuffle,Seed}
%%   To get cases executed in random order.
%% Seed = {integer(),integer(),integer()}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%              repeat_until_any_ok | repeat_until_any_fail
%%   To get execution of cases repeated.
%% N = integer() | forever
%%
%% @spec: groups() -> [Group]
%% @end
%%--------------------------------------------------------------------
groups() ->
    [{
       login, [sequence],
       [
        test_c2s_lib,
        user_auth,
        login_no_guid,
        login_no_app,
        login_no_username,
        login_no_domain,
        login_no_client_resource,
        login_no_auth,
        login_no_cmd,
        login_fail,
        login,
        login_with_provision
       ]
     },
     {
       send_message, [sequence],
       [
        %% %% notify_no_payload,
        %% %% notify_wrong_payload,
        send_message_no_body,
        send_message_no_id,
        send_message_no_to,
        send_message,
        get_unread_no_message,
        c2_login_and_get_unread,
        send_msg_to_c2,
        get_unread_message,
        %% sync_offline,
        send_message_single_chat
       ]
     },
     {
       roster, [sequence],
       [
        %%roster_1,
        roster_2,
        roster_3,
        roster_clear,
        roster_verify_init_state,
        roster_invite,
        roster_accept,
        roster_verify,
        roster_remove,
        roster_verify_init_state,
        roster_invite,
        roster_reject
       ]
     },
     {
       muc, [sequence],
       [
        muc_redis_query_create_group,
        muc_redis_query_destroy_group,
        muc_redis_query_create_chatroom,
        muc_redis_query_destroy_chatroom,
        muc_group_clear,
        muc_group_verify_init,
        muc_group_create,
        muc_group_verify,
        muc_group_join,
        muc_group_leave,
        muc_group_destroy,
        muc_group_verify_init,
        muc_verify_consistency,
        muc_redis_query_for_join
       ]
     },
     {
       privacy, [ sequence ],
        [clear_privacy_list,
        add_privacy_list_init,
        add_privacy_list,
        check_privacy_list
        ]
     },
     {
       other, [parallel],
       [
        parse_jid,
        chain_apply,
        pb_jid,
        to_xml,
        to_xml_1,
        to_xml_2,
        to_xml_3,
        to_xml_4,
        test_shaper
       ]
     }
    ].

%%--------------------------------------------------------------------
%% @doc
%%  Returns the list of groups and test cases that
%%  are to be executed.
%%
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%%   Name of a test case group.
%% TestCase = atom()
%%   Name of a test case.
%% Reason = term()
%%   The reason for skipping all groups and test cases.
%%
%% @spec all() -> GroupsAndTestCases | {skip,Reason}
%% @end
%%--------------------------------------------------------------------
all() ->
    [{group,login},
     {group,send_message},
     {group,roster},
     {group,muc},
     {group,privacy},
     {group,other}
    ].


%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
user_auth(_Config) ->
    true = msync_user:auth(elib:eid(<<"easemob-demo#chatdemoui">>, <<"c1">>, <<"easemob.com">>, <<"mobile">>), <<"asd">>),
    false = msync_user:auth(elib:eid(<<"easemob-demo#chatdemoui">>, <<"c1">>, <<"easemob.com">>, <<"mobile">>), <<"other">>),
    ok.

login_no_guid(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no guid">>}}},
    msync_client:stop_after_recv(Client,1),
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).

login_no_app(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    ok = msync_client:set_guid(Client, #'JID'{}),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    guid = #'JID'{},
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no appkey name">>}}},
    msync_client:stop_after_recv(Client,1),
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).
login_no_username(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    guid = JID,
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no user name">>}}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).
login_no_domain(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    guid = JID,
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no domain">>}}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).
login_no_client_resource(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    guid = JID,
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no client resource">>}}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).
login_no_auth(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    guid = JID,
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no auth">>}}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).
login_no_cmd(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    guid = JID,
                    auth = <<"asd">>,
                    command = 'SYNC',
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no command">>}}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).
login_fail(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"no secret">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    guid = JID,
                    auth = <<"no secret">>,
                    command = 'UNREAD',
                    payload = #'CommUnreadDL'{
                                 status = #'Status'{
                                             error_code = 'UNAUTHORIZED',
                                             reason = <<"Sorry, who are you?">>}}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([],Config).
login(Config) ->
    process_flag(trap_exit, true),
    %% clean up unread messages if any.
    Client1 = create_client(<<"c1">>),
    %% 1 seconds to read all unread messages.
    timer:sleep(1000),
    msync_client:stop(Client1),
    %%  now login again, a clean login
    ejabberd_sm:get_session(<<"easemob-demo#chatdemoui_c1">>, <<"easemob.com">>, <<"mobile">>),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:login(Client),
    _Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    [{session,{<<"easemob-demo#chatdemoui_c1">>,
               <<"easemob.com">>,<<"mobile">>},
      {_,{msync_c2s,_}},
      {<<"easemob-demo#chatdemoui_c1">>,<<"easemob.com">>},
      0,
      [{ip,_},{conn,msync_c2s},{socket,_},{auth_module,undefined}]}] =
        ejabberd_sm:get_session(<<"easemob-demo#chatdemoui_c1">>, <<"easemob.com">>, <<"mobile">>),
    save_expected_errors([],Config).
login_with_provision(_Config) ->
    process_flag(trap_exit, true),
    [] = ejabberd_sm:get_session(<<"easemob-demo#chatdemoui_c1">>, <<"easemob.com">>, <<"mobile">>),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'PROVISION'),
    ok = msync_client:stop_after_recv(Client,1),
    Payload = #'Provision' {
                 compress_type = ['COMPRESS_NONE']
                 },
    ok = msync_client:send_payload(Client, Payload),
    _Msg = msync_client:recv_message(Client,400),
    wait(Client, normal, 50),
    [{session,{<<"easemob-demo#chatdemoui_c1">>,
               <<"easemob.com">>,<<"mobile">>},
      {_,{msync_c2s,_}},
      {<<"easemob-demo#chatdemoui_c1">>,<<"easemob.com">>},
      0,
      [{ip,_},{conn,msync_c2s},{socket, _}, {auth_module,undefined}]}] =
        ejabberd_sm:get_session(<<"easemob-demo#chatdemoui_c1">>, <<"easemob.com">>, <<"mobile">>),
    ok.
save_expected_errors(E,Config)->
    {save_config, set(expected_errors,E,Config)}.
%% notify_no_payload(Config) ->
%%     Args = ["--command", "login",
%%             "--command", "recv",
%%             "--command", "expect_status,OK",
%%             "--command", "notify_no_payload",
%%             "--command", "recv",
%%             "--command", "expect_status,MISSING_PARAMETER,\"no notify_request\""
%%            ],
%%     my_exec_msync_test(Args, Config),
%%     save_expected_errors([
%%                           <<"MISSING_PARAMETER: no notify_request">>
%%                          ],Config).
%% notify_wrong_payload(Config) ->
%%     Args = ["--command", "login",
%%             "--command", "recv",
%%             "--command", "expect_status,OK",
%%             "--command", "notify_wrong_payload",
%%             "--command", "recv",
%%             "--command", "expect_status,WRONG_PARAMETER,\"wrong payload notify_response\""
%%            ],
%%     my_exec_msync_test(Args, Config),
%%     save_expected_errors([
%%                           <<"WRONG_PARAMETER: NOTIFY but payload is notify_response">>
%%                          ], Config).
send_message_no_body(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'SYNC'),
    ok = msync_client:stop_after_recv(Client,1),
    ok = msync_client:send_payload(Client, undefined),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no meta body">> }}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([<<"missing parameter">>],Config).

send_message_no_id(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'SYNC'),
    ok = msync_client:stop_after_recv(Client,1),
    Payload = #'CommSyncUL'{
                 meta = #'Meta'{}
                },
    ok = msync_client:send_payload(Client, Payload),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no meta id">> }}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([
                          <<"namespace(encode) is not defined">>,
                          <<"MISSING_PARAMETER: no meta id">>],Config).
send_message_no_to(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'SYNC'),
    ok = msync_client:stop_after_recv(Client,1),
    Payload = #'CommSyncUL'{
                 meta = #'Meta'{
                           id = erlang:abs(time_compat:unique_integer())
                          }
                },
    ok = msync_client:send_payload(Client, Payload),
    Msg = #'MSync'{ version = 'MSYNC_V1',
                    command = 'SYNC',
                    payload = #'CommSyncDL'{
                                 status = #'Status'{
                                             error_code = 'MISSING_PARAMETER',
                                             reason = <<"no meta to">> }}},
    Msg = msync_client:recv_message(Client,100),
    wait(Client, normal, 50),
    save_expected_errors([
                          <<"namespace(encode) is not defined">>,
                          <<"MISSING_PARAMETER: no meta to">>],Config).
c2_login_and_get_unread(_Config) ->
    process_flag(trap_exit, true),
    %% clean up unread messages if any.
    Client1 = create_client(<<"c1">>),
    %% 1 seconds to read all unread messages.
    timer:sleep(500),
    msync_client:stop(Client1).

send_msg_to_c2(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'SYNC'),
    ok = msync_client:stop_after_recv(Client,1),
    ClientId = erlang:abs(time_compat:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = <<"c2">>},
                        ns = 'CHAT',
                        payload = test_ns_chat:a_message_body()
                       }
                },
    ok = msync_client:send_payload(Client, Payload),
    _Msg = msync_client:recv_message(Client,500),
    wait(Client, normal, 500),
    Config.
send_message_single_chat(_Config)->
    process_flag(trap_exit, true),
    Client = create_client(<<"c1">>),
    timer:sleep(100),
    ClientId = erlang:abs(time_compat:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = <<"c2">>},
                        ns = 'CHAT',
                        payload = test_ns_chat:a_message_body()
                       }
                },
    ok = msync_client:send_payload(Client, Payload),
    msync_client:stop_after_idle(Client),
    wait(Client,normal, 1000).


get_unread_message(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:stop_after_recv(Client,1),
    Payload = #'CommUnreadDL'{},
    ok = msync_client:send_payload(Client, Payload),
    #'MSync'{ version = 'MSYNC_V1',
              command = 'UNREAD',
              payload = #'CommUnreadDL'{
                           status = #'Status'{
                                       error_code = 'OK',
                                       reason = undefined }}}
        = msync_client:recv_message(Client,700),
    wait(Client, normal, 700),
    Config.
get_unread_no_message(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:stop_after_recv(Client,1),
    Payload = undefined,
    ok = msync_client:send_payload(Client, Payload),
    #'MSync'{ version = 'MSYNC_V1',
              command = 'UNREAD',
              payload = #'CommUnreadDL'{
                           status = #'Status'{
                                       error_code = 'OK',
                                       reason = undefined }}}
        = msync_client:recv_message(Client,500),
    wait(Client, normal, 500),
    Config.
send_message(Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'SYNC'),
    ok = msync_client:stop_after_recv(Client,3),
    ClientId = erlang:abs(time_compat:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = <<"c1">>},
                        ns = 'CHAT',
                        payload = test_ns_chat:a_message_body()
                       }
                },
    ok = msync_client:send_payload(Client, Payload),
    send_message_expect_respons(Client, ClientId),
    send_message_expect_respons(Client, ClientId),
    wait(Client, normal, 500),
    Config.

send_message_expect_respons(Client, ClientId) ->
    %% It is not for sure which one comes first
    case msync_client:recv_message(Client,1000) of
        #'MSync'{ version = 'MSYNC_V1',
                  command = 'NOTICE',
                  payload =
                      #'CommNotice'{
                         queue = {
                           'JID',
                           undefined,<<"c1">>,undefined,
                           <<"mobile">>
                          }
                        }
                }
        -> ok;
        #'MSync'{ version = 'MSYNC_V1',
                  command = 'SYNC',
                  payload = #'CommSyncDL'{
                               meta_id = ClientId, % match old binding
                               server_id = ServerId, % new binding
                               status = #'Status'{
                                           error_code = 'OK',
                                           reason = undefined }}}
        ->
            ct:log("Server id is  ~p",[ServerId]),
            ok
    end.


roster_invite(_Config) ->
    process_flag(trap_exit, true),
    Client = create_client(<<"c1">>),
    c1_invite_c2(Client),
    %%ok = msync_client:stop_after_recv(Client,1),
    Ver1 = easemob_roster:get_roster_version(<<"easemob-demo#chatdemoui_c1">>),
    Ver2 = easemob_roster:get_roster_version(<<"easemob-demo#chatdemoui_c2">>),
    %% <<"3171E3C81941E063791C0037C61265A64E5F654D">> <<"6F8F37FAF96487CD16B76D3FD9F76099DA6941BC">>ok
    io:format("1 v1 = ~p~nv2 = ~p~n",[Ver1, Ver2]),
    %% | easemob-demo#chatdemoui_c1 | 3171E3C81941E063791C0037C61265A64E5F654D |
    %% | easemob-demo#chatdemoui_c2 | 6F8F37FAF96487CD16B76D3FD9F76099DA6941BC |
    io:format("2 v1 = ~p~nv2 = ~p~n",[Ver1, Ver2]),
    msync_client:stop_after_idle(Client),
    wait(Client,normal, 1000).
roster_accept(_Config) ->
    process_flag(trap_exit, true),
    Client = create_client(<<"c2">>),
    %% 2 feedback,
    %% 1. ack
    %% 2. notice
    %% 3. sync
    %% ok = msync_client:stop_after_recv(Client,3),
    c2_accept_c1(Client),
    Ver1 = easemob_roster:get_roster_version(<<"easemob-demo#chatdemoui_c1">>),
    Ver2 = easemob_roster:get_roster_version(<<"easemob-demo#chatdemoui_c2">>),
    %% <<"1058221C9CE0B643B5BA22EEBEE6A975D5E8DB84">> <<"CF13AE9FD42C3F15D07E8450FC8AF7B078874896">>
    io:format("~p ~p",[Ver1, Ver2]),
    timer:sleep(2000),
    msync_client:stop(Client),
    wait(Client,normal, 1000).
roster_verify(_Config) ->
    [{roster,{<<"easemob-demo#chatdemoui_c1">>,
          <<"easemob.com">>,
          {<<"easemob-demo#chatdemoui_c2">>,<<"easemob.com">>,
           <<>>}},
         {<<"easemob-demo#chatdemoui_c1">>,<<"easemob.com">>},
         {<<"easemob-demo#chatdemoui_c2">>,<<"easemob.com">>,<<>>},
      <<>>,both,none,[],<<>>,[]}] = easemob_roster:get_roster(<<"easemob-demo#chatdemoui_c1">>,<<"easemob.com">>),
    [{roster,{<<"easemob-demo#chatdemoui_c2">>,
          <<"easemob.com">>,
          {<<"easemob-demo#chatdemoui_c1">>,<<"easemob.com">>,
           <<>>}},
         {<<"easemob-demo#chatdemoui_c2">>,<<"easemob.com">>},
         {<<"easemob-demo#chatdemoui_c1">>,<<"easemob.com">>,<<>>},
      <<>>,both,none,[],<<>>,[]}] = easemob_roster:get_roster(<<"easemob-demo#chatdemoui_c2">>,<<"easemob.com">>).
roster_clear(_Config) ->
    roster_clear_for_user(<<"c1">>),
    roster_clear_for_user(<<"c2">>),
    timer:sleep(200).
roster_clear_for_user(User) ->
    U1 =  <<"easemob-demo#chatdemoui_", User/binary>>,
    List = easemob_roster:get_roster(U1,<<"easemob.com">>),
    lists:foreach(
      fun(Roster) ->
              %% todo use roster record here
              {LUser, Domain, _} = erlang:element(4, Roster),
              UserInviter = U1,
              UserInvitee = <<LUser/binary>>,
              JIDInviter = <<UserInviter/binary, "@", Domain/binary>>,
              JIDInvitee = <<UserInvitee/binary, "@", Domain/binary>>,
              easemob_roster:del_roster_by_jid(UserInviter, UserInvitee, JIDInviter, JIDInvitee)
      end, List).

roster_verify_init_state(_Config) ->
    [] = easemob_roster:get_roster(<<"easemob-demo#chatdemoui_c1">>,<<"easemob.com">>),
    [] = easemob_roster:get_roster(<<"easemob-demo#chatdemoui_c2">>,<<"easemob.com">>).
roster_remove(_Config) ->
    process_flag(trap_exit, true),
    Client = create_client(<<"c1">>),
    c1_remove_c2(Client),
    %% ok = msync_client:stop_after_recv(Client,1),
    _Ver1 = easemob_roster:get_roster_version(<<"easemob-demo#chatdemoui_c1">>),
    _Ver2 = easemob_roster:get_roster_version(<<"easemob-demo#chatdemoui_c2">>),
    %% <<"6A887F33562FCD67052EC20C3C96AA0B00051A69">> <<"72178793CA579A1261A9835885D5BAE2FA7B69B9">>
    msync_client:stop_after_idle(Client),
    wait(Client,normal, 500).
roster_reject(_Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    %% 2 feedback,
    %% 1. ack
    %% 2. notice
    %% 3. sync
    c2_reject_c1(Client),
    msync_client:stop_after_idle(Client),
    wait(Client,normal, 500).

roster_1(_Config) ->
    %% this case is failed because the rosterbody.proto is changed
    M = <<"<message id='1446709334704' from='easemob.com' to='easemob-demo#chatdemoui_c2@easemob.com/mobile'><body xmlns='urn:msync:roster'>g2gHZAAKUm9zdGVyQm9keWQAA0FERGgFZAADSklEbQAAABdlYXNlbW9iLWRlbW8jY2hhdGRlbW91aW0AAAAFdXNlcjFtAAAAC2Vhc2Vtb2IuY29tbQAAAAZtb2JpbGVsAAAAAWgFZAADSklEbQAAABdlYXNlbW9iLWRlbW8jY2hhdGRlbW91aW0AAAAFdXNlcjJtAAAAC2Vhc2Vtb2IuY29tbQAAAAZtb2JpbGVqbQAAAAlubyByZWFzb25kAAl1bmRlZmluZWRkAAl1bmRlZmluZWQ=</body></message>">>,
    XML = xml_stream:parse_element(M),
    Meta = msync_meta_converter:from_xml(XML),
    MSync = #'MSync'{ version = 'MSYNC_V1',
                      command = 'SYNC',
                      payload = #'CommSyncDL'{
                                   metas = [Meta],
                                   next_key = <<"1234">>,
                                   queue = #'JID'{domain = <<"easemob.com">>}
                                  }
                    },
    DLBuffer = msync_msg:encode(MSync, undefined),
    DLMSync = msync_msg:decode_dl(DLBuffer),
    CommSyncDL = DLMSync#'MSync'.payload,
    Metas = CommSyncDL#'CommSyncDL'.metas,
    lists:foreach(fun msync_client:show_meta/1, Metas).
roster_2(_Config) ->
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload = test_ns_roster2:invite()
                       }
                },
    MSync = #'MSync'{ version = 'MSYNC_V1',
                      command = 'SYNC',
                      payload = Payload },
    msync_msg:encode(MSync, undefined).
roster_3(_Config) ->
    {'RosterBody',
     'ACCEPT',
     {'JID',<<"easemob-demo#chatdemoui">>,<<"c2">>,<<"easemob.com">>,<<"mobile">>},
     [{'JID',<<"easemob-demo#chatdemoui">>,<<"c1">>,<<"easemob.com">>,<<"mobile">>}]
    ,undefined
    ,undefined
    ,undefined}.

c1_invite_c2(Client)->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    %% ok = msync_client:stop_after_recv(Client,3),
    ClientId = erlang:abs(erlang:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload = test_ns_roster2:invite()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).

c2_accept_c1(Client)->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    %%ok = msync_client:stop_after_recv(Client,3),
    ClientId = erlang:abs(erlang:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload = test_ns_roster2:accept()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).

c2_reject_c1(Client)->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c2">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    %% ok = msync_client:stop_after_recv(Client,1),
    ClientId = erlang:abs(erlang:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload = test_ns_roster2:reject()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).

c1_remove_c2(Client)->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    %% ok = msync_client:stop_after_recv(Client,3),
    ClientId = erlang:abs(erlang:unique_integer()),
    ok = msync_client:set_command(Client, 'SYNC'),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'ROSTER',
                        payload = test_ns_roster2:remove()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).

muc_redis_query_create_group(_Config) ->
    RoomName = <<"easemob-demo#chatdemoui_1234567">>,
    RoomOpts =
        [
         {members_by_default,true},
         {allow_user_invites,false},
         {title,<<"g1">>},
         {description,<<"the first group">>},
         {public,true},
         {members_only,false},
         {max_users,500},
         {public,true},
         {affiliations,[
          <<"easemob-demo#chatdemoui_c1">>,
          <<"easemob-demo#chatdemoui_c2">>
          ]},
         {owner, <<"easemob-demo#chatdemoui_c1">>}
        ],
    [["HMSET",<<"im:easemob-demo#chatdemoui_1234567">>,title,<<"g1">>,description,
      <<"the first group">>,public,true,members_only,false,allow_user_invites,
      false,max_users,500,last_modified,_,type,<<"group">>,created,
      _,owner,<<"easemob-demo#chatdemoui_c1">>],
     [del,<<"im:easemob-demo#chatdemoui_1234567:affiliations">>],
     [zadd,<<"im:easemob-demo#chatdemoui_1234567:affiliations">>,1,
      <<"easemob-demo#chatdemoui_c1">>,1,<<"easemob-demo#chatdemoui_c2">>],
     [zadd,<<"im:easemob-demo#chatdemoui:groups">>,1,
      <<"easemob-demo#chatdemoui_1234567">>],
     [zadd,<<"im:easemob-demo#chatdemoui:publicgroups">>,1,
      <<"easemob-demo#chatdemoui_1234567">>],
     [zadd,<<"im:easemob-demo#chatdemoui_c1:groups">>,1,
      <<"easemob-demo#chatdemoui_1234567">>],
     [zadd,<<"im:easemob-demo#chatdemoui_c2:groups">>,1,
      <<"easemob-demo#chatdemoui_1234567">>]] =
        easemob_muc:redis_query_for_create(RoomName, RoomOpts).

muc_redis_query_destroy_group(_Config) ->
    RoomName = <<"easemob-demo#chatdemoui_1234567">>,
    Public = true,
    Type = <<"group">>,
    Affiliations =  [
                     <<"easemob-demo#chatdemoui_c1">>,
                     <<"easemob-demo#chatdemoui_c2">>
                    ],
    io:format("~p~n",[easemob_muc:redis_query_for_destroy(RoomName, Type, Public, Affiliations)]),
    [[del,<<"im:easemob-demo#chatdemoui_1234567">>],
     [zrem,<<"im:easemob-demo#chatdemoui:groups">>,
      <<"easemob-demo#chatdemoui_1234567">>],
     [zrem,<<"im:easemob-demo#chatdemoui:publicgroups">>,
      <<"easemob-demo#chatdemoui_1234567">>],
     [del,<<"im:easemob-demo#chatdemoui_1234567:affiliations">>],
     [zrem,<<"im:easemob-demo#chatdemoui_c1:groups">>,
      <<"easemob-demo#chatdemoui_1234567">>],
     [zrem,<<"im:easemob-demo#chatdemoui_c2:groups">>,
      <<"easemob-demo#chatdemoui_1234567">>]] =
          easemob_muc:redis_query_for_destroy(RoomName, Type, Public, Affiliations).

muc_redis_query_create_chatroom(_Config) ->
    RoomName = <<"easemob-demo#chatdemoui_7654321">>,
    RoomOpts =
        [
         {members_by_default,true},
         {allow_user_invites,false},
         {title,<<"g1">>},
         {description,<<"the first group">>},
         {public,true},
         {members_only,false},
         {type, <<"chatroom">>},
         {max_users,500},
         {public,true},
         {affiliations,[
          <<"easemob-demo#chatdemoui_c1">>,
          <<"easemob-demo#chatdemoui_c2">>
          ]},
         {owner, <<"easemob-demo#chatdemoui_c1">>}
        ],
    io:format("~p~n",[easemob_muc:redis_query_for_create(RoomName, RoomOpts)]),
    [["HMSET",<<"im:easemob-demo#chatdemoui_7654321">>,title,<<"g1">>,description,
      <<"the first group">>,public,true,members_only,false,allow_user_invites,
      false,max_users,500,last_modified,_,type,<<"chatroom">>,created,
      _,owner,<<"easemob-demo#chatdemoui_c1">>],
     [del,<<"im:easemob-demo#chatdemoui_7654321:affiliations">>],
     [zadd,<<"im:easemob-demo#chatdemoui_7654321:affiliations">>,1,
      <<"easemob-demo#chatdemoui_c1">>,1,<<"easemob-demo#chatdemoui_c2">>],
     [zadd,<<"im:easemob-demo#chatdemoui:chatrooms">>,1,
      <<"easemob-demo#chatdemoui_7654321">>],
     [zadd,<<"im:easemob-demo#chatdemoui_c1:groups">>,1,
      <<"easemob-demo#chatdemoui_7654321">>],
     [zadd,<<"im:easemob-demo#chatdemoui_c2:groups">>,1,
      <<"easemob-demo#chatdemoui_7654321">>]] =
        easemob_muc:redis_query_for_create(RoomName, RoomOpts).

muc_redis_query_destroy_chatroom(_Config) ->
    RoomName = <<"easemob-demo#chatdemoui_7654321">>,
    Public = true,
    Type = <<"chatroom">>,
    Affiliations =  [
                     <<"easemob-demo#chatdemoui_c1">>,
                     <<"easemob-demo#chatdemoui_c2">>
                    ],
    [[del,<<"im:easemob-demo#chatdemoui_7654321">>],
     [zrem,<<"im:easemob-demo#chatdemoui:chatrooms">>,
      <<"easemob-demo#chatdemoui_7654321">>],
     [del,<<"im:easemob-demo#chatdemoui_7654321:affiliations">>],
     [zrem,<<"im:easemob-demo#chatdemoui_c1:groups">>,
      <<"easemob-demo#chatdemoui_7654321">>],
     [zrem,<<"im:easemob-demo#chatdemoui_c2:groups">>,
      <<"easemob-demo#chatdemoui_7654321">>]] =
        easemob_muc:redis_query_for_destroy(RoomName, Type, Public, Affiliations).

muc_group_verify_init(_Config) ->
    group_not_found = (catch easemob_muc:read_group_affiliations(<<"easemob-demo#chatdemoui_1234567">>)).
muc_group_clear(_Config) ->
    case (catch easemob_muc:read_group_affiliations(<<"easemob-demo#chatdemoui_1234567">>)) of
        group_not_found ->
            ok;
        _ ->
            easemob_muc:destroy(<<"easemob-demo#chatdemoui_1234567">>)
    end.
muc_group_create(_Config) ->
    process_flag(trap_exit, true),
    Client = create_client(<<"c1">>),
    %%ok = msync_client:stop_after_recv(Client,2),
    muc_create(Client),
    %% msync_client:recv_message(Client,100),
    timer:sleep(500),
    msync_client:stop(Client),
    wait(Client,normal, 1000),
    verify_group(<<"easemob-demo#chatdemoui_1234567">>).

muc_group_verify(_Config) ->
    <<"group">> = easemob_muc:read_group_type(<<"easemob-demo#chatdemoui_1234567">>),
    true = easemob_muc:read_group_public(<<"easemob-demo#chatdemoui_1234567">>),
    [
     <<"easemob-demo#chatdemoui_c1">>
     %% <<"easemob-demo#chatdemoui_c2">>
    ] =
        easemob_muc:read_group_affiliations(<<"easemob-demo#chatdemoui_1234567">>).

muc_group_destroy(_Config) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    %% 1. NOTICE
    %% 2. ACK
    %% 3. FEEDBACK
    %% ok = msync_client:stop_after_recv(Client,3),
    muc_destroy(Client),
    msync_client:stop_after_idle(Client),
    wait(Client,normal, 1000).


muc_create(Client) ->
    ok = msync_client:set_command(Client, 'SYNC'),
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc2:create_group()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).
muc_destroy(Client) ->
    ok = msync_client:set_command(Client, 'SYNC'),
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc2:destroy_group()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).

muc_verify_consistency(_Config) ->
    [] =  easemob_muc:read_app_groups(<<"no such appkey">>),
    case easemob_muc:read_app_groups(<<"easemob-demo#chatdemoui">>) of
        Groups when is_list(Groups)
                    -> lists:foreach(fun verify_group/1, lists:sublist(Groups,10))
    end,
    ok.
muc_redis_query_for_join(_Config) ->
    [[zadd,
      <<"im:easemob-demo#chatdemoui_1234567:affiliations">>,1,
      <<"easemob-demo#chatdemoui_c1">>],
     [zadd,<<"im:easemob-demo#chatdemoui_c1:groups">>,1,
      <<"easemob-demo#chatdemoui_1234567">>],
     [zrem,<<"im:easemob-demo#chatdemoui_1234567:outcast">>,
      <<"easemob-demo#chatdemoui_c1">>],
     [zrem,<<"im:easemob-demo#chatdemoui_1234567:mute">>,
      <<"easemob-demo#chatdemoui_c1">>]] =
        easemob_muc:redis_query_for_join(<<"easemob-demo#chatdemoui_1234567">>, <<"easemob-demo#chatdemoui_c1">>).


muc_group_join(_Config) ->
    Client = create_client(<<"c4">>),
    %% 1. NOTICE
    %% 2. ACK
    %% 3. FEEDBACK
    %% ok = msync_client:stop_after_recv(Client,3),
    muc_join(Client),
    msync_client:stop_after_idle(Client),
    wait(Client,normal, 1000),
    Worker = cuesport:get_worker(muc),
    {ok,<<"1">>} = eredis:q(Worker, [zrank,<<"im:easemob-demo#chatdemoui_1234567:affiliations">>, [<<"easemob-demo#chatdemoui_c4">>]]).
muc_join(Client) ->
    ok = msync_client:set_command(Client, 'SYNC'),
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc2:join_group()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).
muc_group_leave(_Config) ->
    Client = create_client(<<"c4">>),
    %% 1. NOTICE
    %% 2. ACK
    %% 3. FEEDBACK
    %% ok = msync_client:stop_after_recv(Client,3),
    muc_leave(Client),
    msync_client:stop_after_idle(Client),
    wait(Client,normal, 1000),
    Worker = cuesport:get_worker(muc),
    {ok, undefined} = eredis:q(Worker, [zrank,<<"im:easemob-demo#chatdemoui_1234567:affiliations">>, [<<"easemob-demo#chatdemoui_c4">>]]).
muc_leave(Client) ->
    ok = msync_client:set_command(Client, 'SYNC'),
    ClientId = erlang:abs(erlang:unique_integer()),
    Payload = #'CommSyncUL'{
                 meta =
                     #'Meta'{
                        id = ClientId,
                        to = #'JID'{ name = undefined },
                        ns = 'MUC',
                        payload = test_ns_muc2:leave_group()
                       }
                },
    ok = msync_client:send_payload(Client, Payload).


verify_group(G) ->
    ?INFO_MSG("verifying ~p~n",[G]),
    Owner = easemob_muc:read_group_owner(G),
    ?INFO_MSG("group owner is ~p~n",[Owner]),
    Affiliations = easemob_muc:read_group_affiliations(G),
    ?INFO_MSG("group members is ~p~n",[Affiliations]),
    [true|_] = [is_list(Affiliations), Affiliations, G],
    [true|_] = [ lists:member(Owner, Affiliations), Owner, Affiliations, G],
    lists:foreach(fun(U) -> verify_user_group(U,G) end, Affiliations).

verify_user_group(U, G) ->
    Groups = easemob_muc:read_user_groups(U),
    io:format("~p belong to ~p~n", [U,G]),
    [true|_] = [ lists:member(G, Groups), G, Groups, U].


clear_privacy_list(_Config) ->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>
            },
    msync_privacy_cache:clear(JID),
    %% the redis value won't be deleted immediately, but usually after
    %% 100ms, it will be cleared.
    timer:sleep(100),
    [] = msync_privacy_cache:read(JID),
    false = msync_privacy_cache:member(JID, JID#'JID'{ name = <<"c2">>}).

add_privacy_list_init(_Config) ->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    msync_privacy_cache:add(JID,
                            [JID#'JID'{ name = <<"c2">>}, JID#'JID'{ name = <<"c2">>},
                             JID#'JID'{ name = <<"c3">>}]),
    [#'JID'{app_key = <<"easemob-demo#chatdemoui">>,
            name = <<"c2">>,domain = <<"easemob.com">>,
            client_resource = undefined},
     #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
            name = <<"c3">>,domain = <<"easemob.com">>,
            client_resource = undefined}] =
        msync_privacy_cache:read(JID).

add_privacy_list(_Config) ->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    msync_privacy_cache:add(JID,
                            [JID#'JID'{ name = <<"c3">>},
                             JID#'JID'{ name = <<"c4">>}]),
    [#'JID'{app_key = <<"easemob-demo#chatdemoui">>,
            name = <<"c2">>,domain = <<"easemob.com">>,
            client_resource = undefined},
     #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
            name = <<"c3">>,domain = <<"easemob.com">>,
            client_resource = undefined},
     #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
            name = <<"c4">>,domain = <<"easemob.com">>,
            client_resource = undefined}] =
        msync_privacy_cache:read(JID).

check_privacy_list(_Config) ->
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    true = msync_privacy_cache:member(JID, JID#'JID'{ name = <<"c2">>}),
    msync_privacy_cache:remove(JID, [JID#'JID'{ name = <<"c2">>}]),
    false = msync_privacy_cache:member(JID, JID#'JID'{ name = <<"c2">>}).



jid_to_binary(_Config) ->
    JID1 = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = <<"c1">>,
             domain = <<"easemob.com">>
            },
    <<"easemob-demo#chatdemoui_c1@easemob.com">> = msync_msg:pb_jid_to_binary(JID1),
    JID2 = #'JID'{
             name = <<"c1">>,
             domain = <<"easemob.com">>
            },
    <<"c1@easemob.com">> = msync_msg:pb_jid_to_binary(JID2),
    JID3 = #'JID'{
              domain = <<"easemob.com">>
             },
    <<"easemob.com">> = msync_msg:pb_jid_to_binary(JID3),
    JID4 = #'JID'{
              name = <<"c1">>
             },
    <<"c1">> = msync_msg:pb_jid_to_binary(JID4).

parse_jid(_Config) ->
    {'JID',
     <<"easemob-demo#chatdemoui">>,
     <<"myc1">>,
     <<"easemob.com">>,
     <<"mobile">>} = msync_msg:parse_jid("easemob-demo#chatdemoui_myc1@easemob.com/mobile"),
    {'JID',
     <<"easemob-demo#chatdemoui">>,
     <<"myc1">>,
     <<"easemob.com">>,
     undefined } = msync_msg:parse_jid("easemob-demo#chatdemoui_myc1@easemob.com"),
    {'EXIT', {1, _}} = (catch error(1)),
    {'EXIT', {{nonvalid_jid, _}, _} } = (catch msync_msg:parse_jid("easemob-demo#chatdemoui_myc1@")),
    {'JID',
     undefined,
     undefined,
     <<"easemob.com">>,
     undefined } = (catch msync_msg:parse_jid(<<"easemob.com">>)),
    ok.
save_bw_jid(_Config) ->
    JID = {'JID',
           <<"easemob-demo#chatdemoui">>,
           <<"myc1">>,
           <<"easemob.com">>,
           <<"mobile">>},
    From1 = {'JID',
             <<"easemob-demo#chatdemoui">>,
             <<"myc2">>,
             <<"easemob.com">>,
             <<"mobile">>},
    From2 = {'JID',
             <<"easemob-demo#chatdemoui2">>,
             <<"myc2">>,
             <<"easemob.com">>,
             <<"mobile">>},
    From3 = {'JID',
             <<"easemob-demo#chatdemoui">>,
             <<"myc2">>,
             <<"conference.easemob.com">>,
             <<"mobile">>},
    #'JID'{app_key = undefined,name = <<"myc2">>,
           domain = undefined,client_resource = <<"mobile">>} = msync_msg:save_bw_jid(JID,From1),
    #'JID'{app_key = <<"easemob-demo#chatdemoui2">>,name = <<"myc2">>,
           domain = undefined,client_resource = <<"mobile">>} = msync_msg:save_bw_jid(JID,From2),
    #'JID'{app_key = undefined,name = <<"myc2">>,
           domain = <<"conference.easemob.com">>,client_resource = <<"mobile">>} = msync_msg:save_bw_jid(JID,From3).


pb_jid(_Config) ->
    <<"c1">> = msync_msg:pb_jid_to_binary(#'JID'{app_key = undefined, name = <<"c1">>, domain = undefined, client_resource = undefined}),
    #'JID'{app_key = <<"Org#App">>,name = <<"Name">>,
           domain = <<"Domain">>,client_resource = <<"Resource">>
          } = ID1
        = msync_msg:pb_jid(<<"Org#App">>,<<"Name">>,<<"Domain">>,<<"Resource">>),
    <<"Org#App_Name@Domain/Resource">> = msync_msg:pb_jid_to_binary(ID1).
chain_apply(_Config) ->
    ID =  msync_msg:pb_jid(<<"Org#App">>,<<"Name">>,<<"Domain">>,<<"Resource">>),
    <<"Org#App@Name_Domain/Resource">>
        =
        chain:apply(
          "",
          [
           {fun(L) -> [L ,ID#'JID'.app_key]  end, []},
           {fun(L,Sep) -> [L , Sep, ID#'JID'.name]  end,["@"]},
           {fun(L,Sep) -> [L , Sep , ID#'JID'.domain]  end,["_"]},
           {fun(L,Sep) -> [L , Sep , ID#'JID'.client_resource]  end, ["/"]},
           {erlang,iolist_to_binary, []}
          ]).
to_xml(_Config) ->
    M1 = #'Meta'{
            id = 1445432345376,
            from =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,
                   name = <<"nc3">>,
                   domain = <<"easemob.com">>,
                   %% client_resource = <<"mobile">>,
                   %% we have to remove client_resource, otherwise, message_store doesn't recognize it.
                   client_resource = undefined
                  },
            to =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,name = <<"no2">>,
                   domain = <<"easemob.com">>,client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:a_message_body()},
    A = (msync_meta_converter:to_xml(M1)),
    M2 = msync_meta_converter:from_xml(A),
    M3 = {'Meta',1445432345376,
          {'JID',<<"easemob-demo#chatdemoui">>,<<"nc3">>,<<"easemob.com">>,
           undefined},
          {'JID',<<"easemob-demo#chatdemoui">>,<<"no2">>,<<"easemob.com">>,
           undefined},
          1445432345376,'CHAT',
          {'MessageBody','CHAT',
           {'JID',undefined,<<"inner_from">>,undefined,undefined},
           {'JID',undefined,<<"inner_to">>,undefined,undefined},
           [{'MessageBody.Content','TEXT',<<"10">>,100.0,101.0,<<"addr">>,
             <<"displayName">>,<<"url">>,<<"secret">>,1960,<<"action">>,
             %% k1 and k2 are swapped, it is OK.
             [{'KeyValue',<<"k1">>,'INT',{varint_value,112}},
              {'KeyValue',<<"k2">>,'INT',{varint_value,111}}],
             1001,
             {'MessageBody.Content.Size',60,40},
             <<"thumbnailRemotePath">>,<<"thumbnailSecretKey">>,
             <<"thumbnailDisplayName">>,1002,
             {'MessageBody.Content.Size',600,400}}],
           [{'KeyValue',<<"k4">>,'INT',{varint_value,111}},
            {'KeyValue',<<"k3">>,'INT',{varint_value,112}}],
           undefined}},
    io:format("~p",[[M1,M2,A]]),
    [true, _,_,_] = [M3 == M2, M1, M2,A].
to_xml_1(_Config) ->
    M1 = #'Meta'{
            id = 1446432415928,
            from =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,
                   name = <<"nc3">>,
                   domain = <<"easemob.com">>,
                   %%client_resource = <<"mobile">>
                   client_resource = undefined
                  },
            to =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,name = <<"no2">>,
                   domain = <<"easemob.com">>,
                   client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:message_body_1()},
    A = (msync_meta_converter:to_xml(M1)),
    M2 = msync_meta_converter:from_xml(A),
    [true, _,_,_] = [M1 == M2, M1, M2,A].

to_xml_2(_Config) ->
    M1 = #'Meta'{
            id = 1446432415928,
            from =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,
                   name = <<"nc3">>,
                   domain = <<"easemob.com">>,
                   %% client_resource = <<"mobile">>
                   client_resource = undefined
                  },
            to =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,name = <<"no2">>,
                   domain = <<"easemob.com">>,
                   client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:message_body_2()},
    A = (msync_meta_converter:to_xml(M1)),
    M2 = msync_meta_converter:from_xml(A),
    [true, _,_] = [M1 == M2, M1, M2].
to_xml_3(_Config) ->
    M1 = #'Meta'{
            id = 1446432415928,
            from =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,
                   name = <<"nc3">>,
                   domain = <<"easemob.com">>,
                   %% client_resource = <<"mobile">>
                   client_resource = undefined
                  },
            to =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,name = <<"no2">>,
                   domain = <<"easemob.com">>,client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:message_body_3()},
    A = (msync_meta_converter:to_xml(M1)),
    M2 = msync_meta_converter:from_xml(A),
    [true, _,_] = [M1 == M2, M1, M2].
to_xml_4(_Config) ->
    M1 = #'Meta'{
            id = 1446432415928,
            from =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,
                   name = <<"nc3">>,
                   domain = <<"easemob.com">>,
                   %%client_resource = <<"mobile">>
                   client_resource = undefined
                  },
            to =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,name = <<"no2">>,
                   domain = <<"easemob.com">>,client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:message_body_4()},
    A = (msync_meta_converter:to_xml(M1)),
    M2 = msync_meta_converter:from_xml(A),
    [true, _,_] = [M1 == M2, M1, M2].
to_xml_5(_Config) ->
    M1 = #'Meta'{
            id = 1445432345376,
            from =
                #'JID'{
                   app_key = undefined,
                   name = <<"nc3">>,
                   domain = undefined,
                   %% client_resource = <<"mobile">>,
                   %% we have to remove client_resource, otherwise, message_store doesn't recognize it.
                   client_resource = undefined
                  },
            to =
                #'JID'{
                   app_key = undefined,
                   name = <<"no2">>,
                   domain = undefined,
                   client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:a_message_body()},
    M1_expected = #'Meta'{
            id = 1445432345376,
            from =
                #'JID'{
                   app_key = undefined,
                   name = <<"nc3">>,
                   domain = <<"easemob.com">>,
                   %% client_resource = <<"mobile">>,
                   %% we have to remove client_resource, otherwise, message_store doesn't recognize it.
                   client_resource = undefined
                  },
            to =
                #'JID'{
                   app_key = undefined,
                   name = <<"no2">>,
                   domain = <<"easemob.com">>,
                   client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:a_message_body()},
    A = (msync_meta_converter:to_xml(M1)),
    M2 = msync_meta_converter:from_xml(A),
    io:format("~p",[[M1,M2,A]]),
    [true, _,_,_] = [M1_expected == M2, M1, M2,A].

from_xml_0(_Config) ->
    XML = {xmlel,<<"message">>,
            [{<<"from">>,<<"easemob-demo#chatdemoui_c2@easemob.com">>},
             {<<"to">>,<<"easemob-demo#chatdemoui_c1@easemob.com">>},
             {<<"id">>,<<"142614849401126912">>},
             {<<"type">>,<<"chat">>}],
            [{xmlel,<<"body">>,[],
              [{xmlcdata,<<"{\"ext\":{\"isPlayed\":false},\"to\":\"c1\",\"bodies\":[{\"type\":\"audio\",\"file_length\":4902,\"filename\":\"audio\",\"url\":\"http://172.16.0.27:80/easemob-demo/chatdemoui/chatfiles/e03ba8a0-a87e-11e5-a3d9-dbbd10f38c26\",\"secret\":\"4Duoqqh-EeWgW-WNASwtmPuk-p6BafrGRVLGRYWjyQyh7j4J\",\"length\":3}],\"from\":\"c2\"}">>}]},
             {xmlel,<<"delay">>,
              [{<<"xmlns">>,<<"urn:xmpp:delay">>},
               {<<"stamp">>,<<"2015-12-22T07:38:27.187Z">>}],
              []}]},
    {'Meta',142614849401126912,
     {'JID',<<"easemob-demo#chatdemoui">>,<<"c2">>,<<"easemob.com">>,undefined},
     {'JID',<<"easemob-demo#chatdemoui">>,<<"c1">>,<<"easemob.com">>,undefined},
     1450769907187,'CHAT',
     {'MessageBody','CHAT',
      {'JID',undefined,<<"c2">>,undefined,undefined},
      {'JID',undefined,<<"c1">>,undefined,undefined},
      [{'MessageBody.Content','VIDEO',undefined,undefined,undefined,
        undefined,<<"audio">>,
        <<"http://172.16.0.27:80/easemob-demo/chatdemoui/chatfiles/e03ba8a0-a87e-11e5-a3d9-dbbd10f38c26">>,
        <<"4Duoqqh-EeWgW-WNASwtmPuk-p6BafrGRVLGRYWjyQyh7j4J">>,4902,
        undefined,[],3,undefined,undefined,undefined,undefined,undefined,
        undefined}],
      [{'KeyValue',<<"isPlayed">>,'BOOL',{varint_value, 0}}],
      undefined}} = msync_meta_converter:from_xml(XML).

test_c2s_lib(_Config) ->
    JID1 = #'JID'{
              app_key = <<"easemob-demo#chatdemoui">>,
              name = <<"nc3">>,
              domain = <<"easemob.com">>,client_resource = <<"mobile1">>
             },
    JID2 = #'JID'{
              app_key = <<"easemob-demo#chatdemoui">>,
              name = <<"nc3">>,
              domain = <<"easemob.com">>,client_resource = <<"mobile2">>
             },
    {ok, Socket1} = gen_tcp:listen( 9001, []),
    {ok, Socket2} = gen_tcp:listen( 9002, []),
    JID1 = msync_c2s_lib:open_session(JID1, Socket1),
    JID2 = msync_c2s_lib:open_session(JID2, Socket2),
    {ok, Socket1} = msync_c2s_lib:get_pb_jid_prop(JID1,socket),
    {ok, Socket2} = msync_c2s_lib:get_pb_jid_prop(JID2,socket),
    [{<<"mobile1">>,Socket1, _SID1},{<<"mobile2">>,Socket2,_SID2}]
        = msync_c2s_lib:get_resources(JID1),
    A1 = msync_c2s_lib:get_socket_prop(Socket1,pb_jid),
    A2 = msync_c2s_lib:get_socket_prop(Socket2,pb_jid),
    {{ok,{'JID',<<"easemob-demo#chatdemoui">>,<<"nc3">>,<<"easemob.com">>,
          <<"mobile1">>}},
     {ok,{'JID',<<"easemob-demo#chatdemoui">>,<<"nc3">>,<<"easemob.com">>,
          <<"mobile2">>}}} = {A1,A2},
    msync_c2s_lib:maybe_close_session(Socket1),
    msync_c2s_lib:maybe_close_session(Socket2),
    [] = ets:tab2list(msync_c2s_tbl_pb_jid),
    ok.

%% internal function
get(Key, Config) ->
    proplists:get_value(Key,Config).
get(Key, Config,Default) ->
    proplists:get_value(Key,Config,Default).
set(Key, Value, Config) ->
    [{Key, Value} | proplists:delete(Key,Config)].
set(Lists, Config) ->
    lists:foldl(fun({Key,Value}, C)->
                        set(Key,Value,C)
                end, Config, Lists).

my_exec_msync_test(Args1, Config) ->
    Cmd = get(msync_test,Config),
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    Args = Args1 ++ ["--port", erlang:integer_to_list(Port)],
    CmdLine = io_lib:format("running command ~p~nargs ~p~n", [Cmd,Args]),
    ct:pal("~s~n", [cmd_output(format_command([Cmd | Args]))]),
    ct:pal("~s~n", [cmd_output(CmdLine)]),
    {Ret, _Output} = msync_SUITE:my_exec(Cmd,Args),
    case 0 == Ret of
        true -> ok;
        false ->
            ct:fail("C++ says failed ~p",[Ret])
    end,
    Config.

format_command(List) ->
    string:join(
      lists:map(fun(L)->
                        "'" ++ L ++ "'"
                end,
                List),
      " ").

my_exec(Command, Args) ->
    Port = open_port({spawn_executable, Command},
                     [stream, in, eof, hide, exit_status, {args, Args}]),
    get_data(Port, []).
get_data(Port, Sofar) ->
    receive
        {Port, {data, Bytes}} ->
            ct:pal("C++ say:~n~s~n", [cmd_output(Bytes)]),
            get_data(Port, [Sofar|Bytes]);
        {Port, eof} ->
            true = erlang:port_close(Port),
            ExitCode =
                receive
                    {Port, {exit_status, Code}} ->
                        Code
                end,
            {ExitCode, lists:flatten(Sofar)}
    end.

cmd_output(Output) ->
    "<pre>" ++
        lists:flatmap(fun escape/1,Output) ++
        "</pre>".

error_output(Output) ->
    "<div class=\"ct_error_notify\">" ++
        lists:map(fun escape/1, erlang:binary_to_list(erlang:iolist_to_binary(Output))) ++
        "</div>".

escape(C) ->
    case C of
        $\n -> "<br/>";
        $& -> "&amp;";
        $< -> "&lt;";
        $> -> "&gt;";
        $" -> "&quot;";
        $' -> "&apos;";
        _ -> [C]
    end.


wait(Client, ExpectReason, Time) ->
    receive
        {'EXIT', Client, Reason} ->
            ExpectReason = Reason,
            ok;
        Other ->
            ?WARNING_MSG("when waiting for client to terminate, msync client recv ~p ",[Other]),
            wait(Client,ExpectReason,Time)
    after Time ->
            ?ERROR_MSG("msync client timeout when waiting for client to terminate",[]),
            fail
    end.
recv_message(Client) ->
    msync_client:recv_message(Client).


create_client(User) ->
    process_flag(trap_exit, true),
    {ok, Port}  = application:get_env(msync,port),
    {ok, Client} = msync_client:start_link(#{port => Port}),
    JID = #'JID'{
             app_key = <<"easemob-demo#chatdemoui">>,
             name = User,
             domain = <<"easemob.com">>,
             client_resource = <<"mobile">>
            },
    ok = msync_client:set_guid(Client, JID),
    ok = msync_client:set_auth(Client, <<"asd">>),
    ok = msync_client:set_command(Client, 'UNREAD'),
    ok = msync_client:login(Client),
    %% receive the response.
    _Msg = msync_client:recv_message(Client,100),
    msync_client:sync_unread(Client),
    %% wait for sync unread messages.
    timer:sleep(200),
    Client.


test_shaper(_Config) ->
    Shaper = shaper:new(rest),
    test_shaper_1(Shaper,0).

test_shaper_1(Shaper, 5) ->
    MaxRate  = element(2,Shaper),
    LastRate  = element(3,Shaper),
    [true, _,_] = [ MaxRate - LastRate < 0.01*MaxRate, MaxRate, LastRate];
test_shaper_1(Shaper, N) ->
    Size  = element(2,Shaper),                  % TODO, import record shaper?
    {Shaper2, Pause} = shaper:update(Shaper, Size),
    io:format("test shapper: Pause = ~p Shaper2 = ~p~n",[Pause, Shaper2]),
    timer:sleep(Pause),
    test_shaper_1(Shaper2, N + 1).

meta_encode_decode(_Config) ->
    M1 = #'Meta'{
            id = <<"1445432345376">>,
            from =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,
                   name = <<"nc3">>,
                   domain = <<"easemob.com">>,client_resource = <<"mobile">>
                  },
            to =
                #'JID'{
                   app_key = <<"easemob-demo#chatdemoui">>,name = <<"no2">>,
                   domain = <<"easemob.com">>,client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:a_message_body()},
    B = msync_msg:encode_meta(M1),
    M2 = msync_msg:decode_meta(B),
    [true, _,_,_] = [M1 == M2, M1, M2, B].



test_from_xml() ->
    XML = {xmlel,<<"message">>,
           [{<<"from">>,<<"51aigegou#aggrelease_liujing@easemob.com">>},
            {<<"to">>,<<"51aigegou#aggrelease_17601597971@easemob.com">>},
            {<<"id">>,<<"171919722621702684">>},
            {<<"type">>,<<"chat">>}],
           [{xmlel,<<"body">>,[],
             [{xmlcdata,<<123,34,102,114,111,109,34,58,34,108,105,117,106,
                          105,110,103,34,44,34,116,111,34,58,34,49,55,54,
                          48,49,53,57,55,57,55,49,34,44,34,98,111,100,105,
                          101,115,34,58,91,123,34,116,121,112,101,34,58,
                          34,99,109,100,34,44,34,97,99,116,105,111,110,34,
                          58,34,73,77,95,65,67,84,73,79,78,95,65,68,68,95,
                          70,82,73,69,78,68,34,44,34,112,97,114,97,109,34,
                          58,91,93,125,93,44,34,101,120,116,34,58,123,34,
                          105,110,118,105,116,97,116,105,111,110,95,99,
                          111,100,101,34,58,34,52,53,51,56,34,44,34,110,
                          111,116,101,95,110,97,109,101,34,58,34,34,44,34,
                          104,105,110,116,34,58,34,49,50,51,34,44,34,117,
                          115,101,114,110,97,109,101,34,58,34,108,105,117,
                          106,105,110,103,34,44,34,109,101,109,98,101,114,
                          95,97,118,97,116,97,114,34,58,34,104,116,116,
                          112,58,47,47,105,109,103,46,97,105,103,101,103,
                          111,117,46,99,111,109,47,48,52,45,49,48,45,50,
                          48,49,53,47,48,52,49,48,49,51,51,57,48,49,57,49,
                          55,46,112,110,103,34,44,34,117,115,101,114,95,
                          105,100,34,58,34,49,56,48,57,34,44,34,110,105,
                          99,107,95,110,97,109,101,34,58,34,232,138,177,
                          229,132,191,230,156,181,230,156,181,229,188,128,
                          34,125,125>>}]},
            {xmlel,<<"thread">>,[],[{xmlcdata,<<"kmb2i0">>}]},
            {xmlel,<<"delay">>,
             [{<<"xmlns">>,<<"urn:xmpp:delay">>},
              {<<"stamp">>,<<"2016-03-10T06:56:19.692Z">>}],
             []}]},
    msync_meta_converter:from_xml(XML).


meta_case_test(_Config) ->
    M1 = #'Meta'{
            id = <<"1445432345376">>,
            from =
                #'JID'{
                   app_key = <<"easemob-Demo#Chatdemoui">>,
                   name = <<"Nc3">>,
                   domain = <<"Easemob.com">>,client_resource = <<"Mobile">>
                  },
            to =
                #'JID'{
                   app_key = <<"Easemob-demo#chatdemoui">>,name = <<"No2">>,
                   domain = <<"Easemob.com">>,client_resource = undefined
                  },
            timestamp = 1445432345376,
            ns = 'CHAT',
            payload = test_ns_chat:a_message_body_mix_case()},
    M2 = msync_msg:meta_to_lower(M1),
    M2 = {'Meta',<<"1445432345376">>,
          {'JID',<<"easemob-demo#chatdemoui">>,<<"nc3">>,<<"easemob.com">>,
           <<"mobile">>},
          {'JID',<<"easemob-demo#chatdemoui">>,<<"no2">>,<<"easemob.com">>,
           undefined},
          1445432345376,'CHAT',
          {'MessageBody','CHAT',
           {'JID',undefined,<<"inner_from">>,undefined,undefined},
           {'JID',undefined,<<"inner_to">>,undefined,undefined},
           [{'MessageBody.Content','TEXT',<<"10">>,100.0,101.0,<<"addr">>,
             <<"displayName">>,<<"url">>,<<"secret">>,1960,<<"action">>,
             [{'KeyValue',<<"k2">>,'INT',{varint_value,111}},
              {'KeyValue',<<"k1">>,'INT',{varint_value,112}}],
             1001,
             {'MessageBody.Content.Size',60,40},
             <<"thumbnailRemotePath">>,<<"thumbnailSecretKey">>,
             <<"thumbnailDisplayName">>,1002,
             {'MessageBody.Content.Size',600,400}}],
           [{'KeyValue',<<"k4">>,'INT',{varint_value,111}},
            {'KeyValue',<<"k3">>,'INT',{varint_value,112}}],
           undefined}}.
