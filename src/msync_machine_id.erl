
-module(msync_machine_id).

-include("logger.hrl").

-export([ set_machine_id/0]).
-export([ machine_id/0
        , id_machine/1
        , update_machineid_ttl/0
        , machineid_local_migrate_etcd/0
        , backup_machineid_to_disc_file/0
        ]).

set_machine_id() ->
    ok = load_application(ticktick),
    ok = application:set_env(ticktick, machine_id, maybe_new_machineid()).

maybe_new_machineid() ->
    case application:get_env(etcdc, enable_etcd_service_disc) of
        {ok, true} ->
            MachineId = msync_etcd_client:maybe_new_machineid(erlang:node()),
            backup_machineid_to_disc_file(MachineId),
            MachineId;
        _ ->
            case read_machineid_from_disc_file() of
                {ok, MachineId} ->
                    MachineId;
                Any ->
                    ?WARNING_MSG("read_machineid_from_disc_file error, "
                                 "error info : ~p", [Any]),
                    get_machineid_from_env()
            end
    end.

update_machineid_ttl() ->
    case application:get_env(etcdc, enable_etcd_service_disc) of
        {ok, true} ->
            msync_etcd_client:update_machineid_ttl();
        _ ->
            ?WARNING_MSG("No update machine id ttl because not enable enable_etcd_service_disc env ~n", []),
            ok
    end.

machine_id() ->
    msync_etcd_client:get_machineid().

id_machine(MachineId) ->
    case application:get_env(etcdc, enable_etcd_service_disc) of
        {ok, true} ->
            msync_etcd_client:get_idmachine(MachineId);
        _ ->
            {error, unsupported}
    end.

machineid_local_migrate_etcd() ->
    PID = erlang:whereis(ticktick_id),
    case sys:get_state(PID) of
        {state, _ ,MachineID, _ , _} ->
            case msync_etcd_client:write_machineid_to_etcd(MachineID, node()) of
                {error, Reason} ->
                    ?ERROR_MSG("write machine id ~p to etcd error: ~p ~n", [MachineID, Reason]);
                {ok, MachineID} ->
                    update_machineid_ttl()
            end;
        Res ->
            ?ERROR_MSG("get machine id from sys state error: ~p ~n", [Res])
    end.

backup_machineid_to_disc_file() ->
    backup_machineid_to_disc_file(machine_id()).

%%%%%%%%%%%%%%%%%%%

backup_machineid_to_disc_file(MachineId) ->
    FileName = application:get_env(etcdc, machineid_disc_file,
                                   "./machineid_backup_file"),
    ok = filelib:ensure_dir(FileName),
    file:write_file(FileName, [erlang:integer_to_binary(MachineId)]),
    ok.

read_machineid_from_disc_file() ->
    FileName = application:get_env(etcdc, machineid_disc_file,
                                   "./machineid_backup_file"),
    case catch file:read_file(FileName) of
        {ok, <<>>} ->
            {error, empty};
        {ok, Bin} when erlang:is_binary(Bin) ->
            {ok, erlang:binary_to_integer(Bin)};
        {error, Reason} ->
            {error, Reason};
        Any ->
            {error, Any}
    end.

get_machineid_from_env() ->
    {ok, MachineId} = application:get_env(ticktick, machine_id),
    MachineId.

load_application(App) ->
    case application:load(App) of
        ok ->
            ok;
        {error, {already_loaded, App}} ->
            ok
    end.
