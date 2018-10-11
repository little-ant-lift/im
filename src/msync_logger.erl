-module(msync_logger).
-export([set/1, status/0]).

set(LogLevel) when is_integer(LogLevel) ->
    LagerLogLevel = case LogLevel of
                        0 -> none;
                        1 -> critical;
                        2 -> error;
                        3 -> warning;
                        4 -> info;
                        5 -> debug
                    end,
    case lager:get_loglevel(lager_console_backend) of
        LagerLogLevel ->
            ok;
        _ ->
            %% ConsoleLog = get_log_path(),
            lists:foreach(
              fun({lager_file_backend, _File} = H)  ->
                      lager:set_loglevel(H, LagerLogLevel);
                 (lager_console_backend = H) ->
                      lager:set_loglevel(H, LagerLogLevel);
				 ({lager_flume_backend, _FlumeId} = H) ->
                      lager:set_loglevel(H, LagerLogLevel);
                 (_) ->
                      ok
              end, gen_event:which_handlers(lager_event))
    end,
    {module, lager}.


status() ->
    lager:status().
