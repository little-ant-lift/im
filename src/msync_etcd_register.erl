
%% 

-module(msync_etcd_register).

-include("logger.hrl").

-export([ watch_storenode_and_register/0
        , enable_etcd_service_disc/0
        , disable_etcd_service_disc/0
        ]).

watch_storenode_and_register() ->
    case application:get_env(etcdc, enable_etcd_service_disc) of
        {ok, true} ->
            register_node_to_etcd(),
            msync_etcd_client:watch_storenode_list(),
            ok;
        _ ->
            ok
    end.

enable_etcd_service_disc() ->
    %% 1, push machineid to etcd from local config
    %% 2, set env for enable_etcd_service_disc using `true`
    %% 3, register node to etcd
    ok = ensure_etcd_client(),
    msync_machine_id:machineid_local_migrate_etcd(),
    ok = application:set_env(etcdc, enable_etcd_service_disc, true),
    ok = watch_storenode_and_register(),
    ok.

disable_etcd_service_disc() ->
    ok = application:set_env(etcdc, enable_etcd_service_disc, false),
    ok = msync_etcd_client:unwatch_storenode_list(),
    ok = msync_etcd_client:stop_node_heartbeat(node()),
    ok.

%%%%%%%%

register_node_to_etcd() ->
    NodeHeartbeatInterval =
        application:get_env(etcdc, node_heartbeat_interval, 2000),
    NodeEtcdTTL = NodeHeartbeatInterval div 1000 + 1,
    msync_etcd_client:register_node(msync, NodeEtcdTTL, node()),
    ok.

ensure_etcd_client() ->
    case erlang:whereis(msync_etcd_client) of
        Pid when erlang:is_pid(Pid) ->
            ok;
        _ ->
            supervisor:start_child(msync_sup, etcd_client()),
            ok
    end.

etcd_client() ->
    {msync_etcd_client,
     {msync_etcd_client, start_link, []},
     permanent,
     infinity,
     worker,
     [msync_etcd_client]
    }.