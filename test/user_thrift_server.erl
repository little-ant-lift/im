%%
%% The module is for user thrift server test, you can start it manually or
%% uncomment the boot line in ejabberd_auth_thrift:start().
%%

-module(user_thrift_server).
-author('eric.l.2046@gmail.com').

-export([start/1,
		 handle_function/2,
		 handle_error/2,
		 stop/1]).

-export([login/1,
		isExist/1,
		registerUser/1,
		remove/1]).

-include("../src/gen-erl/user_service_thrift.hrl").
-include("logger.hrl").

-define(NAME, ?MODULE).
-define(DEFAULT_DELAY_TIME, 900). %% in milliseconds
-define(DEFAULT_RECV_TIMEOUT, 60*60*1000).

login(User) when is_record(User, 'UserAuth') ->
	goodman("login", User),
	AccessToken = #'AccessToken'{ token = User#'UserAuth'.password },
	User1 = User#'UserAuth'{ token = AccessToken},
	#'UserInfo'{ auth = User1 }.

isExist(Eid) when is_record(Eid, 'EID')->
	goodman("is_exist", Eid, false).

registerUser(User) when is_record(User, 'UserAuth')->
	goodman("register_user", User),
	AccessToken = #'AccessToken'{ token = User#'UserAuth'.password },
	User1 = User#'UserAuth'{ token = AccessToken},
 	#'UserInfo'{ auth = User1 }.

remove(Eid) when is_record(Eid, 'EID')->
	goodman("remove", Eid).

goodman(CallName, Args) ->
	goodman(CallName, Args, true).

goodman(CallName, Args, Ret) ->
	?DEBUG("Thrift Server get call ~p with ~p ~n ", [CallName, Args]),
	timer:sleep(?DEFAULT_DELAY_TIME),
	Ret.

%% for thrift server

start(Port) ->
	%% how to link?
	timer:start(),
    Handler   = ?MODULE,
    thrift_socket_server:start([{handler, Handler},
                                {service, user_service_thrift},
                                {port, Port},
								{socket_opts, [{recv_timeout, ?DEFAULT_RECV_TIMEOUT}]},
								{framed, true},
                                {name, user_service_server}]).

stop(Server) ->
    thrift_socket_server:stop(Server).

handle_function(Function, Args) when is_atom(Function), is_tuple(Args) ->
    case apply(?MODULE, Function, tuple_to_list(Args)) of
        ok -> ok;
        Reply -> {reply, Reply}
    end.

handle_error(undefined, Reason) ->
	?INFO_MSG("Connnection problem in thrift server, reason: ~p ~n", [Reason]);
handle_error(Function, Reason) ->
	?ERROR_MSG("Error in thrift server, stub function ~p has problem ~p , stack: ~p~n ",
			  [Function, Reason, erlang:get_stacktrace()]).
