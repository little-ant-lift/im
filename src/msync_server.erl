-module(msync_server).
-author('wcy123@gmail.com').
-include("logger.hrl").
-export([start_link/1, stop/0, shutdown/0]).
-export([loop/2]).
-compile([{parse_transform, lager_transform}]).

-define(DEFAULTS, [{name, ?MODULE},
                   {port, get_port()} |
                   get_sock_options()
                  ]).


parse_options(Options) ->
    Loop = {?MODULE, loop},
    Options1 = [{loop, Loop} | proplists:delete(loop, Options)],
    mochilists:set_defaults(?DEFAULTS, Options1).

start_link(Options) ->
    mochiweb_socket_server:start_link(parse_options(Options)).
stop() ->
    mochiweb_socket_server:stop(?MODULE).


loop(Socket, _Opts) ->
    case easemob_traffic_control:get_ticket(traffic_control_login) of
        ok ->
            case catch msync_client_sup:start_client(Socket) of
                {ok, Pid} ->
                    case gen_tcp:controlling_process(Socket, Pid) of
                        ok ->
                            ok;
                        {error, Reason} when Reason == closed;
                                             Reason == einval ->
                            ?INFO_MSG("socket closed when controlling process, "
                                      "socket: ~p, reason: ~p~n", [Socket, Reason]),
                            msync_client_sup:stop_client(Pid);
                        {error, Reason} ->
                            ?ERROR_MSG("controlling process failed, reason: ~p~n",
                                       [Reason]),
                            msync_client_sup:stop_client(Pid)
                    end;
                Error ->
                    ?ERROR_MSG("start client failed, error: ~p~n", [Error])
            end;
        {error, Reason} ->
            ?WARNING_MSG("login traffic control happen:reason:~p", [Reason])
    end.

get_port() ->
    {ok, Port} = application:get_env(msync,port),
    Port.

get_sock_options() ->
    {ok, SockOptions} = application:get_env(msync,sock_opts),
    SockOptions.


shutdown() ->
    %% stop the listening socket
    supervisor:terminate_child(msync_sup, msync_server),
    close_all_socket().



close_all_socket() ->
    {links, Links} = process_info(whereis(msync_c2s), links),
    lists:foreach(
      fun(Socket)
          when is_port(Socket) ->
              MaybeJID = msync_c2s_lib:get_socket_prop(Socket,pb_jid),
              ?INFO_MSG("close socket ~p for ~p~n",[Socket, MaybeJID]),
              msync_c2s_lib:maybe_close_session(Socket);
         (_) ->
              false
      end, Links).
