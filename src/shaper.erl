%%%----------------------------------------------------------------------
%%% File    : shaper.erl
%%% Author  : Alexey Shchepin <alexey@process-one.net>
%%% Purpose : Functions to control connections traffic
%%% Created :  9 Feb 2003 by Alexey Shchepin <alexey@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2013   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(shaper).

-author('alexey@process-one.net').

-export([init/0, new/1, new1/1, new2/1, update/2, load_from_config/0]).


-include("logger.hrl").

-record(maxrate, {maxrate  = 0   :: integer(),
                  lastrate = 0.0 :: float(),
                  lasttime = 0   :: integer()}).
-record(avgrate, { avgrate         = 0.0   :: float(),
                   lasttime        = 0.0   :: float(),
                   lastsize        = 0.0   :: float()
       }).

%% ets:tab2list(shaper).
%% [{rest,1000},
%%  {fast,50000},
%%  {normal,1000}]

init() ->
    shaper = ets:new(shaper, [named_table, public]),
    ok = load_from_config(),
    ?INFO_MSG("shapper is started",[]),
    ok.

-spec load_from_config() -> ok | {error, any()}.

load_from_config() ->
    {ok, ShaperConfig} = application:get_env(msync,shaper),
    lists:foreach(
      fun({K,V}) ->
              true = ets:insert(shaper,{K,V})
      end, ShaperConfig),
    ok.



new(none) ->
    none;
new(Name) ->
    MaxRate = case ets:lookup(shaper, Name) of
                  [{Name, R}] ->
                      R;
                  [] ->
                      ?WARNING_MSG("Attempt to initialize an "
                                   "unspecified shaper '~s'", [Name]),
                      none
              end,
    new1(MaxRate).


new1(none) -> none;
new1(MaxRate) ->
    #maxrate{maxrate = MaxRate, lastrate = 0.0,
             %% initially 1second budget, 1000000.
             lasttime = now_to_usec(os:timestamp()) - 1000000}.

new2(none) -> none;
new2(AvgRate) ->
    #avgrate{avgrate = AvgRate,
             lasttime = 0,
             lastsize = 0}.
update(none, _Size) -> {none, 0};
update(#maxrate{} = State, Size) ->
    MinInterv = 1000 * Size /
		  (2 * State#maxrate.maxrate - State#maxrate.lastrate),
    Interv = (now_to_usec(os:timestamp()) - State#maxrate.lasttime) /
	       1000,
    ?DEBUG("State: ~p, Size=~p~nM=~p, I=~p~n",
	   [State, Size, MinInterv, Interv]),
    Pause = if MinInterv > Interv ->
		   1 + trunc(MinInterv - Interv);
	       true -> 0
	    end,
    NextNow = now_to_usec(os:timestamp()) + Pause * 1000,
    {State#maxrate{lastrate =
		       (State#maxrate.lastrate +
			  1000000 * Size / (NextNow - State#maxrate.lasttime))
			 / 2,
		   lasttime = NextNow},
     Pause};
update(#avgrate{} = State, Size) ->
    Now = p1_time_compat:system_time(micro_seconds),
    MinInterv = 1000 * (State#avgrate.lastsize + Size) / State#avgrate.avgrate,
    Interv = (Now - State#avgrate.lasttime) / 1000,
    case Interv > 2000 orelse Interv < -2000 of
        true ->
            {State#avgrate{lasttime=Now, lastsize=Size}, 0};
        false ->
            Pause = if
                        MinInterv - Interv >= 1 ->
                            trunc(MinInterv - Interv);
                        true ->
                            0
                    end,
            NextNow = Now + Pause * 1000,
            ?DEBUG("State: ~p, Size=~p~nM=~p, I=~p,P=~p~n",
                   [State, Size, MinInterv, Interv, Pause]),
            NewState =
                if
                    NextNow > State#avgrate.lasttime + 1000000 ->
                        State#avgrate{
                          lasttime = (State#avgrate.lasttime + NextNow) / 2,
                          lastsize = (State#avgrate.lastsize + Size) / 2
                         };
                    true ->
                        State#avgrate{
                          lastsize = State#avgrate.lastsize + Size
                         }
                end,
            {NewState, Pause}
    end.

now_to_usec({MSec, Sec, USec}) ->
    (MSec * 1000000 + Sec) * 1000000 + USec.
