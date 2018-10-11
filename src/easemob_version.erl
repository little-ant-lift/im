-module(easemob_version).
-export([to_binary/1,
         parse/1]).

-export([make_client_info/1,
         get_client_version/1]).

-export([test/0]).

-include("logger.hrl").

make_client_info({Os, Version}) ->
    [{client_version, {Os, parse(Version)}}].

get_client_version(Info) when is_list(Info) ->
    proplists:get_value(client_version, Info, undefined);
get_client_version(_) ->
    undefined.

to_binary(Version) when is_float(Version) ->
    to_binary(parse(Version));
to_binary({Maj, Mid, Min}) ->
    iolist_to_binary([integer_to_binary(Maj), ".",
                      integer_to_binary(Mid), ".",
                      integer_to_binary(Min)]);
to_binary(_) ->
    undefined.

parse(Version) ->
    try
        parse2(Version)
    catch
        Class:Error ->
            ?WARNING_MSG("abnormal version: ~p, exception ~p: ~p~n", [Version, Class, Error]),
            undefined
    end.

parse2(Version) when is_float(Version) ->
    Version0 = Version + 0.00000001,
    Maj = trunc(Version0),
    Version1 = (Version0 - Maj) * 10,
    Mid = trunc(Version1),
    Version2 = (Version1 - Mid) * 10,
    Min = trunc(Version2),
    {Maj, Mid, Min};
parse2([Maj, _, _] = Version) when is_binary(Maj) ->
    VL = lists:map(fun(V) ->
                           binary_to_integer(V)
                   end, Version),
    list_to_tuple(VL);
parse2([Maj, _, _] = Version) when is_integer(Maj)->
    list_to_tuple(Version);
parse2(Version) when is_binary(Version) ->
    VL = binary:split(Version, [<<".">>], [global]),
    parse2(VL);
parse2({_Maj, _Mid, _Min}=Version) ->
    Version;
parse2(_) ->
    undefined.

test() ->
    to_binary_test(),
    parse_test(),
    ok.

to_binary_test() ->
    <<"1.2.3">> = to_binary(1.23),
    <<"1.2.3">> = to_binary({1, 2, 3}).

parse_test() ->
    {1, 2, 3} = parse([<<"1">>, <<"2">>, <<"3">>]),
    {1, 2, 3} = parse([1, 2, 3]),
    {1, 2, 3} = parse(<<"1.2.3">>),
    {1, 2, 3} = parse({1, 2, 3}),
    undefined = parse([<<"1">>, <<"2">>, <<"3">>, <<"4">>]),
    undefined = parse([1, 2, 3, 4]),
    undefined = parse(<<"1.2.3.4">>),
    undefined = parse({1, 2, 3, 4}).
