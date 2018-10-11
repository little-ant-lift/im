-module(msync_user).
-author("Eric Liang <eric@easemob.com>").
-behaviour(supervisor).

-export([start_link/0, start_link/2, start_link/3, init/1,
		 auth/2,
		 is_existent/1,
		 is_bypassed/0,
		 auth_opt/1, auth_opt/2,
		 proc_name/1]).
-include("logger.hrl").
-include("elib.hrl").
-include("gen-erl/user_types.hrl").

-define(DEFAULT_POOL_SIZE, 10).
-define(DEFAULT_SERVER, <<"localhost:9147">>).
-record(auth_opt, { key :: atom(), value :: any()}).

start_link() ->
	start_link(?DEFAULT_POOL_SIZE, ?DEFAULT_SERVER).

start_link(PoolSize, Servers) ->
	start_link(PoolSize, Servers, false).

start_link(PoolSize, Servers, Bypassed) when is_binary(Servers)->
	F = fun(S) ->
				[Server, Port]=binary:split(S, <<":">>),
				{binary_to_list(Server), binary_to_integer(Port)}
		end,
	Servers1 = [ F(S) || S <- binary:split(Servers, <<",">>, [global])],
	start_link(PoolSize, Servers1, Bypassed);

start_link(PoolSize, Servers, Bypassed) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE,
						  [PoolSize, Servers, Bypassed]).

init([PoolSize, Servers, Bypassed]) ->
	catch ets:new(auth_opts, [named_table, public, {keypos, #auth_opt.key}]),
	auth_opt(pool_size, PoolSize),
	auth_opt(servers, Servers),
	auth_opt(bypassed, Bypassed),
	Children = lists:map(
				 fun(N) ->
						 Name = proc_name(N),
						 { Name,
						   {user_thrift_client, start_link, [Name, Servers]},
						   permanent,
						   brutal_kill,
						   worker,
						   [user_thrift_client] }
				 end, lists:seq(0, PoolSize -1 )),
    ?INFO_MSG("user config: pool_size = ~p, servers = ~p, bypassed = ~p~nChildren=~p~n",
              [PoolSize, Servers, Bypassed,Children]),
	{ok, {{one_for_one, 1, 5}, Children}}.

auth(Eid, Password) ->
	Proc = get_random_process(),
	UserAuth = #'UserAuth'{eid = to_EID(Eid), password = Password},
	user_thrift_client:login(Proc, UserAuth, is_bypassed()).

is_existent(Eid) ->
	Proc = get_random_process(),
	user_thrift_client:is_exist(Proc, to_EID(Eid), is_bypassed()).

%% From MSync eid to user thrift EID
to_EID(#eid{app_key = AppKey, user = User}) ->
	#'EID'{tenant_id = AppKey, user_id = User}.

proc_name(Integer) ->
    list_to_atom(lists:flatten(io_lib:format("~p_~p", [?MODULE,Integer]))).

get_random_process() ->
    proc_name(random_instance(auth_opt(pool_size))).

random_instance(N) ->
    {A1, A2, A3} = os:timestamp(),
    random:seed(A1, A2, A3),
	random:uniform(N) - 1.

is_bypassed() ->
	auth_opt(bypassed).

auth_opt(Key) ->
	case ets:lookup(auth_opts, Key) of
		[] ->
			undefined;
		[#auth_opt{value=V}] ->
			V
	end.

auth_opt(Key, Value) ->
	ets:insert(auth_opts, #auth_opt{key = Key, value = Value}).
