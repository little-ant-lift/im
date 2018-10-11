%% Call = login, Args = {'UserAuth',{'EID',<<"easemob-demo#chatdemoui">>,<<"c5">>},<<"asd">>,undefined}

-module(msync_user_with_poolboy).
-include("logger.hrl").
-include("pb_msync.hrl").
-include("gen-erl/user_service_thrift.hrl").
-include("gen-erl/common_types.hrl").
-export([auth/2]).

auth(JID, Password) ->
    AppKey = JID#'JID'.app_key,
    Name = JID#'JID'.name,
    Block = false,
    Timeout = 1000,
    case im_thrift:call(user_service_thrift, login, [{'UserAuth', {'EID', AppKey, Name}, Password, undefined}],
                       Block, Timeout) of
        {error, full} ->
            ?WARNING_MSG("bypass because there pool size is full for user ~s_~s~n",[AppKey, Name]),
            true;
        {error, Reason} ->
            ?WARNING_MSG("bypass due to ~p for user ~s_~s~n",[Reason, AppKey, Name]),
            true;
        {ok, B} when is_boolean(B) ->
            B;
		{ok, #'UserInfo'{ auth = UserAuth } } ->
			UserAuth#'UserAuth'.token /= undefined;
        {exception, EE = #'EasemobException'{ code = EECode } } ->
			?DEBUG("Exception got from thrift server, ~p~n ", [EE]),
			%% error codes [400,500) are due to client problems, default false
			EECode < 400 orelse EECode >= 500;
        Otherwise ->
            ?WARNING_MSG("bypass due to unknown return value ~p for user ~s_~s~n",[Otherwise, AppKey, Name]),
            true
    end.
