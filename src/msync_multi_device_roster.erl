%%%-------------------------------------------------------------------
%%% @author zhangchao <zhangchao@easemob.com>
%%% @copyright (C) 2017, zhangchao
%%% @doc
%%%
%%% @end
%%% Created : 26 Jun 2017 by zhangchao <zhangchao@easemob.com>
%%%-------------------------------------------------------------------
-module(msync_multi_device_roster).

%% API
-export([make_roster_meta/4]).

-include("pb_rosterbody.hrl").
-include("logger.hrl").

%%%===================================================================
%%% API
%%%===================================================================
make_roster_meta(Op, A, B, Version) ->
    Payload = #'RosterBody'{
                 operation = Op,
                 from = A,
                 to = [B],
                 roster_ver = Version
                },
    SystemQueue = B#'JID'{
                    app_key = undefined, name = undefined,
                    client_resource = undefined
                   },
    msync_msg:new_meta(SystemQueue, B, 'ROSTER', Payload).

%%%===================================================================
%%% Internal functions
%%%===================================================================
