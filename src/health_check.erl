-module(health_check).
-export([start/2, stop/1,
         handle/4, check/0,
         check_and_post/0]).

-callback check() -> map().
-callback services() -> list().

-include("logger.hrl").

-define(SERVER, health_monitor).
-define(RESULTS_ETS, health_results).
-define(DEFAULT_HEALTH_SERVER, "http://localhost:8888/cgi-bin/health").

start(_Host, _Opts) ->
    ChildSpec =
        {?SERVER,
         {?SERVER, start_link, []},
         temporary,
         infinity,
         worker,
         [?SERVER]
        },
    supervisor:start_child(msync_sup, ChildSpec).

stop(_Host) ->
    supervisor:terminate_child(msync_sup, ?SERVER),
    supervisor:delete_child(msync_sup, ?SERVER).

handle(_M, R, _DR, _A)->
    Res = jsx:encode(check()),
    R:respond({200, [{"Content-Type", "application/json"}], binary_to_list(Res)++"\n"}).

get_health_server_url() ->
    {ok, HealthServer} = application:get_env(msync, health_server),
    Host = proplists:get_value(host, HealthServer, "localhost"),
    Port = proplists:get_value(port, HealthServer, "80"),
    Path = proplists:get_value(path, HealthServer, "/health"),
    URL = iolist_to_binary(["http://", Host,":", Port, Path]),
    binary_to_list(URL).

cluster_name() ->
    application:get_env(msync, cluster, ebs).

post_request(URL, Body)->
    Timeout = application:get_env(msync, httpc_timeout, 10000),
    HttpOptions = [{autoredirect, true}, {timeout, Timeout}],
    Options = [],
    BodyType = "application/json",
    case application:get_env(msync, http_proxy) of
        {ok, {Server, Port}} ->
            httpc:set_options([{proxy, {{Server, Port}, []}}]);
        _ ->
            ok
    end,
    try httpc:request(post, { URL, [], BodyType, Body}, HttpOptions,Options) of
        {ok, {{_HTTPVersion, 200 = _StatusCode, _ReasonPhrase} = _StatusLine,
              _Headers,
              _RetBody}} ->
            ok;
        _RetBody ->
            failed
    catch
        C:E ->
            ?ERROR_MSG("httpc:request error: ~p:~p~n", [C, E]),
            error
    end.

check_and_post() ->
    case check() of
        error -> error;
        Res ->
            try
                %io:format("~p~n", [R]),
                Services = health_check_utils:get_services(),
                lists:map(
                  fun(S) ->
                          #{S := R} = Res,
                          Body = jsx:encode(R),
                          URL = get_health_server_url(),
                          post_request(URL, Body)
                  end, Services)
            catch C:E ->
                      ?ERROR_MSG("health_check error ~p:~p", [C, E]),
                      error
            end
    end.

init_result() ->
    Services = health_check_utils:get_services(),
    Timestamp = health_check_utils:get_timestamp(),
    ID = health_check_utils:get_service_id(),
    lists:foldl(
      fun(S, Out) ->
              S1 = atom_to_binary(S, latin1),
              S2 = <<"im_", S1/binary>>,
              R = #{service => binary_to_atom(S2, latin1),
                    timestamp => Timestamp,
                    status => normal,
                    cluster => cluster_name(),
                    details => #{},
                    id => ID},
              Out#{S => R}
      end, #{}, Services).

check() ->
    try
        R = init_result(),
        do_check_all(R, sync)
    catch C:E ->
              ?ERROR_MSG("health_check error ~p:~p", [C, E]),
              error
    end.

check_service(MS, S) when is_list(MS) ->
    lists:member(S, MS);
check_service(Module, Services) when is_list(Services) ->
    MS = Module:services(),
    lists:any(fun(S1) -> lists:member(S1, MS) end, Services).

all_checks(Services) ->
    Checks = application:get_env(msync, all_checks, []),
    lists:filtermap(
      fun(C) ->
              case check_service(C, Services) of
                  true -> {true, C};
                  _ -> false
              end
      end, Checks).

all_services(Modules) ->
    lists:foldl(
      fun(M, O) ->
              Services = M:services(),
              O#{M => Services}
      end, #{}, Modules).

%get_results() ->
%    R = ets:tab2list(?RESULTS_ETS),
%    lists:foldl(fun({K, V}, Out) ->
%                        Out#{K => V}
%                end, #{}, R).
%
%save_result(K, V) ->
%    ets:insert(?RESULTS_ETS, {K, V}).
%
%do_check_all(async) ->
%    Checks = all_checks(),
%    lists:foreach(fun(C) ->
%                          spawn(fun() ->
%                                        R = check(C),
%                                        save_result(C, R)
%                                end)
%                  end, Checks),
%    get_results();

set_result(MS, M, R, Ss, Out) ->
    #{status := Status} = R,
    lists:foldl(
      fun(S, O) ->
              case lists:member(S, MS) of
                  true ->
                      #{S := Res} = O,
                      #{status := OldStatus, details := Details} = Res,
                      Res1 = case Status of
                                 ignore -> Res;
                                 normal -> Res#{details => Details#{M => normal}};
                                 _ ->
                                     NewStatus = health_check_utils:check_result(OldStatus, Status),
                                     Res#{status =>NewStatus, details => Details#{M => R}}
                             end,
                      O#{S => Res1};
                  _ -> O
              end
      end, Out, Ss).

do_check_all(Res, sync) ->
    Services = health_check_utils:get_services(),
    Checks = all_checks(Services),
    AllMS = all_services(Checks),
    lists:foldl(fun(M, O) ->
                        R = try
                                M:check()
                            catch
                                C:E ->
                                    #{status => fault,
                                      error => health_check_utils:format("~p~p", [C, E])}
                            end,
                        #{M := MS} = AllMS,
                        set_result(MS, M, R, Services, O)
                end, Res, Checks).
