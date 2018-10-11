%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(msync_web_api).
-export([app/2]).
-author("wcy123@gmail.com").
-include("pb_msync.hrl").

app(Req, [<<"easemob.com">>, Org, App, <<"sessions">>, Pattern]) ->
    AppKey = << Org/binary , "#", App/binary >>,
    Req:respond({200,
                 [{"Content-Type", "application/json"}],
                 jsx:encode(lists:sublist(msync_c2s_lib:search_sessions(AppKey, Pattern), 100))});
app(Req, [ Host, <<"close_session">>, Org, App, User, Resource]) ->
    AppKey = << Org/binary , "#", App/binary >>,
    JID = #'JID'{
             app_key = AppKey,
             name = User,
             domain = Host,
             client_resource = Resource
            },
    case msync_c2s_lib:get_pb_jid_prop(JID, socket) of
        {ok, Socket} ->
            msync_c2s_lib:maybe_close_session(Socket),
            ok = gen_tcp:close(Socket),
            Req:respond({200,
                         [{"Content-Type", "plain/text"}],
                         <<"ok">>});
        {many_found, [List]} ->
            Text = [ begin
                         msync_c2s_lib:maybe_close_session(Socket),
                         ok = gen_tcp:close(Socket),
                         io_lib:format("~p is closed, SID = ~p~n", [Socket, SID])
                     end ||
                [Socket, SID] <- List ],
            Req:respond({200,
                         [{"Content-Type", "plain/text"}],
                         erlang:iolist_to_binary(Text)});
        OtherWise ->
            Text = io_lib:format("cannot find resource. Value = ~p~n", [OtherWise]),
            Req:respond({200,
                         [{"Content-Type", "plain/text"}],
                         erlang:iolist_to_binary(Text)})
    end;

%%get metrics
app(Req, [<<"metrics">>]) ->
    Req:respond({200,
                [{"Content-Type", "plain/text"}],
                prometheus_text_format:format()});

app(Req, X) ->
    Req:respond({404,
                 [{"Content-Type", "plain/text"}],
                 erlang:iolist_to_binary(io_lib:format("not defined: ~p~n",[X]))}).
