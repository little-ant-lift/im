-ifndef(_common_types_included).
-define(_common_types_included, yeah).

-define(COMMON_STATUSCODE_UNKNOWN, 1).
-define(COMMON_STATUSCODE_OK, 200).
-define(COMMON_STATUSCODE_NOT_FOUND, 404).
-define(COMMON_STATUSCODE_NOT_AUTHORIZED, 401).
-define(COMMON_STATUSCODE_FAILED_AUTHENTICATE, 402).
-define(COMMON_STATUSCODE_BAD_REQUEST, 400).
-define(COMMON_STATUSCODE_SERVER_ERROR, 500).
-define(COMMON_STATUSCODE_TIMEOUT, 501).
-define(COMMON_STATUSCODE_UNKNOWN_HOST, 502).

%% struct 'EasemobException'

-record('EasemobException', {'code' :: integer(),
                             'reason' :: string() | binary()}).
-type 'EasemobException'() :: #'EasemobException'{}.

-endif.
