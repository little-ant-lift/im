%%%-------------------------------------------------------------------
%%% @author redink
%%% @copyright (C) , redink
%%% @doc
%%%
%%% @end
%%% Created :  by redink
%%%-------------------------------------------------------------------
-module(msync_etcd_client).

-behaviour(gen_server).

-include("logger.hrl").

%% API
-export([ start_link/0
        , stop/0]).

-export([ get_machineid/0
        , get_machineid/1
        , maybe_new_machineid/1
        , update_machineid_ttl/0
        , get_idmachine/1
        , write_machineid_to_etcd/2
        , watch_workernode_list/0
        , unwatch_workernode_list/0
        , get_workernode/1
        , watch_storenode_list/0
        , unwatch_storenode_list/0
        , get_storenode/1
        , register_node/3
        , unregister_node/2
        , stop_node_heartbeat/1
        , config_watch_key/1
        , config_unwatch_key/1
        ]).

-export([ etcdc_get/2
        , etcdc_set/2
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-define(HIBERNATE_TIMEOUT, hibernate).

-define(MACHINEID_TTL, 86400000).
-define(UPDATE_MACHINEID_INTERVAL, 3600000).
-define(GLOBAL_MACHINEID_START, 1).
-define(GLOBAL_MACHINEID_END, 900).
-define(NODE_HEARTBEAT_INTERVAL, 2000).
-define(UPDATE_ETCD_CACHE_INTERVAL, 2000).
-define(ETCD_RETRY_WATCH_INTERVAL, 3000).
-define(GLOBAL_MACHINEID_KEY, "/ims/globalmachineid").

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:call(?SERVER, stop).

get_machineid() ->
    get_machineid_self(erlang:node()).

get_machineid(Node) ->
    get_machineid_self(Node).

maybe_new_machineid(Node) ->
    case get_machineid_self(Node) of
        {error, not_found} ->
            get_machineid_new(Node);
        {ok, MachineID} ->
            MachineID
    end.

update_machineid_ttl() ->
    erlang:send(?SERVER, {update_machineid_ttl, erlang:node()}).

get_idmachine(MachineID) ->
    MachineIDBin = erlang:integer_to_binary(MachineID),
    IDToMachineKey = get_id_to_machine_key(MachineIDBin),
    case etcdc_get(IDToMachineKey) of
        {error, Reason} ->
            {error, Reason};
        #{<<"node">> := #{<<"value">> := Node}} ->
            {ok, etcd_data:decode_value(Node)}
    end.

write_machineid_to_etcd(MachineID, Node) ->
    case write_machineid(erlang:integer_to_binary(MachineID), Node) of
        {error, Reason} ->
            {error, Reason};
        {ok, MachineID} ->
            {ok, MachineID}
    end.

-spec watch_workernode_list() -> ok.
watch_workernode_list() ->
    watch_node_list(worker).

-spec get_workernode(atom()) -> {error, term()} | {ok, node()}.
get_workernode(GroupType) ->
    get_node(worker, GroupType).

-spec watch_storenode_list() -> ok.
watch_storenode_list() ->
    watch_node_list(store).

-spec get_storenode(atom()) -> {error, term()} | {ok, node()}.
get_storenode(GroupType) ->
    get_node(store, GroupType).

-spec register_node(atom(), integer(), node()) -> ok.
register_node(NodeType, TTL, Node) ->
    del_unregister_tag(Node),
    erlang:send(?SERVER, {register_node, NodeType, TTL, Node}),
    ok.

unregister_node(NodeType, Node) ->
    gen_server:call(?SERVER, {unregister_node, NodeType, Node}).

stop_node_heartbeat(Node) ->
    gen_server:call(?SERVER, {stop_node_heartbeat, Node}).

unwatch_storenode_list() ->
    unwatch_node_list(store).

unwatch_workernode_list() ->
    unwatch_node_list(worker).

config_watch_key(EtcdKeyPrefix) ->
    gen_server:call(?SERVER, {config_watch_key, EtcdKeyPrefix}).

config_unwatch_key(EtcdKeyPrefix) ->
    gen_server:call(?SERVER, {config_unwatch_key, EtcdKeyPrefix}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    ets:new(?SERVER, [named_table, public, {read_concurrency, true}]),
    {ok, #state{}, ?HIBERNATE_TIMEOUT}.

%%--------------------------------------------------------------------

handle_call({config_watch_key, EtcdKeyPrefix}, _From, State) ->
    case ets:lookup(?SERVER, {config_watch_key, EtcdKeyPrefix}) of
        [] ->
            etcdc_watch(EtcdKeyPrefix, [continous, recursive]),
            ok;
        [{_, _}] ->
            ok
    end,
    {reply, ok, State, ?HIBERNATE_TIMEOUT};

handle_call({config_unwatch_key, EtcdKeyPrefix}, _From, State) ->
    case ets:lookup(?SERVER, {config_watch_key, EtcdKeyPrefix}) of
        [{_, Pid}] ->
            ets:delete(?SERVER, {config_watch_key, EtcdKeyPrefix}),
            ok = etcdc:cancel_watch(Pid);
        [] ->
            ok
    end,
    {reply, ok, State, ?HIBERNATE_TIMEOUT};

handle_call({unwatch_node_list, NodeType}, _From, State) ->
    ok = write_unwatch_nodelist_tag(NodeType),
    {reply, ok, State, ?HIBERNATE_TIMEOUT};

handle_call({stop_node_heartbeat, Node}, _From, State) ->
    ok = write_unregister_tag(Node),
    {reply, ok, State, ?HIBERNATE_TIMEOUT};

handle_call({unregister_node, NodeType, Node}, _From, State) ->
    EtcdKeyNodeNameList = generate_node_key(NodeType, Node),
    delete_node(EtcdKeyNodeNameList),
    rewrite_ets_del_node(EtcdKeyNodeNameList, Node),
    write_unregister_tag(Node),
    [del_node_from_backup(NodeType, GroupType, Node)
     || GroupType <- [filename:basename(filename:dirname(X))
                      || X <- EtcdKeyNodeNameList]],
    {reply, ok, State, ?HIBERNATE_TIMEOUT};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State, ?HIBERNATE_TIMEOUT}.

%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State, ?HIBERNATE_TIMEOUT}.

%%--------------------------------------------------------------------
handle_info({register_node, NodeType, TTL, Node}, State) ->
    case ets:lookup(?SERVER, {'__UNREGISTER_TAG__', Node}) of
        [] ->
            write_node(generate_node_key(NodeType, Node), TTL),
            NewTimeInterval =
                application:get_env(etcdc, node_heartbeat_interval, ?NODE_HEARTBEAT_INTERVAL),
            NewTTL = NewTimeInterval div 1000 + 1,
            erlang:send_after(NewTimeInterval, self(),
                              {register_node, NodeType, NewTTL, Node});
        _ ->
            ok
    end,
    {noreply, State, ?HIBERNATE_TIMEOUT};

handle_info({update_machineid_ttl, Node}, State) ->
    case application:get_env(etcdc, enable_etcd_service_disc) of
        {ok, true} ->
            update_machineid_ttl(Node),
            TimeInterval =
                application:get_env(etcdc, update_machineid_ttl_interval, ?UPDATE_MACHINEID_INTERVAL),
            erlang:send_after(TimeInterval, ?SERVER,{update_machineid_ttl, Node});
        _ ->
            ?WARNING_MSG("not update machineid ttl because enable_etcd_service_disc is not enable, ", [])
    end,
    {noreply, State, ?HIBERNATE_TIMEOUT};

handle_info({watch_node_list, NodeType}, State) ->
    case ets:lookup(?SERVER, {'__UNWATCHNODELIST__', NodeType}) of
        [] ->
            [begin
                EtcdKeyNodeType = filename:dirname(X),
                update_node_list_into_ets(get_node_list(EtcdKeyNodeType))
             end || X <- get_node_prefix(NodeType)],
            NewTimeInterval =
                application:get_env(etcdc, update_etcd_cache_interval, ?UPDATE_ETCD_CACHE_INTERVAL),
            erlang:send_after(NewTimeInterval, self(),
                              {watch_node_list, NodeType});
        _ ->
            ok
    end,
    {noreply, State, ?HIBERNATE_TIMEOUT};

handle_info({watch, _, EtcdConfigAltera}, State) ->
    msync_etcd_config:set_env_and_backup_file_basedon_etcd(
        {watch, EtcdConfigAltera}),
    {noreply, State, ?HIBERNATE_TIMEOUT};

handle_info({watch_started, Pid, EtcdKeyPrefix}, State) ->
    ets:insert(?SERVER, {{config_watch_key, EtcdKeyPrefix}, Pid}),
    {noreply, State, ?HIBERNATE_TIMEOUT};

handle_info({watch_error, _, Key, Error}, State) ->
    ?ERROR_MSG("etcdc_config watch etcd error, "
               "key ~p, error ~p~n", [Key, Error]),
    ets:delete(?SERVER, {config_watch_key, Key}),
    erlang:send_after(application:get_env(
                        etcdc, etcdc_config_retry_watch_interval, ?ETCD_RETRY_WATCH_INTERVAL),
                      self(), {retry_watch_etcd, Key}),
    {noreply, State, ?HIBERNATE_TIMEOUT};

handle_info({retry_watch_etcd, Key}, State) ->
    etcdc_watch(Key, [continous, recursive]),
    {noreply, State, ?HIBERNATE_TIMEOUT};

handle_info(_Info, State) ->
    {noreply, State, ?HIBERNATE_TIMEOUT}.

%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

etcdc_get(Key) ->
    case catch etcdc:get(Key) of
        {'EXIT', Reason} ->
            ?ERROR_MSG("etcdc_get key ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        {error, Reason} ->
            ?ERROR_MSG("etcdc_get key ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        Res ->
            Res
    end.

etcdc_get(Key, Options) ->
    case catch etcdc:get(Key, Options) of
        {'EXIT', Reason} ->
            ?ERROR_MSG("etcdc_get key ~p options ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Options, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        {error, Reason} ->
            ?ERROR_MSG("etcdc_get key ~p options ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Options, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        Res ->
            Res
    end.

etcdc_set(Key, Value) ->
    case catch etcdc:set(Key, Value) of
        {'EXIT', Reason} ->
            ?ERROR_MSG("etcdc_set key ~p value ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Value, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        {error, Reason} ->
            ?ERROR_MSG("etcdc_set key ~p value ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Value, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        Res ->
            Res
    end.

etcdc_set(Key, Value, Options) ->
    case catch etcdc:set(Key, Value, Options) of
        {'EXIT', Reason} ->
            ?ERROR_MSG("etcdc_set key ~p value ~p options ~p error for reason: ~p stacktrace:~p ~n",
                    [Key, Value, Options, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        {error, Reason} ->
            ?ERROR_MSG("etcdc_set key ~p value ~p options ~p error for reason: ~p stacktrace:~p ~n",
                    [Key, Value, Options, Reason, erlang:get_stacktrace()]),
            {error,Reason};
        Res ->
            Res
    end.

etcdc_del(Key) ->
    case catch etcdc:del(Key) of
        {'EXIT', Reason} ->
            ?ERROR_MSG("etcdc_del key ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        {error, Reason} ->
            ?ERROR_MSG("etcdc_del key ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        Res ->
            Res
    end.

etcdc_watch(Key, Options) ->
    case catch etcdc:watch(Key, Options) of
        {'EXIT', Reason} ->
            ?ERROR_MSG("etcdc_watch key ~p options ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Options, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        {error, Reason} ->
            ?ERROR_MSG("etcdc_watch key ~p options ~p error for reason: ~p stacktrace: ~p ~n",
                    [Key, Options, Reason, erlang:get_stacktrace()]),
            {error, Reason};
        Res ->
            Res
    end.

etcdc_cancel_watch(Pid) ->
    case catch etcdc:cancel_watch(Pid) of
        {'EXIT', Reason} ->
            ?ERROR_MSG("etcdc_cancel_watch ~p error, info: ~p~n", [Pid, Reason]),
            {error, Reason};
        {error, Reason} ->
            ?ERROR_MSG("etcdc_cancel_watch ~p error, info: ~p~n", [Pid, Reason]),
            {error, Reason};
        Res ->
            Res
    end.

get_machineid_self(Node) ->
    MachineToIDKey =
        get_machine_to_id_key(http_uri:encode(atom_to_list(Node))),
    case etcdc_get(MachineToIDKey) of
        {error, _} ->
            {error, not_found};
        #{<<"node">> := #{<<"value">> := MachineToID0}} ->
            {ok, erlang:binary_to_integer(MachineToID0)}
    end.

write_machineid(MachineIDBin, Node) ->
    OriginMachineID = erlang:binary_to_integer(MachineIDBin),
    MachineToIDKey =
        get_machine_to_id_key(http_uri:encode(atom_to_list(Node))),
    IDToMachineKey = get_id_to_machine_key(MachineIDBin),
    TtlConfig = application:get_env(etcdc, etcd_machineid_ttl, ?MACHINEID_TTL),
    TTL = TtlConfig div 1000 + 1,
    case etcdc_set(IDToMachineKey, etcd_data:encode_value(Node),
                    [{prevExist, false}, {ttl, TTL}]) of
        {error, Reason} ->
            {error, Reason};
        _ ->
            etcdc_set(MachineToIDKey, OriginMachineID, [{ttl, TTL}]),
            {ok, OriginMachineID}
    end.

update_machineid_ttl(Node) ->
    NodeEncode = etcd_data:encode_value(Node),
    MachineToIDKey =
        get_machine_to_id_key(http_uri:encode(atom_to_list(Node))),
    case etcdc_get(MachineToIDKey) of
        {error, Reason} ->
            ?ERROR_MSG("Get ~p error for reason: ~p ~n",[MachineToIDKey, Reason]),
            {error, Reason};
        #{<<"node">> := #{<<"value">> := MachineToID0}} ->
            IDToMachineKey = get_id_to_machine_key(MachineToID0),
            case etcdc_get(IDToMachineKey) of
                {error, Reason} ->
                    ?ERROR_MSG("Update ~p error for reason: ~p ~n",[IDToMachineKey, Reason]),
                    {error, Reason};
                #{<<"node">> := #{<<"value">> := NodeEncode}} ->
                    MachineToID = erlang:binary_to_integer(MachineToID0),
                    ?INFO_MSG("Update node ~p machineid ~p ttl ~n",[Node, MachineToID]),
                    TtlConfig = application:get_env(etcdc, etcd_machineid_ttl, ?MACHINEID_TTL),
                    TTL = TtlConfig div 1000 + 1,
                    etcdc_set(IDToMachineKey, NodeEncode, [{ttl, TTL}]),
                    etcdc_set(MachineToIDKey, MachineToID, [{ttl, TTL}]);
                #{<<"node">> := #{<<"value">> := NodeNew}} ->
                    ?CRITICAL_MSG("Update node ~p machine id ~p ttl but found another node ~p"
                                    " use this machine id ~n", [Node, MachineToID0, NodeNew])
            end
    end.

new_global_machineid(GlobalMachineID) ->
    GlobalMachineIDEnd =
        application:get_env(etcdc, global_machine_id_end, ?GLOBAL_MACHINEID_END),
    case GlobalMachineID >= GlobalMachineIDEnd of
        true ->
            application:get_env(etcdc, global_machine_id_start, ?GLOBAL_MACHINEID_START);
        _ ->
            GlobalMachineID + 1
    end.

get_machineid_new(Node) ->
    GlobalMachineIDKey =
        application:get_env(etcdc, global_machine_id_key, ?GLOBAL_MACHINEID_KEY),
    case etcdc_get(GlobalMachineIDKey) of
        {error, not_found} ->
            GlobalMachineIDStart =
                application:get_env(etcdc, global_machine_id_start, ?GLOBAL_MACHINEID_START),
            case etcdc_set(GlobalMachineIDKey, GlobalMachineIDStart,
                           [{prevExist, false}]) of
                {error, _} ->
                    get_machineid_new(Node);
                #{<<"action">> := <<"create">>,
                  <<"node">> := #{<<"value">> := MachineID}} ->
                    case write_machineid(MachineID, Node) of
                        {error, _} ->
                            get_machineid_new(Node);
                        {ok, MachineID} ->
                            MachineID
                    end
            end;
        {error, Reason} ->
            ?CRITICAL_MSG("Get global machine id error for reason ~p ~n",[Reason]);
        #{<<"node">> := #{<<"value">> := OriginMachineID0}} ->
            OriginMachineID = erlang:binary_to_integer(OriginMachineID0),
            NewMachineID = new_global_machineid(OriginMachineID),
            case etcdc_set(GlobalMachineIDKey, NewMachineID,
                        [{prevValue, OriginMachineID}]) of
                {error, _} ->
                    get_machineid_new(Node);
                #{<<"action">> := <<"compareAndSwap">>,
                <<"node">> := #{<<"value">> := NewOriginMachineID}} ->
                    case write_machineid(NewOriginMachineID, Node) of
                        {error, _} ->
                            get_machineid_new(Node);
                        {ok, MachineID} ->
                            MachineID
                    end
            end
    end.

-spec watch_node_list(atom()) -> ok.
watch_node_list(NodeType) ->
    ok = del_unwatch_nodelist_tag(NodeType),
    erlang:send(?SERVER, {watch_node_list, NodeType}),
    ok.

unwatch_node_list(NodeType) ->
    gen_server:call(?SERVER, {unwatch_node_list, NodeType}),
    ok.

-spec get_node(atom(), atom()) -> {error, term()} | {ok, node()}.
get_node(NodeType, GroupType) ->
    case application:get_env(etcdc, enable_etcd_service_disc) of
        {ok, true} ->
            get_node_do(NodeType, GroupType);
        _ ->
            {error, disable_etcd_service_disc}
    end.

get_node_do(NodeType, GroupType) ->
    case [X || X <- get_node_prefix(NodeType),
               erlang:atom_to_list(GroupType) == filename:basename(X)] of
        [] ->
            {error, empty};
        EtcdKeyGroupTypeList ->
            {A1, A2, A3} = os:timestamp(),
            random:seed(A1, A2, A3),
            get_node_do_do(lists:nth(random:uniform(length(EtcdKeyGroupTypeList)),
                           EtcdKeyGroupTypeList))
    end.

get_node_do_do(EtcdKeyGroupType) ->
    case catch ets:lookup(?SERVER, EtcdKeyGroupType) of
        {'EXIT', _} ->
            {error, etcdc_cache_error};
        [] ->
            {error, empty};
        [{_, []}] ->
            {error, empty};
        [{_, List}] ->
            {A1, A2, A3} = os:timestamp(),
            random:seed(A1, A2, A3),
            {ok, lists:nth(random:uniform(length(List)), List)}
    end.

generate_node_key(NodeType, Node) ->
    [filename:join([KeyPrefix,
                   http_uri:encode(erlang:atom_to_list(Node))])
     || KeyPrefix <- get_node_prefix(NodeType)].

delete_node(EtcdKeyNodeNameList) ->
    [etcdc_del(EtcdKeyNodeName) || EtcdKeyNodeName <- EtcdKeyNodeNameList],
    ok.

rewrite_ets_del_node([], _) ->
    ok;
rewrite_ets_del_node([EtcdKeyNodeName | Tail], Node) ->
    EtcdKeyGroupType = filename:dirname(EtcdKeyNodeName),
    case catch ets:lookup(?SERVER, EtcdKeyGroupType) of
        [{EtcdKeyGroupType, NodeList}] ->
            case lists:delete(Node, NodeList) of
                [] ->
                    ets:delete(?SERVER, EtcdKeyGroupType);
                NewNodeList ->
                    ets:insert(?SERVER, {EtcdKeyGroupType, NewNodeList})
            end,
            ok;
        _ ->
            ok
    end,
    rewrite_ets_del_node(Tail, Node).

write_unwatch_nodelist_tag(NodeType) ->
    ets:insert(?SERVER, {{'__UNWATCHNODELIST__', NodeType}, fake}),
    ok.

del_unwatch_nodelist_tag(NodeType) ->
    ets:delete(?SERVER, {'__UNWATCHNODELIST__', NodeType}),
    ok.

write_unregister_tag(Node) ->
    ets:insert(?SERVER, {{'__UNREGISTER_TAG__', Node}, fake}),
    ok.

del_unregister_tag(Node) ->
    ets:delete(?SERVER, {'__UNREGISTER_TAG__', Node}),
    ok.

% del_node_from_backup(worker, GroupType, Node) ->
%     ejabberd_worker:del_worker_node(GroupType, erlang:atom_to_list(Node));
del_node_from_backup(store, GroupType, Node) ->
    ejabberd_store:del_store_node(GroupType, erlang:atom_to_list(Node));
del_node_from_backup(_, _, _) ->
    ok.

write_node([], _) ->
    ok;
write_node([EtcdKeyNodeName | Tail], TTL) ->
    etcdc_set(EtcdKeyNodeName, "up", [{ttl, TTL}]),
    write_node(Tail, TTL).

get_node_list(EtcdKeyNodeType) ->
    etcdc_get(EtcdKeyNodeType, [recursive]).

update_node_list_into_ets(EtcdRes) when erlang:is_map(EtcdRes) ->
    Nodes = maps:get(<<"nodes">>, maps:get(<<"node">>, EtcdRes, #{}), []),
    [begin
        Key   = erlang:binary_to_list(maps:get(<<"key">>, Node)),
        Value = [begin
                    OriginKey = erlang:binary_to_list(maps:get(<<"key">>, X)),
                    OriginWorkerNode = filename:basename(OriginKey),
                    erlang:list_to_atom(http_uri:decode(OriginWorkerNode))
                 end || X <- maps:get(<<"nodes">>, Node, [])],
        ets:insert(?SERVER, {Key, Value}),
        {NodeType, GroupType} = parse_node_and_group_type(Key),
        write_ejabberd_node(NodeType, GroupType, Value),
        ok
     end || Node <- Nodes],
    ok;
update_node_list_into_ets(Res) ->
    ?ERROR_MSG("update_node_list_into_ets error, for reason: ~p~n", [Res]),
    ok.

parse_node_and_group_type(EtcdKeyGroupType) ->
    GroupType0 = filename:basename(EtcdKeyGroupType),
    NodeType0  = filename:basename(filename:dirname(EtcdKeyGroupType)),
    {catch match_nodetype(NodeType0), erlang:list_to_atom(GroupType0)}.

match_nodetype(NodeTypeString) ->
    match_nodetype(worker, NodeTypeString),
    match_nodetype(conn, NodeTypeString),
    match_nodetype(store, NodeTypeString).

match_nodetype(NodeType, NodeTypeString) ->
    case get_node_prefix(NodeType) of
        [] ->
            ok;
        [NodeTypePrefix | _]  ->
            case filename:basename(filename:dirname(NodeTypePrefix)) ==
                    NodeTypeString of
                true ->
                    erlang:throw(NodeType);
                false ->
                    ok
            end
    end.

% write_ejabberd_node(worker, GroupType, Nodes) ->
%     ejabberd_worker:set_worker_nodes(GroupType, Nodes);
write_ejabberd_node(store, GroupType, Nodes) ->
    ejabberd_store:set_store_nodes(GroupType, Nodes);
write_ejabberd_node(NodeType, GroupType, Nodes) ->
    ?WARNING_MSG("Unknown nodetype, nodetype : ~p grouptype : ~p nodes : ~p ~n",
                 [NodeType, GroupType, Nodes]),
    ok.

get_machine_to_id_key(Machine) ->
    filename:join([get_machine_to_id_prefix(), Machine]).
get_id_to_machine_key(ID) ->
    filename:join([get_id_to_machine_prefix(), ID]).

get_machine_to_id_prefix() ->
    application:get_env(etcdc, msync_machine_id_prefix, "").

get_id_to_machine_prefix() ->
    application:get_env(etcdc, msync_id_machine_prefix, "").

% get_node_prefix(worker) ->
%     application:get_env(etcdc, ejabberd_workernode_prefix, []);
% get_node_prefix(conn) ->
%     application:get_env(etcdc, ejabberd_connnode_prefix, []);
get_node_prefix(store) ->
    application:get_env(etcdc, ejabberd_storenode_prefix, []);
% get_node_prefix(msglimit) ->
%     application:get_env(etcdc, ejabberd_msglimitnode_preifx, []);
% get_node_prefix(httpbind) ->
%     application:get_env(etcdc, ejabberd_httpbindnode_preifx, []);
% get_node_prefix(imapi) ->
%     application:get_env(etcdc, ejabberd_imapinode_preifx, []);
% get_node_prefix(restbatch) ->
%     application:get_env(etcdc, ejabberd_restbatchnode_preifx, []);
% get_node_prefix(restkefu) ->
%     application:get_env(etcdc, ejabberd_restkefunode_preifx, []);
% get_node_prefix(restnormal) ->
%     application:get_env(etcdc, ejabberd_restnormalnode_preifx, []);
get_node_prefix(msync) ->
    application:get_env(etcdc, msync_node_prefix, []);
get_node_prefix(_) ->
    [].
