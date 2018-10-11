-module(ejabberd_bridge).
-author("wcy123@gmail.com").
-export([open_session/3,
         open_session/4,
         open_session/5,
         close_session/2,
         create_group/0,
         create_group/2,
         get_group/0,
         get_group/1,
         valid_ejabberd_nodes/0,
         rpc/3]).
-include("logger.hrl").
-include("pb_msync.hrl").
-include("jlib.hrl").

open_session(SID, JID, Socket) ->
    open_session(SID, JID, Socket, undefined).
open_session(SID, #'JID'{ domain = Server, client_resource= Resource} = JID, Socket, Version) ->
    open_session(SID, #'JID'{ domain = Server, client_resource= Resource} = JID, Socket, Version, []).
open_session(SID, #'JID'{ domain = Server, client_resource= Resource} = JID, Socket, Version, Ext)
  when is_binary(Server),
       is_binary(Resource) ->
    User = msync_msg:pb_jid_to_long_username(JID),
    Conn = msync_c2s,
    {{P1, P2, P3, P4},_} =  IPAddr =
        case read_ip_port(Socket) of
            {{_,_,_,_},_} = IPAddr0 -> IPAddr0;
            _ -> {{0,0,0,0},0}
        end,
    Info = [{ip, IPAddr},
            {conn, Conn},
            {socket, Socket},
            {auth_module, undefined},
            {client_version, Version}] ++ Ext,

    msync_c2s_lib:set_socket_prop(Socket, ip_port, IPAddr),
    %% {{{1446,946528,201806},<0.1329.0>},
    %% <<"easemob-demo#chatdemoui_user2">>,<<"easemob.com">>,<<"mobile">>,0,{xmlel,<<"presence">>,[{<<"type">>,<<"time_statistics">>},{<<"id">>,<<"D6C6FAB8-8DBD-4721-9C0F-006D6D343EA3">>}],[{xmlel,<<"im_login_time">>,[],[{xmlcdata,<<"1889">>}]}]},[{ip,{{127,0,0,1},43409}},{conn,c2s_compressed},{auth_module,ejabberd_auth_thrift}]}
    %%
    %% Presence = {xmlel,<<"presence">>,[]},
    easemob_metrics_statistic:inc_counter(login),
    msync_log:on_user_login(JID, login, Info),
    easemob_statistics:user_login(JID#'JID'.app_key),
    ?INFO_MSG("(~p.~p.~p.~p) msync open session for ~s, Socket = ~p~n",
              [P1, P2, P3, P4, msync_msg:pb_jid_to_binary(JID), Socket]),
    %% open a session asynchronously, because we don't care about
    %% whether it is OK or not, even throug it fails, the client could
    %% still get unread messages by heart beat. It is nonblocking so
    %% that the number of workers will not be very high and system is
    %% still responsive.
    spawn(easemob_session, open_session, [SID, User, Server, Resource, Info]),
    %% it seems that the set_presence has no effect.
    %% rpc(ejabberd_sm,set_presence, [SID, User, Server, Resource, Priority,
    %%
    ok.

close_session(SID, #'JID'{ domain = Server, client_resource = Resource } = JID)
  when is_binary(Server),
       is_binary(Resource) ->
    ?INFO_MSG("close session, jid: ~p, sid: ~p~n", [JID, SID]),
    User = msync_msg:pb_jid_to_long_username(JID),
    spawn(easemob_session,close_session, [SID, User, Server, Resource]),
    ok.

create_group() ->
    RoomName = <<"easemob-demo#chatdemoui_1234567">>,
    RoomOpts =
        [
         {members_by_default,true},
         {allow_user_invites,false},
         {title,<<"g1">>},
         {description,<<"the first group">>},
         {public,true},
         {members_only,false},
         {max_users,500},
         {public,true},
         {affiliations,
          [{{<<"easemob-demo#chatdemoui_user1">>,<<"easemob.com">>,<<>>},owner},
           {{<<"easemob-demo#chatdemoui_user2">>,<<"easemob.com">>,<<>>},member}
          ]}],
    create_group(RoomName, RoomOpts).
create_group(RoomName, RoomOpts) ->
    Service = <<"conference.easemob.com">>,
    Domain = <<"easemob.com">>,
    rpc(mod_muc_admin,create_room,[RoomName, Service, Domain, RoomOpts]).

get_group() ->
    RoomName = msync_msg:parse_jid(<<"easemob-demo#chatdemoui_1234567@conference.easemob.com">>),
    get_group(RoomName).
get_group(#'JID'{ domain = Service } = JID) ->
    RoomName = msync_msg:pb_jid_to_long_username(JID),
    Domain = <<"easemob.com">>,
    Service = <<"conference.easemob.com">>,
    case rpc(mod_muc_admin,get_online_room,[RoomName, Service, Domain]) of
        [R] ->
            {ok, R};
        [] ->
            {error, not_found}
    end.

%% valid_ejabberd_nodes() ->
%%     Nodes = sets:from_list(nodes()),
%%     DefinedNodes = sets:from_list(application:get_env(msync,ejabberd_nodes,[])),
%%     ValidNodes = sets:intersection(Nodes, DefinedNodes),
%%     _ValidNodesList = sets:to_list(ValidNodes).

valid_ejabberd_nodes() ->
    application:get_env(msync,ejabberd_nodes,[]).

ejabberd_node() ->
    ValidNodesList = valid_ejabberd_nodes(),
    case ValidNodesList of
        [] -> undefined;
        _  -> random_nth(ValidNodesList)
    end.

random_nth(List)
  when is_list(List) ->
    X = abs(time_compat:monotonic_time()
                bxor time_compat:unique_integer()),
    lists:nth((X rem length(List)) + 1, List).


rpc(M,F,A) ->
    EjabberdNode = ejabberd_node(),
    case EjabberdNode of
        undefined ->
            ?WARNING_MSG("no ejabberd node for rpc: MFA=~p:~p(~p)~n",[M,F,A]),
            {error, {badrpc, nonode}};
        _ ->
            case rpc:call(EjabberdNode,M,F,A, 5000) of
                {badrpc, Reason} ->
                    ?WARNING_MSG("ejabberd rpc error: reason=~p Node= ~p MFA=~p:~p(~p)~n",[Reason, EjabberdNode, M,F,A]),
                    {error, {badrpc, Reason}};
                Else ->
                    ?DEBUG("ejabberd rpc OK: Value=~p MFA=~p:~p(~p)~n",[Else, M,F,A]),
                    Else
            end
    end.

read_ip_port(Socket) ->
    case inet:peername(Socket) of
        {ok, {Address, Port}} ->
            {Address, Port};
        {error, _}  ->
            undefined
    end.


%% timer:tc(fun() -> A =
