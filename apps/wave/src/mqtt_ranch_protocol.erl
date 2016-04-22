%%
%%    Wave - MQTT Broker
%%    Copyright (C) 2014-2016 - Guillaume Bour
%%
%%    This program is free software: you can redistribute it and/or modify
%%    it under the terms of the GNU Affero General Public License as published
%%    by the Free Software Foundation, version 3 of the License.
%%
%%    This program is distributed in the hope that it will be useful,
%%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%    GNU Affero General Public License for more details.
%%
%%    You should have received a copy of the GNU Affero General Public License
%%    along with this program.  If not, see <http://www.gnu.org/licenses/>.

-module(mqtt_ranch_protocol).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(ranch_protocol).

-export([start_link/4]).
-export([init/4]).

-export([ping/2, crlfping/2, send/3, close/2]).

-include("mqtt_msg.hrl").

-type ranch_socket()    :: inet:socket()|ssl:sslsocket().
-type ranch_transport() :: ranch_tcp|ranch_ssl.
-type transport()       :: {Module::module(), RanchTransport::ranch_transport(), RanchSocket::ranch_socket()}.


start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

-spec init(Ref::ranch:ref(), Socket::ranch_socket(), Transport::ranch_transport(), Opts::any()) -> ok.
init(Ref, Socket, Transport, _Opts = []) ->
    ok = ranch:accept_ack(Ref),

    {ok, {Ip,Port}} = peername(Transport, Socket),
    %TODO: use binary fmt instead
    % ie: tcp:127.0.0.1:55435
    Addr = string:join([wave_utils:str(Transport:name()), inet_parse:ntoa(Ip), wave_utils:str(Port)], ":"),

    {ok, Session} = mqtt_session:start_link({?MODULE, Transport, Socket}, [{addr, Addr}]),
    lager:debug("fsm= ~p (~p : ~p) from ~p", [Session, Transport, Socket, Addr]),
    loop(Socket, Transport, Session, <<"">>, 0).

-spec loop(ranch_socket(), ranch_transport(), Session::pid(), binary(), integer()) -> ok.
loop(Socket, Transport, Session, Buffer, Length) ->
    %TODO: do not use *infinity* timeout (handle incorrectly closed sockets)
    %      we can use PINGS to check socket state
    case Transport:recv(Socket, Length, infinity) of %5000) of
        {ok, Data} ->
            case route(Socket, Transport, Session, <<Buffer/binary, Data/binary>>) of
                {extend, Extend, Rest} ->
                    loop(Socket, Transport, Session, Rest, Extend);
                continue ->
                    loop(Socket, Transport, Session, <<"">>, 0);
                _ ->
                    stop
            end;

        {error, timeout} ->
            lager:notice("socket timeout. Sending ping"),
            Transport:send(Socket, mqtt_msg:encode(#mqtt_msg{type='PINGREQ'})),
            loop(Socket, Transport, Session, Buffer, Length);

        % socket closed by peer
        {error, closed} ->
            lager:debug("~p: err:closed", [Socket]),
            mqtt_session:disconnect(Session, peer_sock_closed),
            ok;

        % TCP keepalive timeout
        {error, etimedout} ->
            lager:debug("~p: err:tcp keepalive timeout", [Socket]),
            mqtt_session:disconnect(Session, peer_tcp_ka_timeout),
            ok;

        Err ->
            lager:debug("~p: err ~p. closing socket", [Socket, Err]),
            ok = Transport:close(Socket)
    end,

    Transport:close(Socket),
    ok.


-spec route(ranch_socket(), ranch_transport(), Session::pid(), binary()) -> ok | stop | continue
                                                                            | {error, term()}
                                                                            | {extend, integer(), binary()}.
route(_,_,_, <<>>) ->
    continue;
route(Socket, Transport, Session, Raw) ->
    try mqtt_msg:decode(Raw) of
        {error, size, Extend} ->
            lager:notice("Packet is too short, missing ~p bytes", [Extend]),
            {extend, Extend, Raw};

        {error, protocol_version, _} ->
            % special error case: in case of wrong protocol version, the broker MUST return
            % a CONNACK packet with 0x01 error code
            % we bypass mqtt_session in this case
            Transport:send(Socket, mqtt_msg:encode(
                #mqtt_msg{type='CONNACK', payload=[{retcode, 1}]})),
            gen_fsm:stop(Session, normal, 50),
            Transport:close(Socket),
            stop;

        {error, Reason, _} ->
            lager:error("closing connection. Reason: ~p", [Reason]),
            gen_fsm:stop(Session, normal, 50),
            Transport:close(Socket),
            stop;

        {ok, Msg, Rest} ->
            lager:info("MQTT msg decoded: ~p", [Msg]),

            %case answer(Msg) of
            case mqtt_session:handle(Session, Msg) of
                {ok, Resp=#mqtt_msg{}} ->
                    lager:info("sending resp ~p", [Resp]),
                    Res = Transport:send(Socket, mqtt_msg:encode(Resp)),
                    lager:debug("msg send result= ~p", [Res]),
                    route(Socket, Transport, Session, Rest);

                {ok, undefined}  ->
                    lager:info("nothing to return"),
                    route(Socket, Transport, Session, Rest);

                {ok, disconnect} ->
                    lager:info("closing socket"),
                    %Transport:close(Socket),
                    stop;

                % send message then close connection
                {ok, {disconnect, M=#mqtt_msg{}}} ->
                    Res = Transport:send(Socket, mqtt_msg:encode(M)),
                    lager:debug("msg send result= ~p", [Res]),
                    stop
            end;


        _CatchAll ->
            lager:error("MQTT Msg unknown decoding error: ~p", [_CatchAll]),
            gen_fsm:stop(Session, normal, 50),
            Transport:close(Socket)

    catch
        Exc ->
            lager:error("failed decoding mqtt message: ~p", [Exc]),
            gen_fsm:stop(Session, normal, 50),
            Transport:close(Socket)
    end.


% send MQTT 'PINGREQ' message
%
%
-spec ping(ranch_transport(), ranch_socket()) -> ok | {error, term()}.
ping(Transport, Socket) ->
    Msg = #mqtt_msg{type='PINGREQ'},
    Transport:send(Socket, mqtt_msg:encode(Msg)).

% send kindof TCP keepalive
%
-spec crlfping(ranch_transport(), ranch_socket()) -> ok | {error, term()}.
crlfping(T, S) ->
    T:send(S, <<"">>).

% send MQTT message
%
-spec send(ranch_transport(), ranch_socket(), mqtt_msg()) -> ok | {error, term()}.
send(Transport, Socket, Msg) ->
    Transport:send(Socket, mqtt_msg:encode(Msg)).

% close underlying socket
%
-spec close(ranch_transport(), ranch_socket()) -> ok | {error, term()}.
close(Transport, Socket) ->
    lager:debug("closing ~p TCP sock", [Socket]),
    Transport:close(Socket).

-spec peername(ranch_ssl|ranch_tcp, inet:socket()) -> {ok, {inet:ipaddress(), inet:port_number()}} 
                                                      | {error, any()}.
peername(ranch_ssl, Socket) ->
    ssl:peername(Socket);
peername(_, Socket) ->
    inet:peername(Socket).
