%%
% Eid abbreviation for Easemob ID, is formed like org#app_user@server/resource,
% and is compatible with Jid, the Jabberd ID for XMPP protocol.
%%

-include("jlib.hrl").

% Eid Seprators
-define(ES_APP, <<"#">>). 
-define(ES_USER, <<"_">>).
-define(ES_SERVER, <<"@">>).

-record(eid, { app_key = <<"">> :: binary(), %% aka org#app
			   user = <<"">> :: binary(),
			   server = <<"">> :: binary(),
			   resource = <<"">> :: binary()
			 }).
