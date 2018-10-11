-ifndef(_keyword_types_included).
-define(_keyword_types_included, yeah).

%% struct 'ResultMessage'

-record('ResultMessage', {'code' :: integer(),
                          'info' :: string() | binary(),
                          'words' = [] :: list()}).
-type 'ResultMessage'() :: #'ResultMessage'{}.

-endif.
