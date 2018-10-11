%%%-------------------------------------------------------------------
%%% @author WangChunye <wcy123@gmail.com>
%%% @copyright (C) 2015, WangChunye
%%% @doc
%%%
%%% @end
%%% Created : 27 Sep 2015 by WangChunye <wcy123@gmail.com>
%%%-------------------------------------------------------------------
-module(process_provision).
-export([handle/3]).
-include("logger.hrl").
-include("pb_msync.hrl").

handle(#'MSync'{
          command = 'PROVISION',
          payload =
              #'Provision'{
                 compress_type = CompressType,
                 os_type = OsType,
                 version = Version
                }
         } = _Request,
       #'MSync'{
          command = 'PROVISION'
         } = Response, JID) ->
    ClinetVersion = {os_type_to_string(OsType), easemob_version:parse(Version)},
    case msync_c2s_lib:get_pb_jid_prop(JID,socket) of
        {ok, Socket} ->
            ?DEBUG("socket: ~p, client version: ~p", [Socket, Version]),
            set_version(Socket, ClinetVersion);
        {error, {many_found, Sessions}} ->
            set_version(Sessions, ClinetVersion);
        _ ->
            ?INFO_MSG("can not get socket of jid ~p", [JID]),
            ok
    end,
    msync_msg:set_status(
      Response#'MSync'{
        payload =
            #'Provision'{
               compress_type = CompressType,
               resource = JID#'JID'.client_resource
              }
       }, 'OK', undefined).

set_version(_, undefined) ->
    ok;
set_version([[_Sock, _]|_] = Sessions, Version) ->
    lists:foreach(fun([Socket, _]) ->
                          set_version(Socket, Version)
                  end, Sessions);
set_version(Socket, Version) when is_port(Socket) ->
    msync_c2s_lib:set_socket_prop(Socket, version, Version).

os_type_to_string('OS_ANDROID') ->
    <<"android">>;
os_type_to_string('OS_IOS') ->
    <<"ios">>;
os_type_to_string('OS_WIN') ->
    <<"win">>;
os_type_to_string('OS_LINUX') ->
    <<"linux">>;
os_type_to_string('OS_OSX') ->
    <<"osx">>;
os_type_to_string(_) ->
    undefined.
