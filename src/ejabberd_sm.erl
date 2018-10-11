-module(ejabberd_sm).
-export([open_session/5, close_session/4, get_session/1, get_session/3, user_resources/2, get_user_ip/3]).

-record(session, {usr, sid, us, priority, info}).

open_session(SID, User, Server, Resource, Info) ->
    Sessions = get_resource_sessions(User, Server, Resource),
    Priority = 0, %% it must be zero, otherwise, the user is not presence
    set_session(SID, User, Server, Resource, Priority, Info),

    %% change get unack msg to []
    %% UnAckList = get_unack_message_and_replace(Sessions),
    replace_session(Sessions),
    UnAckList = [],
    check_max_sessions(User, Server),
	UnAckList.

close_session(SID, User, Server, Resource) ->
    case get_session(User, Server, Resource) of
        [#session{info=I, sid = SID}] ->
            LUser = jlib:nodeprep(User),
            LServer = jlib:nameprep(Server),
            LResource = jlib:resourceprep(Resource),
            USR = {LUser, LServer, LResource},
            ejabberd_store:store_rpc(get_store_name(LUser), mnesia, activity,
                                     [ejabberd_store:op_by_consistency(),
                                      fun mnesia:delete/1,
                                      [{session, USR}], mnesia_frag]),
            I;
        _ -> []
    end.

user_resources(User, Server) ->
    Resources = get_user_resources(User, Server),
    lists:sort(Resources).

get_user_resources(User, Server) ->
	PriorityUSRs = get_usrs_with_priority(User, Server),
	lists:map(fun({_,{_,_,R}}) -> R end, PriorityUSRs).

get_resource_sessions(User, Server, Resource) ->
	Sessions = get_session(User, Server, Resource),
    Sessions.

get_session(User, Server, Resource) ->
	LUser = jlib:nodeprep(User),
    LServer = jlib:nameprep(Server),
    LResource = jlib:resourceprep(Resource),
    USR = {LUser, LServer, LResource},
	get_session(USR).

get_session({U,_,_} = USR) ->
	ejabberd_store:store_rpc(get_store_name(U), mnesia, activity,
                             [async_dirty, fun mnesia:read/1, [{session, USR}], mnesia_frag]).


set_session(SID, User, Server, Resource, Priority, Info) ->
    LUser = jlib:nodeprep(User),
    LServer = jlib:nameprep(Server),
    LResource = jlib:resourceprep(Resource),
    US = {LUser, LServer},
    USR = {LUser, LServer, LResource},
	Session = #session{sid = SID, usr = USR, us = US,
					   priority = Priority, info = Info},
	set_session(get_store_name(LUser), Session).

set_session(StoreName, #session{} = Session) ->
	ejabberd_store:store_rpc(StoreName, mnesia, activity,
							 [ejabberd_store:op_by_consistency(), fun mnesia:write/1,
							  [Session], mnesia_frag]).

replace_session([]) ->
	[];
replace_session([Session]) ->
    #session{sid={_, Pid} } = Session,
    Pid ! {replaced, Session}.


check_max_sessions(User, Server) ->
	LUser = jlib:nodeprep(User),
	LServer = jlib:nodeprep(Server),
    Sessions = dirty_select(get_store_name(LUser), session,
                            [{#session{sid = '$1', us = {LUser, LServer},
                                       _ = '_'},
                              [{'/=', as_partial_key, {{LUser, LServer}}}],
                              ['$_']}]),
    SIDs = lists:map(fun(#session{sid=SID}) -> SID end, Sessions),
    MaxSessions = get_max_user_sessions(LUser, LServer),
    if length(SIDs) =< MaxSessions -> ok;
       true ->
            {Index, {_, Pid}} = list_min(SIDs),
            Pid ! {replaced, lists:nth(Index, Sessions)}
    end.


get_usrs_with_priority(User, Server) ->
	LUser = jlib:nodeprep(User),
	LServer = jlib:nodeprep(Server),
    dirty_select(get_store_name(LUser), session,
				 [{#session{usr = '$1', us = {LUser, LServer},
							priority = '$2', _ = '_'},
				   [{'/=', as_partial_key, {{LUser, LServer}}}],
				   [{{'$2','$1'}}]}]).


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


get_max_user_sessions(_LUser, _Host) ->
    application:get_env(msync, max_user_sessions, 100).

get_user_ip(User, Server, Resource) ->
    case get_session(User, Server, Resource) of
        [] ->
            offline;
        Ss ->
            Session = lists:max(Ss),
            proplists:get_value(ip, Session#session.info)
    end.

list_min([]) ->
    {0, undefined};
list_min([H]) ->
    {1,H};
list_min([H|_T] = L) ->
    {_Index, MinIndex, MinValue} =
        lists:foldl(
          fun(E,{Index, MinIndex, Acc}) ->
                  case E <  Acc of
                      true -> { Index + 1, Index, E};
                      false  -> { Index + 1, MinIndex, Acc}
                  end
          end, {1, 1, H}, L),
    {MinIndex, MinValue}.
