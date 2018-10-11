-module(elib).
-author("Eric Liang <eric@easemob.com>").

-include("elib.hrl").

-export([eid/1, eid/4, jid/1, to_string/1]).

eid(Jid) when is_record(Jid, jid) ->
	[H|T] = binary:split(Jid#jid.user, ?ES_USER),
	[AppKey, User] = case T of
						 [] ->
							 [<<>>, H];
						 [User1] ->
							 [H, User1]
					 end,
	eid(AppKey, User, Jid#jid.server, Jid#jid.resource);

eid(EidBin) when is_binary(EidBin) ->
	%% TODO: Maybe parse by myself, but not now considering security and efficiency.
	Jid = jlib:string_to_jid(EidBin),
	eid(Jid);

eid(EidStr) ->
	EidBin = iolist_to_binary(EidStr),
	eid(EidBin).

eid(AppKey, User, Server, Resource) ->
	#eid{ app_key = AppKey,
		  user = User,
		  server = Server,
		  resource = Resource
		}.

jid(Eid) when is_record(Eid, eid)->
	User = case Eid#eid.app_key of
			   <<>> ->
				   Eid#eid.user;
			   AppKey ->
				   User1 = Eid#eid.user,
				   <<AppKey/binary, ?ES_USER/binary, User1/binary>>
		   end,
	#jid{ user = User,
		  server = Eid#eid.server,
		  resource = Eid#eid.resource
	 }.

to_string(Eid) when is_record(Eid, eid)->
	jlib:jid_to_string(jid(Eid)).

%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

eid_test() ->
	stringprep:load_nif(),
	EidStr = <<"o#a_u@s.com/r">>,
	Eid = eid(EidStr),

	?assertEqual(Eid,
				 #eid{ app_key = <<"o#a">>,
					   user = <<"u">>,
					   server = <<"s.com">>,
					   resource = <<"r">>
					 }),

    ?assertEqual( EidStr,
				  to_string(Eid)).

jid_test() ->
	stringprep:load_nif(),
	EidStr = <<"u@s.com/r">>,
	Eid = eid(EidStr),

	?assertEqual(Eid,
				 #eid{ app_key = <<"">>,
					   user = <<"u">>,
					   server = <<"s.com">>,
					   resource = <<"r">>
					 }),

    ?assertEqual( EidStr,
				  to_string(Eid)).

-endif.
