%%%-------------------------------------------------------------------
%%% @author zhangchao <zhangchao@easemob.com>
%%% @copyright (C) 2017, zhangchao
%%% @doc
%%%
%%% @end
%%% Created : 26 Jun 2017 by zhangchao <zhangchao@easemob.com>
%%%-------------------------------------------------------------------
-module(msync_multi_devices_muc).

%% API
-export([make_muc_meta/5]).

-include("pb_mucbody.hrl").
-include("logger.hrl").

%%%===================================================================
%%% API
%%%===================================================================
make_muc_meta(From, To, MUCJID, Op, Reason) ->
    ?DEBUG("Paras:~p ~n", [{From, To, MUCJID, Op, Reason}]),
    Payload = make_muc_body(From, To, MUCJID, Op, 'OK', <<>>, Reason),
    msync_msg:new_meta(MUCJID, From, 'MUC', Payload).

make_muc_body(From, To, MUCJID, Op, ErrorCode, ErrorDesc, Reason) ->
    DefaultMUCDomainName = <<"conference.easemob.com">>,
    #'MUCBody'{
       muc_id = MUCJID#'JID'{domain = DefaultMUCDomainName},
       from = From,
       to = To,
       operation = Op,
       reason = Reason,
       status = #'MUCBody.Status'{
                   error_code = ErrorCode,
                   description = ErrorDesc
                  }
      }.

%%%===================================================================
%%% Internal functions
%%%===================================================================
