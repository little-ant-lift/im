%% @author Mochi Media <dev@mochimedia.com>
%% @copyright 2010 Mochi Media <dev@mochimedia.com>

%% @doc Web server for msync.

-module(msync_web).
-author("Mochi Media <dev@mochimedia.com>").
-include("logger.hrl").

-include("msync_http.hrl").
-include("elib.hrl").
-include("pb_msync.hrl").

-export([start/1, stop/0, loop/2]).
-export([msync_to_json/1]).
-compile([export_all]).

-define(record_to_proplist(R),
		fun(Val) ->
				Fields = record_info(fields, R),
				[_Tag|Values] = tuple_to_list(Val),
				lists:zip(Fields, Values)
		end).

%% External API

start(Options) ->
    {DocRoot, Options1} = get_option(docroot, Options),
    ?INFO_MSG("WEB SERVER STARTED WITH OPTIONS ~p~n", [Options]),
    Loop = fun (Req) ->
                   ?MODULE:loop(Req, DocRoot)
           end,
    mochiweb_http:start([{name, ?MODULE}, {loop, Loop} | Options1]).

stop() ->
    mochiweb_http:stop(?MODULE).

loop(Req, DocRoot) ->
    try
        "/" ++ Path = Req:get(path),
        case Req:get(method) of
            Method when Method =:= 'GET'; Method =:= 'HEAD' ->
                case Path of
					"msync" ->
						Resp = msync_get(Req),
						case Resp of
							{ok, Unread} ->
								Req:respond({200,
											 [{"Content-Type", "application/json"}],
											 msync_to_json(Unread)});
							{error, Reason} ->
								Req:respond({404,
											 [{"Content-Type", "application/json"}],
											 Reason})
						end;
                    "system/" ++ Path2 ->
                        msync_web_system:app(Req,Path2);
					"api/" ++ Path2 ->
                        msync_web_api:app(Req,binary:split(list_to_binary(Path2), <<"/">>, [global]));
					_ ->
                        Req:serve_file(Path, DocRoot)
                end;
            'POST' ->
                case Path of
                    _ ->
                        Req:not_found()
                end;
            _ ->
                Req:respond({501, [], []})
        end
    catch
        Type:What ->
            Report = ["web request failed",
                      {path, Req:get(path)},
                      {type, Type}, {what, What},
                      {trace, erlang:get_stacktrace()}],
            error_logger:error_report(Report),
            Req:respond({500, [{"Content-Type", "text/plain"}],
                         "request failed, sorry\n"})
    end.

msync_to_json(Msg) ->
	Converter = ?record_to_proplist('MSync'),
	PropList = Converter(Msg),

	%%FIXME: payload might not be a record?
	PropList2 = lists:keyreplace(payload, 1, PropList, {payload, <<>>}),
	?DEBUG("MSYNC: convert ~p to ~p ~n",[Msg, PropList2]),
	jsx:encode(PropList2).

%% Internal API

get_option(Option, Options) ->
    {proplists:get_value(Option, Options), proplists:delete(Option, Options)}.

msync_get(Req) ->
	QueryStringData = Req:parse_qs(),
	H = proplists:get_value("h", QueryStringData, ""),
	MHeader = msync_http_header:decode(H),
	case MHeader#msync_http_header.command of
		?MSYNC_COMM_UNREAD ->
			JID = to_JID(MHeader#msync_http_header.guid),
			?DEBUG("MSYNC: get unread for ~p~n", [JID]),

			MSync = msync_msg:set_command(#'MSync'{}, dl, 'UNREAD'),
			{ok, process_unread:handle(undefined, MSync, JID)};
		Comm ->
			?WARNING_MSG("MSYNC: unsupported command with GET", [Comm]),
			{error, unsupported_command}
	end.

%%FIXME: to get rid of the bogged JID
to_JID(JidStr) ->
	Eid = elib:eid(JidStr),
	#'JID'{
	   app_key = Eid#eid.app_key,
	   name = Eid#eid.user,
	   domain = Eid#eid.server,
	   client_resource = Eid#eid.resource
	  }.

%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

you_should_write_a_test() ->
    ?assertEqual(
       "yes!",
       "yes!"),
    ok.

-endif.
