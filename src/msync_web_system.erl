%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(msync_web_system).
-export([app/2]).
-author("wcy123@gmail.com").


app(Req, Path) ->
    case Path of
        "memory" ->
            memory(Req);
        _ ->
            Req:respond({404,
                         [{"Content-Type", "text/plain"}],
                         <<"not found">>})
    end.

memory(Req) ->
    Memory = erlang:memory(),
    Req:respond({200,
                 [{"Content-Type", "application/json"}],
                 jsx:encode(Memory)}).
