-ifndef(_media_types_included).
-define(_media_types_included, yeah).

%% struct 'MediaException'

-record('MediaException', {'what' :: integer(),
                           'name' :: string() | binary(),
                           'why' :: string() | binary()}).
-type 'MediaException'() :: #'MediaException'{}.

%% struct 'Member'

-record('Member', {'userId' :: string() | binary(),
                   'conferenceId' :: string() | binary(),
                   'serverIp' :: string() | binary(),
                   'rcode' :: string() | binary(),
                   'serverPort' :: integer(),
                   'channelId' :: integer(),
                   'vchannelId' :: integer()}).
-type 'Member'() :: #'Member'{}.

-endif.
