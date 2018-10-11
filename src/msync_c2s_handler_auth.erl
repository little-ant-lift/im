-module(msync_c2s_handler_auth).
-export([try_authenticate/1]).
-include("logger.hrl").
-include("pb_msync.hrl").
%% return {MSyncID, InitResponse}
try_authenticate(#'MSync'{guid = undefined} = Msg) ->
    return_error_missing_parameter(Msg,<<"no guid">>);
try_authenticate(#'MSync'{  guid = #'JID'{app_key = undefined } } = Msg) ->
    return_error_missing_parameter(Msg,<<"no appkey name">>);
try_authenticate(#'MSync'{  guid = #'JID'{name = undefined } } = Msg) ->
    return_error_missing_parameter(Msg,<<"no user name">>);
try_authenticate(#'MSync'{  guid = #'JID'{domain = undefined } } = Msg) ->
    return_error_missing_parameter(Msg,<<"no domain">>);
try_authenticate(#'MSync'{  guid = #'JID'{client_resource = undefined } } = Msg) ->
    return_error_missing_parameter(Msg,<<"no client resource">>);
try_authenticate(#'MSync'{  command = undefined } = Msg) ->
    return_error_missing_parameter(Msg,<<"no command">>);
try_authenticate(#'MSync'{
                    guid = #'JID'{} = JID,
                    auth = Auth
                   } = Msg)
  when Auth =/= undefined ->
    %% in case two devices login simultaneously with same client
    %% resource.
    try_authenticate_with_auth(JID, Auth, Msg);
try_authenticate(#'MSync'{
                    guid = JID,
                    auth = undefined,
                    payload = #'Provision'{
                                 password = undefined,
                                 auth = Auth}} = Msg)
  when Auth =/= undefined ->
    try_authenticate_with_auth(JID, Auth, Msg);
%% Try login with password when `auth' is `undefined'
try_authenticate(#'MSync'{
                    guid = JID,
                    auth = undefined,
                    payload = #'Provision'{password = Password}} = Msg)
  when Password =/= undefined ->
    case try_auth(JID, Password) of
        true ->
            BinJID = msync_msg:pb_jid_to_binary(JID),
            case app_config:is_user_login_disabled(BinJID) of
                false ->
                    Command = msync_msg:get_command(Msg),
                    {JID, msync_msg:set_command(#'MSync'{}, dl, Command)};
                true ->
                    %%return_error_unauthorized(Msg)
                    return_error_im_forbidden(Msg)
            end;
        false ->
            return_error_unauthorized(Msg)
    end;
try_authenticate(#'MSync'{auth = undefined} = Msg) ->
    return_error_missing_parameter(Msg,<<"no auth">>);
try_authenticate(Msg) ->
    %% it is ok for CT coverage not to cover this line.
    return_error_missing_parameter(
      Msg,
      "send email to noreply@easemob.com, ask for what is missing").

try_authenticate_with_auth(JID, Auth, Msg) ->
    case try_auth(JID, Auth) of
        true ->
            BJid = msync_msg:pb_jid_to_binary(JID),
            case app_config:is_user_login_disabled(BJid) of
                false ->
                    Command = msync_msg:get_command(Msg),
                    { JID, msync_msg:set_command(#'MSync'{}, dl,Command) };
                true ->
                    %%return_error_unauthorized(Msg)
                    return_error_im_forbidden(Msg)
            end;
        false ->
            %% login failed
            return_error_unauthorized(Msg)
    end.    

try_auth(JID, Auth) ->
    try_auth(JID, Auth, application:get_env(msync, user_auth_module, msync_user_with_poolboy)).

try_auth(JID, Auth, msync_user) ->
    #'JID'{
       app_key = AppKey,
       name = Name,
       domain = Domain,
       client_resource = ClientResource } = JID,
	Eid = elib:eid(AppKey, Name, Domain, ClientResource),
	msync_user:auth(Eid, Auth);
try_auth(JID, Auth, msync_user_with_poolboy) ->
	msync_user_with_poolboy:auth(JID, Auth);
try_auth(_JID, _Auth, _) ->
    %% for anything else, the bypass mode is enabled.
    true.


%% internal functions
return_error_unauthorized(Msg) ->
    Command = msync_msg:get_command(Msg),
    {undefined,
     chain:apply(Msg,
                [{msync_msg,set_command, [dl, Command]},
                 {msync_msg,set_status, ['UNAUTHORIZED', <<"Sorry, who are you?">>]}])}.

return_error_missing_parameter(#'MSync'{} = Msg, Reason) ->
    ?WARNING_MSG("missing parameter ~p~n",[Msg]),
    Command = msync_msg:get_command(Msg),
    {undefined,
     chain:apply(Msg,
                 [{msync_msg,set_command, [dl, Command]},
                  {msync_msg,set_status, ['MISSING_PARAMETER', Reason]}])}.

return_error_im_forbidden(Msg) ->
    Command = msync_msg:get_command(Msg),
    {undefined,
     chain:apply(Msg,
                [{msync_msg,set_command, [dl, Command]},
                 {msync_msg,set_status, ['IM_FORBIDDEN', <<"Sorry, im forbidden">>]}])}.
