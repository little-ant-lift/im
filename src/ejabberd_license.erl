%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmaill.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc

%%%%
%%  When IM server is started, it cannot accept a new c2s connection
%%  until the license is activated. A new parameter `licence_file` is
%%  the file name of the license file. If the filename is a relative
%%  file name, it is relative to the current working directory of the
%%  ejabberd process. If you are not sure about the current working
%%  directory, please use an absolute file name. The default license
%%  file name is "~/.ssh/easemob.pub". If you forget the license file,
%%  please sign in http://easemob.com, and download a new one.
%%
%%%%

%%%

%%% @end
%%% Created :  2 Sep 2015 by WangChunye <>
%%%-------------------------------------------------------------------
-module(ejabberd_license).
-include("logger.hrl").
-behaviour(gen_server).
-ifndef(INITIAL_LICENSE_TIME).
-define(INITIAL_LICENSE_TIME, {{1996,11,6},{14,18,43}}).
-endif.
%% API
-export([start_link/0, is_active/0, get_expire_date/0, check_activation/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {expire_datetime_utc = calendar:universal_time()}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc check whether the license is active.
-spec is_active() -> boolean().
is_active() ->
    gen_server:call(?SERVER, is_active).

%% @doc return a string represent the expire date time
-spec get_expire_date() -> string().
get_expire_date() ->
    gen_server:call(?SERVER, get_expire_date).

%% @doc check if activation message is valid. If it is, license is
%% activated and new c2s connection request will be accepted.
-spec check_activation(binary()) -> none().
check_activation(ActivationMessage) ->
    gen_server:multi_call(?SERVER, {activate, ActivationMessage}).
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    State = #state{  expire_datetime_utc = ?INITIAL_LICENSE_TIME},
    ?INFO_MSG("Initiallly, your license will expire at ~p~n",
              [get_expire_date_1(State)]),
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(is_active, _From, State) ->
    ExpireDate = State#state.expire_datetime_utc,
    Timeout = expire_in_seconds(ExpireDate),
    Reply = Timeout > 0,
    {reply, Reply, State};
handle_call({activate, ActivationMessage_b64}, _From, State) ->
    {Reply, NewState}  = do_activate(ActivationMessage_b64, State),
    {reply, Reply, NewState};
handle_call(get_expire_date, _From, State) ->
    Reply = get_expire_date_1(State),
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(timeout, State) ->
    %% we don't need update the date time, to save when it is
    %% activated last time.
    ?ERROR_MSG("Sorry, your license is expired at ~s~n", [get_expire_date_1(State)]),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
do_activate(ActivationMessage_b64, State) ->
    PubKey = ejabberd_license_data:data(),
    {EncrypedDesKey, EncrypedActivationMessage} = binary_to_term(base64:decode(ActivationMessage_b64)),
    DesKey = public_key:decrypt_public(EncrypedDesKey, PubKey),
    Msg = block_decrypt(DesKey, EncrypedActivationMessage),
    {ExpireDate, Command} = calculate_expire_datetime(Msg),
    Timeout = expire_in_seconds(ExpireDate),
    NewState = State#state{expire_datetime_utc = ExpireDate},
    if Timeout > 0 ->
            ?INFO_MSG("Thank you. Your license extends to ~p~n",
                      [get_expire_date_1(NewState)]);
       true ->
            ?INFO_MSG("Bong! something wrong, license expired at ~p~n",
                      [get_expire_date_1(NewState)])
    end,
    Reply = execute(Command),
    {Reply, NewState}.

%% caluclate next time out value, return 0 if verification is failed
%% and it becomes inactive almost immediately.
calculate_expire_datetime(MsgBin) ->
    try %% in case of any error, crash, and ejabber_sup will restart it
        Msg = binary_to_term(MsgBin),
        {Data, CheckSum } = Msg,
        CheckSum = erlang:crc32(Data),
        {NewActiveDateTime, Command}  = binary_to_term(Data),
        {NewActiveDateTime, Command}
    catch
        error:ErrMsg ->
            ?ERROR_MSG("An invalid activation message is received: Reason ~p~n.",
                       [ErrMsg]),
            ErrMsg
    end.

expire_in_seconds({{Year,Month,Day}, {Hour,Minute,Second}} = DatetimeExpir) when
      is_integer(Year),
      is_integer(Month),
      is_integer(Day),
      is_integer(Hour),
      is_integer(Minute),
      is_integer(Second) ->
    DatetimeNow = calendar:now_to_datetime(erlang:timestamp()),
    Diff = datetime_sub_datetime(DatetimeExpir, DatetimeNow),
    max(Diff,0);
expire_in_seconds(_) ->
    0.

datetime_sub_datetime(Datetime1, Datetime2) ->
    calendar:datetime_to_gregorian_seconds(Datetime1)
        - calendar:datetime_to_gregorian_seconds(Datetime2).

get_expire_date_1(#state{expire_datetime_utc = D}) ->
    D.

execute(Command) ->
    try
        {ok, Tokens, _EndPos} = erl_scan:string(binary_to_list(Command)),
        {ok, Exprs} = erl_parse:parse_exprs(Tokens),
        erl_eval:exprs(Exprs, erl_eval:new_bindings())
    catch
        Class:Error ->
            [Class, Error, Command, erlang:get_stacktrace()]
    end.
block_decrypt(DesKey, EncrypedActivationMessage) ->
    {_NewState, ActivationMessage }
        = crypto:stream_decrypt(crypto:stream_init(rc4, DesKey),EncrypedActivationMessage),
    ActivationMessage.
