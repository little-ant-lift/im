-module(msync_redis).
-export([q/2]).
-include("logger.hrl").
q(Name, Q) ->
    Client = cuesport:get_worker(Name),
    try eredis:q(Client, Q) of
        {error, no_connection} ->
            ?ERROR_MSG("redis op: input = ~w, error reason:~w", [Q, no_connection]),
            {error, no_connection};
        {error, Reason} ->
            ?ERROR_MSG("redis op: input = ~w, error reason:~w", [Q, Reason]),
            {error, Reason};
        {ok, Value} ->
            ?DEBUG("redis op: ~p => ~p~n", [Q, Value]),
            {ok, Value}
    catch
        Class:Exception ->
            ?ERROR_MSG("redis op ~p:~p input = ~w~n       stack = ~p~n",
                       [Class, Exception, erlang:get_stacktrace()]),
            {error, {Class, Exception}}
    end.
