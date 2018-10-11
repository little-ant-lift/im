-module(process_system_queue).
-export([route/4]).
-include("logger.hrl").
-include("pb_msync.hrl").

route(JID, From, To, #'Meta'{ ns = NS, payload = Payload } )
  when Payload =/= undefined ->
    try
        Value = case NS of
                    'ROSTER' ->
                        msync_roster:handle(JID, Payload);
                    'MUC' ->
                        User = msync_msg:pb_jid_to_long_username(JID),
                        case app_config:is_use_thrift_group(User) of
                            true ->
                                msync_muc_bridge:handle(JID, From, To, Payload);
                            false ->
                                msync_muc:handle(JID, From, To, Payload)
                        end
                    end,
        case Value of
            ok -> ok;
            {  error, Error1 } when is_binary(Error1) ->
                {error, Error1};
            {  error, Error1 } when is_atom(Error1) ->
                {error, atom_to_binary(Error1, latin1)}
        end
    catch
        What:Error2 ->
            ?ERROR_MSG("exception ~p:~p Payload=~p~n"
                       "**stack: ~p",
                       [ What,Error2, Payload,
                         erlang:get_stacktrace()]),
            {error, <<"internal error">>}
    end;
route(JID, _From,_To,Meta) ->
    ?ERROR_MSG("unknown namespace from ~s, Meta=~p",
               [ msync_msg:pb_jid_to_binary(JID),
                 Meta]),
    {error, <<"unknown namespace">>}.
