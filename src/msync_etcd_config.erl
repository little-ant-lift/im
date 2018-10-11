
-module(msync_etcd_config).

-include("logger.hrl").

-export([ read_configure_from_etcd/0
        , config_watch_key/0
        , set_env_and_backup_file_basedon_etcd/1
        , config_recover_from_backup_file/0
        , config_local_migrate_etcd/0
        , enable_etcd_config/0
        , disable_etcd_config/0
        ]).

read_configure_from_etcd() ->
    case application:get_env(etcdc, enable_etcd_config) of
        {ok, true} ->
            EtcdConfigPrefx = get_etcd_config_prefix(),
            case msync_etcd_client:etcdc_get(EtcdConfigPrefx, [recursive]) of
                Res when erlang:is_map(Res) ->
                    set_env_and_backup_file_basedon_etcd(Res),
                    ok;
                {error, not_found} ->
                    ok;
                {error, Reason} ->
                    ?WARNING_MSG("read_configure_from_etcd "
                                 "etcdc get error ~p~n", [Reason]),
                    config_recover_from_backup_file()
            end;
        _ ->
            ok
    end.

config_watch_key() ->
    case application:get_env(etcdc, enable_etcd_config) of
        {ok, true} ->
            msync_etcd_client:config_watch_key(get_etcd_config_prefix());
        _ ->
            ok
    end.

set_env_and_backup_file_basedon_etcd(EtcdConfigInfo)
  when erlang:is_map(EtcdConfigInfo) ->
    EtcdConfig = maps:get(<<"nodes">>,
                          maps:get(<<"node">>, EtcdConfigInfo, #{}), []),
    AppList =
        [begin
            XKey = maps:get(<<"key">>, X),
            AppName = binary_to_atom(filename:basename(XKey), latin1),
            ok = load_application(AppName),
            parse_and_set_par_value(maps:get(<<"nodes">>, X, []), AppName),
            AppName
         end || X <- EtcdConfig],
    backup_file_basedon_etcd(AppList),
    ok;
set_env_and_backup_file_basedon_etcd({watch,
                                      #{<<"action">> := <<"set">>} =
                                        EtcdConfigAltera}) ->
    #{<<"key">> := Key, <<"value">> := Content} =
        maps:get(<<"node">>, EtcdConfigAltera),
    Par = binary_to_atom(filename:basename(Key), latin1),
    AppName = binary_to_atom(filename:basename(filename:dirname(Key)), latin1),
    ok = load_application(AppName),
    case parse_etcd_string(binary_to_list(Content)) of
        undefined ->
            ?WARNING_MSG("parse_etcd_string error, content ~p", [Content]),
            ignore;
        Value ->
            set_env(AppName, Par, Value)
    end,
    backup_file_basedon_etcd([AppName]),
    ok;
set_env_and_backup_file_basedon_etcd({watch, EtcdConfigAltera}) ->
    ?WARNING_MSG("etcd watch wanring, info : ~p~n", [EtcdConfigAltera]),
    ok.

config_recover_from_backup_file() ->
    AppList = application:get_env(etcdc, etcd_config_enable_applist, []),
    BackupFileDir = application:get_env(etcdc, etcd_config_backup_file_dir,
                                        "./back_dir"),
    config_recover_from_backup_file(AppList, BackupFileDir),
    ok.

config_local_migrate_etcd() ->
    AppList = application:get_env(etcdc, etcd_config_enable_applist, []),
    EtcdConfigPrefx = get_etcd_config_prefix(),
    [begin
        EtcdKeyApp = filename:join(EtcdConfigPrefx, atom_to_list(App)),
        config_local_migrate_etcd(get_all_env(App), EtcdKeyApp)
     end || App <- AppList],
    ok.

enable_etcd_config() ->
    ok = application:set_env(etcdc, enable_etcd_config, true),
    msync_etcd_client:config_watch_key(get_etcd_config_prefix()),
    ok.

disable_etcd_config() ->
    ok = application:set_env(etcdc, enable_etcd_config, false),
    msync_etcd_client:config_unwatch_key(get_etcd_config_prefix()),
    ok.

%%%%%%

get_etcd_config_prefix() ->
    {ok, Value} = application:get_env(etcdc, etcd_config_prefix),
    Value.

parse_and_set_par_value([], _) ->
    ok;
parse_and_set_par_value([#{<<"key">> := Par0,
                           <<"value">> := Value0} = Option | Tail],
                        AppName) ->
    Par = binary_to_atom(filename:basename(Par0), latin1),
    case parse_etcd_string(binary_to_list(Value0)) of
        undefined ->
            ?WARNING_MSG("parse_etcd_string error, content ~p", [Option]),
            ignore;
        Value ->
            set_env(AppName, Par, Value)
    end,
    parse_and_set_par_value(Tail, AppName);
parse_and_set_par_value([Other | Tail], AppName) ->
    ?WARNING_MSG("parse_and_set_par_value wanring, info : ~p~n", [Other]),
    parse_and_set_par_value(Tail, AppName).

backup_file_basedon_etcd([]) ->
    ok;
backup_file_basedon_etcd([App | Tail]) ->
    BackupFileDir = application:get_env(etcdc, etcd_config_backup_file_dir,
                                        "./back_dir"),
    BackupFileName = filename:join(BackupFileDir, atom_to_list(App)),
    Content = lists:flatten(io_lib:format("~p", [get_all_env(App)])),
    ok = filelib:ensure_dir(BackupFileName),
    ok = file:write_file(BackupFileName, [list_to_binary(Content)]),
    backup_file_basedon_etcd(Tail).

config_recover_from_backup_file([], _) ->
    ok;
config_recover_from_backup_file([App | Tail], BackupFileDir) ->
    AppFileName = filename:join(BackupFileDir, atom_to_list(App)),
    case file:read_file(AppFileName) of
        {ok, ContentBin} ->
            [set_env(App, Par, Value)
             || {Par, Value} <- parse_etcd_string(binary_to_list(ContentBin))];
        {error, enoent} ->
            ignore
    end,
    config_recover_from_backup_file(Tail, BackupFileDir).

config_local_migrate_etcd([], _) ->
    ok;
config_local_migrate_etcd([{Par, Value} | Tail], EtcdKeyApp) ->
    EtcdKeyAppPar = filename:join(EtcdKeyApp, atom_to_list(Par)),
    Content = lists:flatten(io_lib:format("~p", [Value])),
    msync_etcd_client:etcdc_set(EtcdKeyAppPar, Content),
    config_local_migrate_etcd(Tail, EtcdKeyApp).

parse_etcd_string(String) ->    
    case erl_scan:string(String ++ ".") of
        {ok, Tokens, _} ->
            case erl_parse:parse_term(Tokens) of
                {ok, Term} -> Term;
                _Err -> undefined
            end;
        _Error ->
            undefined
    end.

set_env(AppName, Par, Value) ->
    ok = application:set_env(AppName, Par, Value).

get_all_env(AppName) ->
    application:get_all_env(AppName).

load_application(App) ->
    case application:load(App) of
        ok ->
            ok;
        {error, {already_loaded, App}} ->
            ok
    end.
