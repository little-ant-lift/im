-module(media_server).
-behavior(gen_server).

-export([init/1, handle_call/3,
         handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([start_link/0, stop/0, handle_error/2, handle_function/2]).

-export([mediaRequest/2]).

-export([test/0, test1/0, test2/0]).

-include("logger.hrl").
-include("pb_msync.hrl").
-include("pb_conferencebody.hrl").
-include_lib("gen-erl/rtc_service_types.hrl").

-record(state, {server_pid}).
-define(SERVICE, media_server_thrift).


start_link()->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([])->
    {ok, Port} = application:get_env(media_server_port),
    Pid = thrift_socket_server:start([{handler, ?MODULE},
                                      {service, ?SERVICE},
                                      {port, Port},
                                      {socket_opts, [{recv_timeout, infinity}
                                                    ]},
                                      {framed, true},
                                      {name, user_service_server}]),
    {ok, #state{server_pid = Pid}}.

stop()->
    gen_server:call(?MODULE, stop).

handle_call(stop, _From, State)->
    {stop, normal, ok, State};
handle_call(_, _From, State)->
    {reply, ok, State}.

handle_cast(_, State)->
    {noreply, State}.

handle_info(_Info, State)->
    {noreply, State}.

terminate(_Reason, #state{server_pid = Pid})->
    thrift_server:stop(Pid),
    ok.

code_change(_OldVar, State, _Extra)->
    {ok, State}.

handle_function(Function, Args) when is_atom(Function), is_tuple(Args) ->
    case apply(?MODULE, Function, tuple_to_list(Args)) of
        ok -> {reply, <<"ok">>};
        Reply -> {reply, Reply}
    end.

handle_error(undefined, closed) ->
    ?DEBUG("Socket Conference Server to IM is ~p~n", [closed]);
handle_error(undefined, Reason) ->
    ?INFO_MSG("Connnection problem in thrift server, reason: ~p ~n", [Reason]);
handle_error(Function, Reason) ->
    ?ERROR_MSG("Error in thrift server, stub function ~p has problem ~p , stack: ~p~n ",
               [Function, Reason, erlang:get_stacktrace()]).

mediaRequest(Header, Meta)->
    Header1 = jsx:decode(Header, [return_maps]),
    Meta1 = msync_msg:decode_meta(Meta),
    do_mediaRequest(Header1, Meta1).

do_mediaRequest(#{<<"op">> := <<"getClt">>, <<"jid">> := JID} = _Header, _)->
    JID1 = jlib:string_to_jid(JID),
    {U, S, _R} = jlib:jid_tolower(JID1),
    case easemob_session:get_all_sessions(U, S) of
        {ok, Sessions} ->
            ResFilter =
            fun(Session)->
                    R1 = easemob_session:get_resource(Session),
                    Version = easemob_session:get_client_version(Session),
                    {Os, SdkVer} = get_client_version(Version),
                    {{P1, P2, P3, P4}, _Port} = easemob_session:get_user_ip(Session),
                    IP = lists:concat([P1, ".", P2, ".", P3, ".", P4]),
                    [{ip, list_to_binary(IP)},
                     {sdkVer, SdkVer},
                     {client_type, Os},
                     {resource, R1}, {online, true}]
            end,
            Infos = lists:map(ResFilter, Sessions),
            jsx:encode([{result, 0}, {info, Infos}]);
        {error, _} ->
            ?INFO_MSG(" can't get session of user: ~p", [JID]),
            jsx:encode([{result, 0}, {info, []}])
    end;
do_mediaRequest(#{<<"op">> := <<"sendmsg">>}, Meta)->
    ?INFO_MSG(" sendmsg ~p", [Meta]),
    FromJid = msync_msg:get_meta_from(Meta),
    ToJid = msync_msg:get_meta_to(Meta),
    Meta1 = msync_msg:allocate_meta_id(Meta),
    Meta2 = msync_msg:generate_timestamp(Meta1),
    msync_route:save(FromJid, ToJid, Meta2),
    msync_route:route_online_only(FromJid, ToJid, Meta2),
    jsx:encode([{result, 0}]).

get_client_version({Os, undefined}) ->
    {Os, undefined};
get_client_version({Os, Version}) ->
    SdkVer = easemob_version:to_binary(Version),
    {Os, SdkVer};
get_client_version(_) ->
    {undefined, undefined}.

test()->
    From = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                  name = <<"c1">>,domain = <<"easemob.com">>,
                  client_resource = <<"mobile">>},
    To = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c2">>,domain = <<"easemob.com">>,
                client_resource = <<"mobile">>},
    Header = jsx:encode([{from, msync_msg:pb_jid_to_binary(From)},
                         {to, msync_msg:pb_jid_to_binary(To)},
                         {op, getClt},
                         {jid, msync_msg:pb_jid_to_binary(From)}]),
    io:format("------1------header is: ~p~n", [Header]),
    Content = #'ConferenceBody'{session_id = <<"1461218722470">>,
                              operation = 'MEDIA_REQUEST',conference_id = undefined,
                              type = 'VIDEO',content = undefined,network = <<"wifi">>,
                              version = <<"3.0.0">>,identity = 'CALLER',
                              duration = undefined,peer_name = undefined,
                              end_reason = undefined,status = undefined,is_direct = true,
                              control_type = 'PAUSE_VOICE', route_flag = 1, route_key = "--X--"},
    Meta = msync_msg:new_meta(From, To, 'CONFERENCE', Content),

    im_thrift:call(?SERVICE, 'mediaRequest', [Header, msync_msg:encode_meta(Meta)]).

make_test_meta() ->
    From = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                  name = <<"c1">>,domain = <<"easemob.com">>,
                  client_resource = <<"mobile">>},
    To = #'JID'{app_key = <<"easemob-demo#chatdemoui">>,
                name = <<"c2">>,domain = <<"easemob.com">>,
                client_resource = <<"mobile">>},
    Content = #'ConferenceBody'{session_id = <<"1461218722470">>,
                              operation = 'MEDIA_REQUEST',conference_id = undefined,
                              type = 'VIDEO',content = undefined,network = <<"wifi">>,
                              version = <<"3.0.0">>,identity = 'CALLER',
                              duration = undefined,peer_name = undefined,
                              end_reason = undefined,status = undefined,is_direct = true,
                              control_type = 'PAUSE_VOICE', route_flag = 1, route_key = "--X--"},
    msync_msg:new_meta(From, To, 'CONFERENCE', Content).
test1()->
    Meta = make_test_meta(),
    do_mediaRequest(#{<<"op">> => <<"sendmsg">>}, Meta).

test2()->
    Meta = make_test_meta(),
    do_mediaRequest(#{<<"op">> => <<"getClt">>, <<"jid">> => <<"easemob-demo#chatdemoui_c1@easemob.com">>}, Meta).
