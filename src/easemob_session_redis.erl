-module(easemob_session_redis).
-export([
          open_session/5,
          close_session/4,
          get_all_sessions/2,
          get_session/3,
          get_all_sessions_pipeline/1,
          get_counter_current/2,
          get_counter_today/2,
          get_counter_yesterday/2,
          get_counter_week/2,
          get_counter_month/2,
          get_counter_timestamp/2,
          send_retrive_dns_msg/2
        ]).

-include("logger.hrl").
-include("pb_jid.hrl").
-include("easemob_session.hrl").

-define(KEYPREFIX, <<"im:sr:">>).

-define(ADMIN_USER, <<"admin">>).
-define(CURRENT, <<"current">>).
-define(TODAY, <<"today">>).
-define(YESTERDAY, <<"yesterday">>).
-define(WEEK, <<"week">>).
-define(MONTH, <<"month">>).
-define(TIMESTAMP, <<"timestamp">>).

open_session(SID, User, Server, Resource, Info) ->
    Priority = 0, %% it must be zero, otherwise, the user is not presence
    LUser = jlib:nodeprep(User),
    LServer = jlib:nameprep(Server),
    LResource = jlib:resourceprep(Resource),
    US = {LUser, LServer},
    USR = {LUser, LServer, LResource},
    Session = #session{sid = SID, usr = USR, us = US, priority = Priority, info = Info},

    easemob_redis:q(get_session_worker(),
                    [hset, get_redis_key(User), Resource, erlang:term_to_binary(Session)]),

    case application:get_env(msync, session_counter, false) of
        true ->
            incr_session_counter(LServer, LUser);
        false ->
            undefined
    end.

close_session(SID, User, Server, Resource) ->
    case get_session(User, Server, Resource) of
        {ok, CurrentSID} ->
            case CurrentSID#session.sid == SID of
                true ->
                    easemob_redis:q(get_session_worker(), [hdel, get_redis_key(User), Resource]),
                    case application:get_env(msync, session_counter, false) of
                        true ->
                            decr_session_counter(Server, User);
                        false ->
                            undefined
                    end;
                false ->
                    ok
            end;
        {error, not_found} ->
            ok
    end.

%% e.g. get_session(<<"easemob-demo#chatdemoui_c1">>, <<"easemob.com">>, <<"mobile">>)
get_session(User, Server, Resource)
  when is_binary(User),
       is_binary(Server),
       is_binary(Resource)->
    case  easemob_redis:q(get_session_worker(),
                          [hget, get_redis_key(User), Resource]) of
        {ok, undefined} ->
            {error, not_found};
        {ok, SessionBinary} ->
            {ok, erlang:binary_to_term(SessionBinary)};
        {error, Reason} ->
            {error, Reason}
    end.

get_all_sessions(User, Server) ->
    case easemob_redis:q(get_session_worker(), [hgetall, get_redis_key(User)]) of
        {ok,Value} ->
            {ok, lists:map(fun({_R,S}) -> binary_to_term(S) end, list2plist(Value))};
        {error,Reason} ->
            {error, Reason}
    end.

-spec get_all_sessions_pipeline(UserNameList :: [binary()]) ->
                                       [{binary(), list()}].
get_all_sessions_pipeline(UserNameList) ->
    Worker = get_session_worker(),
    Qs = lists:map(fun (User) ->
                           [hgetall, get_redis_key(User)]
                   end, UserNameList),
    case easemob_redis:qp(Worker, Qs) of
        {error, _Reason} ->
            [];
        ResList ->
            lists:zipwith(fun (User, Res) ->
                                  case Res of
                                      {ok, ResSessionList} ->
                                          {User, parse_sessions(ResSessionList)};
                                      _ ->
                                          {User, []}
                                  end
                          end, UserNameList, ResList)
    end.

get_redis_key(User) ->
    << ?KEYPREFIX/binary, User/binary >>.

get_session_worker() ->
    case application:get_env(message_store, use_new_session_codis, false) of
        true ->
            new_codis_session;
        _ ->
            codis_session
    end.

parse_sessions(ResSessionList) ->
    parse_sessions(ResSessionList, []).

parse_sessions([], Acc) ->
    Acc;
parse_sessions([_, Session | T], Acc) ->
    parse_sessions(T, [binary_to_term(Session) | Acc]).

%% app session counter interface
-spec incr_session_counter(binary(), binary()) -> ok.

incr_session_counter(Host, User) ->
  Counter = incr_counter(Host, User),
  Limit = app_config:get_max_sessions(User),
  case Counter > Limit of
    true ->
      case app_config:is_max_sessions_limit(User) of
        true ->
          ?WARNING_MSG("~s app online sessions exceed limit ~p, limit login for ~s", 
            [binary:bin_to_list(app_config:get_user_appkey(User)), Limit, binary:bin_to_list(User)]),
          rpc:cast(node(), ?MODULE, send_retrive_dns_msg, [User, Host]);
        _ ->
          ?WARNING_MSG("~s app online sessions exceed limit ~p, but not limit login for ~s", 
            [binary:bin_to_list(app_config:get_user_appkey(User)), Limit, binary:bin_to_list(User)])
      end;
    _ ->
      ok
  end,
  ok.

-spec decr_session_counter(binary(), binary()) -> ok.

decr_session_counter(Host, User) ->
  decr_counter(Host, User),
  ok.

-spec send_retrive_dns_msg(binary(), binary()) -> ok.

send_retrive_dns_msg(User, Server) ->
    [AppKey|[To]] = binary:split(User, <<"_">>),
    MsgBody = << <<"{\"from\":\"">>/binary, ?ADMIN_USER/binary,
                <<"\",\"to\":\"">>/binary, To/binary,
                <<"\",\"bodies\":[{\"type\":\"cmd\",\"action\":\"em_retrieve_dns\",\"target\":[\"">>/binary,To/binary,<<"\"]}]}">>/binary >>,

    FromJID = jlib:make_jid(iolist_to_binary([AppKey,"_", ?ADMIN_USER]), Server, <<>>),
    ToJID = jlib:make_jid(User, Server, <<>>),
    XmlBody = {xmlel, <<"message">>,
               [{<<"id">>, erlang:integer_to_binary(msync_uuid:generate_msg_id())},
                {<<"type">>, <<"chat">>},
                {<<"from">>, <<?ADMIN_USER/binary, <<"@">>/binary, Server/binary >>},
                {<<"to">>, <<User/binary, <<"@">>/binary, Server/binary >>}],
               [{xmlel, <<"body">>, [],
                 [{xmlcdata, MsgBody}]}]},

    Meta = msync_meta_converter:from_xml(XmlBody),
    msync_route:save_and_route(msync_msg:jid_to_pb_jid(FromJID), msync_msg:jid_to_pb_jid(ToJID), Meta),
    ?DEBUG("send retrive dns msg:~p", [XmlBody]).

incr_counter(Host, User) ->
  AppKey = app_config:get_user_appkey(User),
  ?DEBUG("incr login session counter ~p",[AppKey]),
  Plist = get_counter_inner(Host, AppKey),
  incr_counters_inner(Host, AppKey, Plist),
  get_counter(Plist, ?TODAY).

decr_counter(Host, User) ->
  AppKey = app_config:get_user_appkey(User),
  ?DEBUG("decr login session counter ~p",[AppKey]),
  decr_counter_inner(Host, AppKey, ?CURRENT).

get_counter_current(Host, AppKey) ->
  get_counter(Host, AppKey, ?CURRENT).

get_counter_today(Host, AppKey) ->
  get_counter(Host, AppKey, ?TODAY).

get_counter_yesterday(Host, AppKey) ->
  get_counter(Host, AppKey, ?YESTERDAY).

get_counter_week(Host, AppKey) ->
  get_counter(Host, AppKey, ?WEEK).

get_counter_month(Host, AppKey) ->
  get_counter(Host, AppKey, ?MONTH).

get_counter_timestamp(Host, AppKey) ->
  get_counter(Host, AppKey, ?TIMESTAMP).

incr_counters_inner(Host, AppKey, Plist) ->
  Cur = get_counter(Plist, ?CURRENT),
  Tmax = get_counter(Plist, ?TODAY),
  Ymax= get_counter(Plist, ?YESTERDAY),
  Week = get_counter(Plist,?WEEK),
  Month = get_counter(Plist, ?MONTH),
  Ttp = get_counter(Plist, ?TIMESTAMP),
  %% increase current counter
  incr_counter_inner(Host, AppKey, ?CURRENT),
  %% increase today max sessions
  case Cur+1 > Tmax of
    true ->
      incr_counter_inner(Host, AppKey, ?TODAY);
    _ ->
      ok
  end,
  %% update yesterday, week, month sessions counter
  TodayTp = get_today_timestamp(),
  case TodayTp =/= Ttp of
    true ->
      Ynmax = erlang:max(Ymax, erlang:max(Tmax, Cur+1)),
      set_counter_inner(Host, AppKey, ?TIMESTAMP, TodayTp),
      set_counter_inner(Host, AppKey, ?TODAY, Cur+1),
      set_counter_inner(Host, AppKey, ?YESTERDAY, Ynmax),
      set_counter_inner(Host, AppKey, ?WEEK, (Week*6+Ynmax) div 7),
      set_counter_inner(Host, AppKey, ?MONTH, (Month*29+Ynmax) div 30);
    _ ->
      ok
  end.

set_counter_inner(_Host, AppKey, Type, Value) ->
  easemob_redis:q(get_session_worker(),["HSET", get_redis_key(AppKey), Type, Value]).

incr_counter_inner(_Host, AppKey, Type) ->
  case easemob_redis:q(get_session_worker(), ["HINCRBY", get_redis_key(AppKey), Type, 1]) of
    {error, _} ->
      -1;
    {ok, Value} ->
      erlang:binary_to_integer(Value)
  end.

decr_counter_inner(_Host, AppKey, Type) ->
  easemob_redis:q(get_session_worker(), ["HINCRBY", get_redis_key(AppKey), Type, -1]).

get_counter(Host, AppKey, Type) ->
    case proplists:get_value(Type, get_counter_inner(Host, AppKey), not_found) of
        not_found ->
            -1;
        Value ->
            erlang:binary_to_integer(Value)
    end.

get_counter(Plist, Type) ->
    case proplists:get_value(Type, Plist, not_found) of
        not_found ->
            0;
        Value ->
            erlang:binary_to_integer(Value)
    end.

get_counter_inner(_Host, AppKey) ->
  case easemob_redis:q(get_session_worker(), ["HGETALL", get_redis_key(AppKey)]) of
    {ok,Value} ->
          lists:map(fun({F,C}) -> {F, C} end,list2plist(Value));
    {error,Reason} ->
          ?ERROR_MSG("cannot get session due to ~w~n", Reason),
          []
  end.

get_today_timestamp() ->
  {M,S,_} = os:timestamp(),
  (M*1000000+S)-(M*1000000+S) rem 86400.

%% TODO: move this function to a common utilities library
list2plist(L) ->
    list2plist(L,[]).
list2plist([], Acc) ->
    lists:reverse(Acc);
list2plist([K], Acc) ->
    lists:reverse([{K,undefined} | Acc]);
list2plist([K,V|T], Acc) ->
    list2plist(T, [{K,V} | Acc]).

%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

open_close_test() ->
    User =  <<"easemob-demo#chatdemoui_cy">>,
    Server = <<"easemob.com">>,
    Resource = <<"mobile">>,
    Conn = msync_c2s,
    IPAddr = {{0,0,0,0},0},
    Socket = socket,
    Info = [{ip, IPAddr},
            {conn, Conn},
            {socket, Socket},
            {auth_module, undefined}],
    SID = {os:timestamp(), {msync_c2s, node()} },
    {ok, <<"1">>} = open_session(SID, User,Server,Resource, Info),
    LUser = jlib:nodeprep(User),
    LServer = jlib:nameprep(Server),
    LResource = jlib:resourceprep(Resource),
    US = {LUser, LServer},
    USR = {LUser, LServer, LResource},
    [
     Session = #session{sid = SID, usr = USR, us = US, priority = 0, info = Info}
    ] = get_session(User, Server, Resource),
    io:format("~p~n", [Session]),
    {ok, <<"1">>} = close_session(SID, User, Server, Resource).
-endif.
