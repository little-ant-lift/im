-module(easemob_session_mnesia).
-export([open_session/5, close_session/4, get_all_sessions/2, get_session/3]).
%% O&M, for backward compatible
-export([get_session_db_type/0, set_session_db_type/1]).
-include("logger.hrl").
-include("easemob_session.hrl").

open_session(SID, User, Server, Resource, Info) ->
    Priority = 0, %% it must be zero, otherwise, the user is not presence
    set_session(SID, User, Server, Resource, Priority, Info).


close_session(_SID, User, Server, Resource) ->
    LUser = jlib:nodeprep(User),
    LServer = jlib:nameprep(Server),
    LResource = jlib:resourceprep(Resource),
    USR = {LUser, LServer, LResource},
    ejabberd_store:store_rpc(get_store_name(LUser), mnesia, activity,
                             [ejabberd_store:op_by_consistency(),
                              fun mnesia:delete/1,
                              [{session, USR}], mnesia_frag]).

get_session(User, Server, Resource) ->
	LUser = jlib:nodeprep(User),
    LServer = jlib:nameprep(Server),
    LResource = jlib:resourceprep(Resource),
    USR = {LUser, LServer, LResource},
	case ejabberd_store:store_rpc(
           get_store_name(LUser), mnesia, activity,
           [async_dirty, fun mnesia:read/1, [{session, USR}], mnesia_frag]) of
        %% todo: not good calling convention.
        [Session] ->
            {ok, Session};
        [] ->
            {error, not_found};
        Other ->
            {error, Other}
    end.
get_all_sessions(User, Server) ->
	LUser = jlib:nodeprep(User),
	LServer = jlib:nodeprep(Server),
    Sessions = dirty_select(get_store_name(LUser), session,
                            [{#session{sid = '$1', us = {LUser, LServer},
                                       _ = '_'},
                              [{'/=', as_partial_key, {{LUser, LServer}}}],
                              ['$_']}]),
    {ok, Sessions}.


set_session(SID, User, Server, Resource, Priority, Info) ->
    LUser = jlib:nodeprep(User),
    LServer = jlib:nameprep(Server),
    LResource = jlib:resourceprep(Resource),
    US = {LUser, LServer},
    USR = {LUser, LServer, LResource},
	Session = #session{sid = SID, usr = USR, us = US,
					   priority = Priority, info = Info},
	set_session(get_store_name(LUser), Session),
    {ok, Session}.

set_session(StoreName, #session{} = Session) ->
	ejabberd_store:store_rpc(StoreName, mnesia, activity,
							 [ejabberd_store:op_by_consistency(), fun mnesia:write/1,
							  [Session], mnesia_frag]).


-spec get_store_name(binary()) -> atom().
get_store_name(User) ->
	case app_config:is_sub_store_used(User) of
		true ->
			sub;
		_ ->
			all
	end.


%%% Mnesia tables operations

%% dirty_index_read(Tab, Key, Pos) ->
%% 	lists:append(dirty_index_read(all, Tab, Key, Pos),
%% 				 dirty_index_read(sub, Tab, Key, Pos)).

%% dirty_index_read(StoreName, Tab, Key, Pos) ->
%% 	ejabberd_store:store_rpc(StoreName, mnesia, activity,
%%                              [async_dirty, fun mnesia:index_read/3, [Tab, Key, Pos], mnesia_frag]).

%% dirty_select(Tab, MatchSpec) ->
%% 	lists:append(dirty_select(all, Tab, MatchSpec),
%% 				 dirty_select(sub, Tab, MatchSpec)).

dirty_select(StoreName, Tab, MatchSpec) ->
	ejabberd_store:store_rpc(StoreName, mnesia, activity,
							 [async_dirty, fun mnesia:select/2,
							  [Tab, MatchSpec], mnesia_frag]).




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
