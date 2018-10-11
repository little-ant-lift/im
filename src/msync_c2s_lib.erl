-module(msync_c2s_lib).
-export([
         create_tables/0,
         maybe_open_session/2,
         open_session/2,
         open_session/3,
         open_session/4,
         get_resources/1,
         maybe_close_session/1,
         maybe_close_session/2,
         get_pb_jid_prop/2,
         get_socket_prop/2,
         set_socket_prop/3,
         search_sessions/2
        ]).
-include("logger.hrl").
-include("pb_mucbody.hrl").
%% be careful to change this structure, there are might millions of
%% such records, so that memory usage will be an issue.
%%
%% Via a ets table msync_c2s_data, we can map a socket to a MSyncId
%% which does not have server_resource, because server_resource is not
%% reliable due to bad mobile network. In addtion, we can map the MSyncId
%% MSyncId key for table lookup.

-record(c2s_socket, {
          pb_jid,
          compression_algorithm = undefined,
          shaper = shaper:new(normal),
          version = undefined,
          ip_port = undefined
         }).

-record(c2s, {
          client_resource,
          socket,
          sid
         }).

create_tables() ->
    msync_c2s_tbl_sockets = ets:new(msync_c2s_tbl_sockets,
                                    [named_table, set, public,  {read_concurrency,true}]),
    msync_c2s_tbl_pb_jid = ets:new(msync_c2s_tbl_pb_jid,
                                   [named_table, bag, public, {read_concurrency,true}]).
%% @doc open a session for a known JID, but if JID is unknown
%% (non-authorized), the session is not opened.
maybe_open_session(undefined,_Socket) ->
    ?DEBUG("open an unknown session, please check msync_c2s_handler_auth:try_authenticate/1",[]),
    undefined;
maybe_open_session(#'JID'{}=JID,Socket)
  when is_port(Socket) ->
    open_session(JID,Socket).

open_session(#'JID'{} = JID, Socket)
    when is_port(Socket)->
    open_session(JID, Socket, undefined).
open_session(#'JID'{} = JID, Socket, Version)
  when is_port(Socket) ->
    new_socket_entry(Socket, JID),
    SID = {os:timestamp(), {self(), msync}},
    new_pb_jid_entry(JID, Socket, SID),
    ejabberd_bridge:open_session(SID, JID, Socket, Version),
    JID.
open_session(#'JID'{} = JID, Socket, Version, Ext)
  when is_port(Socket)
       ->
    new_socket_entry(Socket, JID),
    SID = {os:timestamp(), {self(), msync}},
    new_pb_jid_entry(JID, Socket, SID),
    ejabberd_bridge:open_session(SID, JID, Socket, Version, Ext),
    JID.

%% close session if there is a session associated with `Socket`.
maybe_close_session(X) ->
    maybe_close_session(X, normal).

maybe_close_session(#'JID'{} = JID, _Mode) ->
    %% TODO: to be deprecated
    ?ERROR_MSG("never goes here~n",[]),
    case get_pb_jid_prop(JID,socket) of
        {ok, Socket} -> close_session(JID, Socket, normal);
        {error, {many_found, Sessions}} ->
            lists:map(fun([Socket, _]) ->
                              close_session(JID, Socket, normal)
                      end, Sessions);
        {error, not_found} ->
            ok
    end,
    self() ! {stop, {shutdown, close_session}};

maybe_close_session(Socket,Mode)
  when is_port(Socket)->
    MaybeJID = get_socket_prop(Socket,pb_jid),
    case MaybeJID of
        {ok, #'JID'{} = JID } ->
            on_close_socket(JID, Socket),
            maybe_logout_chatroom(Socket),
            close_session(JID, Socket, Mode);
        {error, _Reason} ->
            %% session is not created yet, so ignore it.
            ignore
    end,
    self() ! {stop, {shutdown, close_session}}.

%% @doc close a session
close_session(undefined, Socket, _Mode) ->
    ?DEBUG("close session for unkown session",[]),
    delete_socket_entry(Socket);
close_session(JID, Socket, Mode) ->
    MaybeSID = get_pb_jid_prop(JID, sid),
    ?INFO_MSG("close session for ~s, Socket = ~p, SID = ~p~n",
              [msync_msg:pb_jid_to_binary(JID), Socket, MaybeSID]),
    case MaybeSID of
        {ok, SID} ->
            cleanup_session(Socket, SID, JID, Mode);
        {error, {many_found, List} } ->
            lists:foreach(
              fun([Socket1, SID1]) ->
                      if Socket =:= Socket1 ->
                              cleanup_session(Socket1, SID1, JID, Mode);
                         true -> ignore
                      end
              end, List);
        {error, Reason} ->
            ?WARNING_MSG("cannot get sid ~s, reason = ~p",[msync_msg:pb_jid_to_binary(JID), Reason])
    end,
    delete_socket_entry(Socket).

cleanup_session(Socket, SID, JID, Mode) ->
    delete_pb_jid_entry(JID,Socket,SID),
    case Mode of
        normal ->
            ejabberd_bridge:close_session(SID,JID);
        replaced ->
            ignore;
        _ ->
            ?WARNING_MSG("unexpected close session mode: ~p~n",[Mode])
    end.

on_close_socket(#'JID'{} = JID, Socket) when is_port(Socket)->
    {ok, Version} = get_socket_prop(Socket, version),
    Ip = case get_socket_prop(Socket, ip_port) of
          {ok, Value} -> Value;
          {error, not_found} -> undefined
          end,
    Infos = [{ip, Ip}, {client_version, Version}],
    ?DEBUG("Infos:~p~n", [Infos]),
    easemob_metrics_statistic:inc_counter(logout),
    msync_log:on_user_logout(JID, logout, Infos).

new_socket_entry(Socket,#'JID'{} = JID) ->
    ?INFO_MSG(" new socket ~p of jid ~p", [Socket, JID]),
    true = ets:insert(msync_c2s_tbl_sockets,
                      erlang:setelement(1,
                                        %% dirty hack to save 1 word memory in the c2s_socket
                                        #c2s_socket{ pb_jid = JID},
                                        Socket
                                       )).
%% @doc mapping a socket to an pb_jid, undefined if not found
get_socket_prop(Socket,Prop) ->
    try get_socket_prop_1(Socket,Prop)
    catch
        error:badarg ->
            {error, ets_error, erlang:get_stacktrace()}
    end.

get_socket_prop_1(Socket, ip_port) ->
    get_socket_prop_imp(Socket, #c2s_socket.ip_port);
get_socket_prop_1(Socket, pb_jid) ->
    get_socket_prop_imp(Socket,#c2s_socket.pb_jid);
get_socket_prop_1(Socket, compression_algorithm) ->
    get_socket_prop_imp(Socket,#c2s_socket.compression_algorithm);
get_socket_prop_1(Socket, version) ->
    get_socket_prop_imp(Socket,#c2s_socket.version);
get_socket_prop_1(Socket, shaper) ->
    get_socket_prop_imp(Socket,#c2s_socket.shaper).
delete_socket_entry(Socket) ->
    ?INFO_MSG(" delete socket ~p", [Socket]),
    ets:delete(msync_c2s_tbl_sockets, Socket).

get_socket_prop_imp(Socket,KeyIndex) ->
    try
        Value = ets:lookup_element(msync_c2s_tbl_sockets, Socket, KeyIndex),
        {ok, Value}
    catch
        error:badarg -> {error, not_found}
    end.

set_socket_prop(Socket,Prop, Value) ->
    try set_socket_prop_1(Socket,Prop,Value)
    catch
        error:badarg ->
            {error, ets_error, erlang:get_stacktrace()}
    end.
set_socket_prop_1(Socket, compression_algorithm, Value) ->
    set_socket_prop_imp(Socket,#c2s_socket.compression_algorithm, Value);
set_socket_prop_1(Socket, version, Value) ->
    set_socket_prop_imp(Socket,#c2s_socket.version, Value);
set_socket_prop_1(Socket, shaper, Value) ->
    set_socket_prop_imp(Socket,#c2s_socket.shaper, Value);
set_socket_prop_1(Socket, ip_port, Value) ->
    set_socket_prop_imp(Socket, #c2s_socket.ip_port, Value).

set_socket_prop_imp(Socket,KeyIndex,Value) ->
    try ets:update_element(msync_c2s_tbl_sockets, Socket, {KeyIndex, Value})
    catch
        error:badarg -> {error, not_found}
    end.

new_pb_jid_entry(#'JID'{
                    app_key = AppKey,
                    name = Name,
                    domain = Domain,
                    client_resource = Resource
                   } = JID, Socket, SID) ->
    %% true = erlang:is_port(Socket),
    ?INFO_MSG(" new pb jid ~p ~p", [JID, Socket]),
    true = ets:insert(msync_c2s_tbl_pb_jid,
                      erlang:setelement(1,
                                        %% dirty hack to save 1 word memory in the c2s
                                        #c2s{
                                           socket = Socket,
                                           sid = SID,
                                           client_resource = Resource
                                          },
                                        { AppKey, Name, Domain}
                                       )).

get_pb_jid_prop(#'JID'{}=JID, socket) ->
    get_pb_jid_prop_imp(JID, #c2s.socket);
get_pb_jid_prop(#'JID'{}=JID, sid) ->
    get_pb_jid_prop_imp(JID, #c2s.sid).

get_pb_jid_prop_imp(#'JID'{
                       app_key = AppKey,
                       name = Name,
                       domain = Domain,
                       client_resource = Resource
                      }, Key) ->
    case ets:match(msync_c2s_tbl_pb_jid,
                   {
                     {AppKey, Name, Domain},
                     Resource,
                     '$1',                      %socket
                     '$2'                       %sid
                   }) of
        [] -> {error, not_found};
        [R] -> {ok, lists:nth(Key - 2, R)};
        List ->
            {error, {many_found,  List}}
    end.
%% delete_pb_jid_entry(#'JID'{
%%                       app_key = AppKey,
%%                       name = Name,
%%                       domain = Domain,
%%                       client_resource = Resource
%%                      }) ->
%%     case ets:match(msync_c2s_tbl_pb_jid,
%%                    {
%%                      {AppKey, Name, Domain},
%%                      Resource,               %resource
%%                      '$1',                   %socket
%%                      '$2'                    %sid
%%                    }) of
%%         List ->
%%             lists:foreach(
%%               fun(L) ->
%%                       ets:delete_object(msync_c2s_tbl_pb_jid,
%%                                         {
%%                                           {AppKey, Name, Domain},
%%                                           Resource, %resource
%%                                           lists:nth(1,L), %% '$1', %socket
%%                                           lists:nth(2,L)  %% '$2' %sid
%%                                         })
%%               end, List)
%%     end.
delete_pb_jid_entry(#'JID'{
                      app_key = AppKey,
                      name = Name,
                      domain = Domain,
                      client_resource = Resource
                     } = JID, Socket, SID) ->
    ?INFO_MSG(" delete pb jid ~p ~p", [JID, Socket]),
    ets:delete_object(msync_c2s_tbl_pb_jid,
                      {
                        {AppKey, Name, Domain},
                        Resource, %resource
                        Socket,
                        SID
                      }).

get_resources(#'JID'{
                 app_key = AppKey,
                 name = Name,
                 domain = Domain
                }) ->
    case ets:match(msync_c2s_tbl_pb_jid,
                   {
                     {AppKey, Name, Domain},
                     '$1',                   %resource
                     '$2',                   %socket
                     '$3'                    %sid
                   }) of
        [] -> {error, not_found};
        List ->
            lists:map(
              fun(L) ->
                 { lists:nth(1,L),              %resource
                   lists:nth(2,L),              %socket
                   lists:nth(3,L)               %sid
                 }
              end,  List)
    end.


search_sessions(AppKey0, RE) ->
    ?DEBUG("AppKey0 = ~p, RE = ~p~n", [AppKey0, RE]),
    F = fun({
              {AppKey, Name, Domain},
              Resource,
              _Socket,
              {Timestamp, _ExtenedPid}
            }, Acc)
           when AppKey =:= AppKey0
                ->
                case re:run(Name, RE) of
                    nomatch ->
                        Acc;
                    {match, _Capture } ->
                        [#{
                            app_key => AppKey,
                            name => Name,
                            domain => Domain,
                            resource => Resource,
                            timestamp => tuple_to_list(Timestamp)
                          } | Acc]
                end;
           ( _, Acc) -> Acc
        end,
    ets:foldl(F, [], msync_c2s_tbl_pb_jid).

%% send leave to chatroom for logout
%% when close session and replace session
maybe_logout_chatroom(Socket)
  when is_port(Socket)->
    MaybeJID = msync_c2s_lib:get_socket_prop(Socket,pb_jid),
    case MaybeJID of
        {ok, #'JID'{} = JID } ->
            User = msync_msg:pb_jid_to_long_username(JID),
            Server = JID#'JID'.domain,
            Service = <<"conference.", Server/binary>>,
            NewJID = JID#'JID'{app_key = undefined, domain = undefined, client_resource = undefined},
            To = JID#'JID'{app_key = undefined, name = undefined, client_resource = undefined},
            Rooms0 = easemob_muc:read_user_chatrooms(User),
            case Rooms0 of
                [] ->
                    ok;
                Rooms ->
                    lists:foreach(
                        fun(Room) ->
                            [AppKey, UserName] = binary:split(Room, <<"_">>),
                            Des = msync_msg:pb_jid(AppKey, UserName, Service, undefined),
                            PayLoad = #'MUCBody'{muc_id = Des, operation = 'LEAVE', from = NewJID, to = []},
                            Meta = msync_msg:new_meta(JID, To, 'MUC', PayLoad),
                            process_system_queue:route(JID, JID, Des, Meta)
                        end,
                    Rooms),
                    ok
            end;
        {error, _Reason} ->
            %% session is not created yet, so ignore it.
            ignore
    end.
