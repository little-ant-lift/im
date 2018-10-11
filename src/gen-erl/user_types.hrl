-ifndef(_user_types_included).
-define(_user_types_included, yeah).

%% struct 'EID'

-record('EID', {'tenant_id' :: string() | binary(),
                'user_id' :: string() | binary()}).
-type 'EID'() :: #'EID'{}.

%% struct 'AccessToken'

-record('AccessToken', {'token' :: string() | binary(),
                        'expires_in' :: integer()}).
-type 'AccessToken'() :: #'AccessToken'{}.

%% struct 'UserAuth'

-record('UserAuth', {'eid' :: 'EID'(),
                     'password' :: string() | binary(),
                     'token' :: 'AccessToken'()}).
-type 'UserAuth'() :: #'UserAuth'{}.

%% struct 'UserInfo'

-record('UserInfo', {'auth' :: 'UserAuth'(),
                     'properties' :: dict:dict()}).
-type 'UserInfo'() :: #'UserInfo'{}.

-endif.
