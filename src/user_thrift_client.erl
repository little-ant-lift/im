-module(user_thrift_client).
-author('eric.l.2046@gmail.com').
-behaviour(gen_server).

-export([start_link/2,
		 stop/1,
		 set_server/2,
		 login/3,
		 is_exist/3,
		 register_user/3,
		 remove/3]).

-export([init/1,
		handle_call/3,
		handle_cast/2,
		code_change/3,
		handle_info/2,
		terminate/2]).

-include("gen-erl/user_service_thrift.hrl").
-include("gen-erl/common_types.hrl").
-include("logger.hrl").

-record(state, { servers, workers, last_connect_time }).

-define(NET_TIMEOUT, 1000). %% in milliseconds
-define(RECONNECT_INTERVAL, 10). %% in microseconds.

%% API

start_link(Name, ThriftServers) ->
	gen_server:start({local, Name}, ?MODULE, [ThriftServers], []).

stop(Name) ->
	gen_server:cast(Name, stop).

set_server(Name, Servers) ->
	gen_server:cast(Name, {set_server, Servers}).

login(Name, User, Bypassed) when is_record(User, 'UserAuth') ->
	Req = {login, User},
	safe_request(Name, Req, Bypassed).

is_exist(Name, Eid, Bypassed) when is_record(Eid, 'EID')->
	Req = {isExist, Eid},
	safe_request(Name, Req, Bypassed).

register_user(Name, User, Bypassed) when is_record(User, 'UserAuth')->
	Req = {registerUser, User},
	safe_request(Name, Req, Bypassed).

remove(Name, Eid, Bypassed) when is_record(Eid, 'EID')->
	Req = {remove, Eid},
	safe_request(Name, Req, Bypassed).

safe_request(_Name, Req, true) ->
	Ret = default(Req),
	?INFO_MSG("Thrift bypass mode, return ~p for request ~p ~n", [Ret, Req]),
	Ret;
safe_request(Name, {Call, Args} = Req, _Bypassed) ->
	Client = case (catch gen_server:call(Name, get_worker, ?NET_TIMEOUT)) of
				 {ok, Client1} ->
					 Client1;
				 {no_worker, {Host, Port}} ->
					 case reconnect(Host, Port) of
						 {error, Reason} ->
							 ?WARNING_MSG("Thrift client connect error ~p to server ~p:~p~n ",
										  [Reason, Host, Port]),
							 undefined;
						 {Client2, _Now} ->
							 ?DEBUG("New thrift client for myself to server ~p:~p~n ",
									[Host, Port]),
							 Client2
					 end;
				 Error ->
					 ?WARNING_MSG("Error on request: ~p due to reason: ~p ~n", [Req, Error]),
					 undefined
			 end,
	case Client of
		undefined ->
			?WARNING_MSG("No thrift client available, return default value to ~p ~n", [Req]),
			default(Req);
		_ ->
			{Client3, Res} =  (catch thrift_client:call(Client, Call, [Args])),
			{Ret, Client4} = check_result_and_update_client(Req, Res, Client3),
			gen_server:cast(Name, {add_worker, Client4}),
			Ret
	end.

check_result_and_update_client(Req, Res, Client) ->
	?DEBUG("extauth rpc request: ~p received data response:~n~p", [Req, Res]),
	case Res of
		{ok, B} when is_boolean(B) ->
			{B, Client};
		{ok, #'UserInfo'{ auth = UserAuth } } ->
			{UserAuth#'UserAuth'.token /= undefined , Client};
		{exception, EE = #'EasemobException'{ code = EECode } } ->
			?DEBUG("Exception got from thrift server, ~p~n ", [EE]),
			%% error codes [400,500) are due to client problems, default false
			B1 = (EECode < 400 orelse EECode >= 500),
			{B1, Client};
		{badmatch, {error, TcpError}} ->
			%% To work with thrift lib's fast failure strategy, we catch tcp error here
			?WARNING_MSG("Tcp ~p error on thrift client ~p reason: ~p ~n",
						 [Req, Client, TcpError]),
			{default(Req), undefined};
		{error, Reason} ->
			?WARNING_MSG("~p error on thrift client ~p reason: ~p ~n",
						 [Req, Client, Reason]),
			%% close it for sanity
			thrift_client:close(Client),
			{default(Req), undefined};
		_ ->
			?CRITICAL_MSG("Unknown monster comes from thrift server, ~p ~n", [Res]),
			{default(Req), undefined}
	end.

%% Internal

init([ThriftServers]) ->
	erlang:process_flag(trap_exit, true),
	lists:foreach(fun(_) ->
						  gen_server:cast(self(), add_worker)
				  end, lists:seq(0, 9)),

	{ok, #state{ servers = filter_valid_server(ThriftServers),
				 workers = queue:new(),
				 last_connect_time = os:timestamp() }}.

handle_call(get_worker, _From, #state{servers = Servers,
									  workers = Workers} = State) ->
	{Host, Port} = random_server(Servers),
	case queue:out(Workers) of
		{empty, _} ->
			{reply, {no_worker, {Host, Port}}, State};
		{{value, Worker}, Workers1} ->
			{reply, {ok, Worker}, State#state{workers = Workers1}}
	end;

handle_call(Req, From, State) ->
	?WARNING_MSG("extauth rpc unknown method: ~p from ~p ~n", [Req, From]),
    {reply, {error, unknown_call}, State}.

handle_cast({set_server, Servers}, State) ->
	NewServers = filter_valid_server(Servers),
	case length(NewServers) > 0 of
		true ->
			?WARNING_MSG("Thrift server changes to ~p~n", [NewServers]),
			{noreply, State#state{servers = NewServers}};
		_ ->
			?WARNING_MSG("Invalid thrift servers: ~p~n", [Servers]),
			{noreply, State}
	end;

%% add worker without rate limit
handle_cast(add_worker , #state{servers = Servers} = State) ->
	{Host, Port} = random_server(Servers),
	case reconnect(Host, Port) of
		{error, Reason} ->
			?WARNING_MSG("Thrift client connect error ~p~n ", [Reason]),
			{noreply, State};
		{Client, Now} ->
			handle_cast({add_worker, Client}, State#state{last_connect_time = Now})
	end;

handle_cast({add_worker, undefined} , #state{ servers = Servers,
											  last_connect_time = Last} = State) ->
	{Host, Port} = random_server(Servers),
	case reconnect(Host, Port, Last) of
		{error, Reason} ->
			?WARNING_MSG("Thrift client connect error ~p~n ", [Reason]),
			{noreply, State};
		{Client, Now} ->
			handle_cast({add_worker, Client}, State#state{last_connect_time = Now})
	end;


handle_cast({add_worker, Client}, #state{workers = Workers} = State) ->
	Workers1 = queue:in(Client, Workers),
	{noreply, State#state{workers = Workers1}};

handle_cast(stop, State) ->
    {stop, normal, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

filter_valid_server(Servers) ->
	[ S || {Host, Port} = S <-Servers, is_list(Host) andalso is_integer(Port)].

random_server(Servers) ->
    {A1, A2, A3} = os:timestamp(),
    random:seed(A1, A2, A3),
	N = random:uniform(length(Servers)),
    lists:nth(N, Servers).

reconnect(Host, Port, Last) ->
	%% auto-connect should be controled by connect interval, to prevent
	%% pushing too much pressure to server
	case timer:now_diff(os:timestamp(), Last) >= ?RECONNECT_INTERVAL of
		true ->
			reconnect(Host, Port);
		_ ->
			{error, rate_limit}
	end.

reconnect(Host, Port) ->
	case catch  thrift_client_util:new(Host, Port, user_service_thrift,
									   [{framed, true},
										{connect_timeout, ?NET_TIMEOUT},
										{recv_timeout, ?NET_TIMEOUT},
										{sockopts, [{keepalive, true}]}]) of
		{ok, Client} ->
			?DEBUG("User thrift connect to server ~p:~p successfully.~n", [Host, Port]),
			{Client, os:timestamp()};
		Error ->
			?WARNING_MSG("User thrift can't connect to server ~p:~p due to error: ~p~n",
						 [Host, Port, Error]),
			{error, connect_error}
	end.

default({login,_}) ->
	true;
default(_Req) ->
	false.
