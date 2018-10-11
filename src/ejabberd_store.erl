-module(ejabberd_store).

%% Store nodes configurations and helper funs.
-export([start/0,
         set_store_nodes/2,
         random_store_node/1,
         store_rpc/4,
         set_store_consistency/1,
         op_by_consistency/0,
         store_node_list/0,
         add_store_node/2,
         del_store_node/2,
         reset_store_nodes/1,
         get_store_nodes/1
        ]).

-include("logger.hrl").


-record(store_nodes, {name :: atom(), nodes :: any()}).

-define(DEFAULT_RPC_TIMEOUT, 60000).

start() ->
    ets:new(store_nodes, [named_table, public, {keypos, #store_nodes.name}]),
	NodesConfig = get_config(),
	[set_store_nodes(Name, Nodes) || {Name, Nodes} <- NodesConfig],

    set_store_consistency(all).

add_store_node(NameString, NodeString) ->
    Name = erlang:list_to_atom(NameString),
    Node = erlang:list_to_atom(NodeString),
    try  Name == all orelse Name == muc orelse Name == sub orelse throw(invalid_name),
         pong == net_adm:ping(Node) orelse throw(node_not_reachable),
         OldNodes = get_store_nodes(Name),
         false == lists:member(Node, OldNodes) orelse throw(node_already_exists),
         set_store_nodes(Name, lists:append(OldNodes, [Node])),
         "success"
    catch
        throw:invalid_name -> io_lib:format("~p is not a valid node name. it must be one of all, muc or sub.",[Name]);
        throw:node_not_reachable -> io_lib:format("node ~p is not reachable.",[Node]);
        throw:node_already_exists -> io_lib:format("node ~p already exists.", [Node])
    end.

del_store_node(NameString, NodeString) ->
    Name = erlang:list_to_atom(NameString),
    Node = erlang:list_to_atom(NodeString),
    try  Name == all orelse Name == muc orelse Name == sub orelse throw(invalid_name),
         OldNodes = get_store_nodes(Name),
         true == lists:member(Node, OldNodes) orelse throw(node_not_exists),
         set_store_nodes(Name, lists:delete(Node, OldNodes)),
         "success"
    catch
        throw:invalid_name -> io_lib:format("~p is not a valid node name. it must be one of all, muc or sub.",[Name]);
        throw:node_not_exists -> io_lib:format("node ~p does not exists.", [Node])
    end.

store_node_list() ->
    StoreNodesFun = fun(Name) ->
                            Nodes = get_store_nodes(Name),
                            [ atom_to_list(Node)|| Node <-  [Name|Nodes] ]
                    end,
    lists:flatmap(StoreNodesFun, [all, muc, sub]).

reset_store_nodes(NameString) ->
    Name = erlang:list_to_atom(NameString),
    try  Name == all orelse Name == muc orelse Name == sub orelse throw(invalid_name),
         set_store_nodes(Name, []),
         "success"
    catch
        throw:invalid_name -> io_lib:format("~p is not a valid node name. it must be one of all, muc or sub.",[Name])
    end.

get_store_nodes(Name) ->
    case ets:lookup(store_nodes, Name) of
        [] ->
            [];
        [#store_nodes{nodes=Nodes}] ->
            Nodes
    end.

set_store_nodes(Name, Nodes) when is_atom(Name), is_list(Nodes) ->
    ?INFO_MSG("Set store nodes to ~p~n", [Nodes]),
    ets:insert(store_nodes, #store_nodes{name=Name, nodes=Nodes});
set_store_nodes(Name, Nodes) ->
    ?ERROR_MSG("Invalid store nodes: ~p for name ~p~n", [Nodes, Name]).

random_store_node(Name) ->
    case msync_etcd_client:get_storenode(Name) of
        {error, disable_etcd_service_disc} ->
            random_store_node_origin(Name);
        {error, empty} ->
            random_store_node_origin(Name);
        {error, ErrorReason} ->
            ?ERROR_MSG("etcd client get store node error : ~p~n",
                       [ErrorReason]),
            random_store_node_origin(Name);
        {ok, Node} ->
            Node
    end.

random_store_node_origin(Name) ->
    case ets:lookup(store_nodes, Name) of
        [] ->
            undefined;
        [#store_nodes{nodes=[]}] ->
            undefined;
        [#store_nodes{nodes=Nodes}] ->
            {A, B, C} = os:timestamp(),
            random:seed(A, B, C),
            lists:nth(random:uniform(length(Nodes)), Nodes)
    end.

store_rpc(Name, M,F,A) ->
    case random_store_node(Name) of
        undefined ->
            ?DEBUG("No available store node ~n",[]),
            %% apply(M,F,A);
            %% todo: return {ok, Value}, {error, Reason}
            [];
        N ->
            ?DEBUG("Call store node: ~p with ~p:~p(~p)~n", [N,M,F,A]),
            case rpc:call(N,M,F,A, ?DEFAULT_RPC_TIMEOUT) of
                {badrpc, Reason} ->
                    ?WARNING_MSG("Fail to call store node ~p due to ~p~n",
                                 [N, Reason]),
                    [];
                R ->
                    R
            end
    end.

set_store_consistency(all) ->
    ets:insert(store_nodes, #store_nodes{name=consistency, nodes=all});
set_store_consistency(one) ->
    ets:insert(store_nodes, #store_nodes{name=consistency, nodes=one});
set_store_consistency(_) ->
    set_store_consistency(all).

op_by_consistency() ->
    case ets:lookup(store_nodes, consistency) of
        [#store_nodes{nodes=one}] ->
            async_dirty;
        _ ->
            sync_dirty
    end.

get_config() ->
    {ok, Config} = application:get_env(msync, store_nodes),
    Config.
