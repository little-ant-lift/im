%% tcp client
-module(tcp_client).
-export([start/2,send_data/2,close/1,loop_start/3]).

loop_start(Ip,Port,Num)->
    case start(Ip,Port)of
        system_limit -> io:format("");
        _-> loop_start(Ip,Port,Num+1)
    end.

start(Ip,Port)->
    try
        %%case gen_tcp:connect("127.0.0.1",Port, [binary,{packet,raw},{active,true},{reuseaddr,true}])of
        case gen_tcp:connect(Ip, Port, [binary,{packet,raw},{active,false},{reuseaddr,true}])of
            {ok,Socket}->Socket;
            {error,Reason}-> {error,Reason}
        end
    catch
        throw:T->T;
        exit:R->R;
        error:E->E
    end.

send_data(Socket,Data)when is_list(Data)orelse is_binary(Data)->
    gen_tcp:send(Socket,Data),
    receive
        {tcp,Socket,Bin}->
            io:format("recv~p~n",[Bin]);
        {tcp_closed,Socket}->
            io:format("receive server don't accept connection!~n")
    end.

close(Socket)when is_port(Socket)->
    gen_tcp:close(Socket).
