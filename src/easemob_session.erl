-module(easemob_session).
-export([open_session/5, close_session/4, get_all_sessions/2, get_session/3
         , replace_session/1
        ]).
%% session properties
-export([get_user_ip/1,
         get_client_version/1,
         get_resource/1,
         get_socket/1
        ]).
-export([set_session_db_type/1, get_session_db_type/0]).
-include("logger.hrl").
-include("easemob_session.hrl").



open_session(SID, User, Server, Resource, Info) ->
    %% get old sessions if any
    MaybeSession =
        case get_session(User, Server, Resource) of
            {ok, S} ->
                [S];
            _ ->
                []
        end,
    {_, NewPId} = SID,
    %% create new sessions
    maybe_spawn(get_the_other_session_module(), open_session, [SID, User, Server, Resource, Info]),
    Res = (get_session_module()):open_session(SID, User, Server, Resource, Info),
    %% replace old session if
    MaybeReplaceSession =
        lists:filtermap(fun(#session{sid = {_, ReplacePId}}) ->
                                ReplacePId /= NewPId
                        end, MaybeSession),
    FromInfo = [{sid,SID},{usr,{User,Server,Resource}},{info,Info}],
    maybe_replace_duplicate_session(MaybeReplaceSession, FromInfo),
    maybe_close_too_many_sessions(User, Server, get_all_sessions(User, Server)),
    %%
    Res.

close_session(SID, User, Server, Resource) ->
    maybe_spawn(get_the_other_session_module(), close_session, [SID, User, Server, Resource]),
    (get_session_module()):close_session(SID, User, Server, Resource).

get_session(User, Server, Resource) ->
    (get_session_module()):get_session(User, Server, Resource).

get_all_sessions(User, Server) ->
    (get_session_module()):get_all_sessions(User, Server).

get_client_version(#session{info = Info}) ->
    easemob_version:get_client_version(Info).
get_socket(#session{info = Info}) ->
    proplists:get_value(socket, Info, undefined).
get_user_ip(#session{info = Info}) ->
    proplists:get_value(ip, Info, {{0,0,0,0},0}).
get_resource(#session{usr = {_,_,R}}) ->
    R.

%% internal functions

%% User, Server is used for query configurations.
maybe_replace_duplicate_session(Sessions, FromInfo) when is_list(Sessions) ->
    [maybe_replace_duplicate_session(Session, FromInfo) || Session <- Sessions];
maybe_replace_duplicate_session(#session{} = Session, FromInfo) ->
    replace_session(Session, FromInfo);
maybe_replace_duplicate_session(_, _FromInfo) ->
    ok.

maybe_close_too_many_sessions(User, Server, {ok, Sessions}) ->
    MaxNumOfSession = get_max_num_of_sessions(User, Server),
    case length(Sessions) =< MaxNumOfSession of
        true ->
            ok;
        false ->
            SortedSessions = lists:sort(fun(A,B) -> A#session.sid > B#session.sid end, Sessions),
            ReplaceSessions = nthtail_safe(MaxNumOfSession, SortedSessions),
            MaxReplace = get_max_replace_session(),
            ChosedSessions = random_chose_sessions(ReplaceSessions, MaxReplace),
            lists:foreach(
              fun close_and_replace/1, ChosedSessions)
    end.

random_chose_sessions(Sessions, Max) ->
    SessionsRandom = utils:random_list(Sessions),
    lists:sublist(SessionsRandom, Max).

get_max_replace_session() ->
    application:get_env(message_store, max_replace_session, 3).

close_and_replace(Session) ->
    replace_session(Session),
    close_session(Session).

close_session(Session) ->
    {U, S, R} = Session#session.usr,
    close_session(Session#session.sid, U, S, R).

replace_session(Session, FromInfo) ->
    Info = Session#session.info,
    NewInfo = [{from, FromInfo}|Info],
    replace_session(Session#session{info = NewInfo}).
replace_session(Session) ->
    #session{sid={_, Pid}, usr=USR, info=Info} = Session,
    ?INFO_MSG("send replace session for ~s, from:~p,to:~p, to_session:~p",
              [jlib:jid_to_string(USR), proplists:get_value(from,Info), Pid, Session]),
    case Pid of
        {RealPid, msync} ->
            RealPid ! {replaced, Session};
        _ ->
            Pid ! {replaced, Session}
    end.

%% TODO, put it into list_utils

get_max_num_of_sessions(LUser, _Host) ->
    case app_config:is_multi_resource_enabled(LUser) of
        true ->
            %% when multi resource is open,max user session is checked in
            %% fun easemob_resource:is_resource_enabled/2
            infinity;
        false ->
            1
    end.


%% exported for OM, keep it here
get_session_db_type() ->
    DBType = application:get_env(msync, session_db_type, mnesia),
    check_session_db_type(DBType).
set_session_db_type(mnesia) ->
    application:set_env(msync, session_db_type, mnesia);
set_session_db_type(redis) ->
    application:set_env(msync, session_db_type, redis).

check_session_db_type(mnesia) ->
    mnesia;
check_session_db_type(redis) ->
    redis;
check_session_db_type(DBType) ->
    ?ERROR_MSG("unknown session db type ~p, check application:get_env(ejabberd, session_db_type, mnesia)~n",[DBType]).

get_session_module() ->
    get_session_module(get_session_db_type()).

get_session_module(redis) ->
    easemob_session_redis;
get_session_module(mnesia) ->
    easemob_session_mnesia.

get_the_other_session_module() ->
    case application:get_env(msync, enable_session_db_hotswap, true) of
        true ->
            get_the_other_session_module(get_session_db_type());
        false ->
            undefined
    end.

get_the_other_session_module(redis) ->
    easemob_session_mnesia;
get_the_other_session_module(mnesia) ->
    easemob_session_redis.

maybe_spawn(easemob_session_redis, F, A) ->
    spawn(easemob_session_redis, F, A);
maybe_spawn(easemob_session_mnesia, F, A) ->
    spawn(easemob_session_mnesia, F, A);
maybe_spawn(_, _F, _A) ->
    maybe_spawn_ignore.




nthtail_safe(N,List) ->
    try lists:nthtail(N, List) of
        X -> X
    catch
        error:function_clause ->
            []
    end.
