%% @author Mochi Media <dev@mochimedia.com>
%% @copyright msync Mochi Media <dev@mochimedia.com>

%% @doc Callbacks for the msync application.

-module(msync_app).
-include("logger.hrl").
-author("Mochi Media <dev@mochimedia.com>").

-behaviour(application).
-export([start/2,stop/1]).


%% @spec start(_Type, _StartArgs) -> ServerRet
%% @doc application start callback for msync.
start(_Type, _StartArgs) ->
    etcdc:start(),
    msync_etcd_config:read_configure_from_etcd(),
    {ok, _} = application:ensure_all_started(lager),
    {ok, _} = application:ensure_all_started(mnesia),
    {ok, _} = application:ensure_all_started(eredis),
    {ok, _} = application:ensure_all_started(message_store),
    {ok, _} = application:ensure_all_started(im_thrift),
    {ok, _} = application:ensure_all_started(brod),
    msync_machine_id:set_machine_id(),
    {ok, _} = application:ensure_all_started(ticktick),
    msync_deps:ensure(),
    app_config:start(),                         % init table, app_config
    ejabberd_store:start(),  % init ets table.
    msync_c2s_lib:create_tables(),
    msync_msg:init(),
    shaper:init(),
    Ret = msync_sup:start_link(),
    ok = msync_etcd_config:config_watch_key(),
    ok = msync_etcd_register:watch_storenode_and_register(),
    msync_machine_id:update_machineid_ttl(),
    write_pid_file(),
    Overload = application:get_env(msync, overload, 1000),
    CurrentProcesses = erlang:system_info(process_count),
    application:set_env(msync, overload_factor,
                        Overload + CurrentProcesses),
    Ret.

%% @spec stop(_State) -> ServerRet
%% @doc application stop callback for msync.
stop(_State) ->
    ?INFO_MSG("APP MSYNC IS STOPPED ~p~n",[whereis(msync_sup)]).

get_pid_file() ->
    case application:get_env(msync, pid_path) of
        {ok, PidPath} ->
            PidPath;
        undefined ->
            ?ERROR_MSG("Get pid file not defined", [])
    end.

write_pid_file() ->
    case get_pid_file() of
        undefined ->
            ok;
        PidFilename ->
            write_pid_file(os:getpid(), PidFilename)
    end.

write_pid_file(Pid, PidFilename) ->
    case file:open(PidFilename, [write]) of
        {ok, Fd} ->
            io:format(Fd, "~s~n", [Pid]),
            file:close(Fd);
        {error, Reason} ->
            ?ERROR_MSG("Cannot write PID file ~s~nReason: ~p", [PidFilename, Reason])
    end.
