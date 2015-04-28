%%
%%    Wave - MQTT Broker
%%    Copyright (C) 2014 - Guillaume Bour
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

-include("include/mqtt_msg.hrl").

start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

init(Ref, Socket, Transport, _Opts = []) ->
    ok = ranch:accept_ack(Ref),

    {ok, Session} = mqtt_session:start_link({?MODULE, Transport, Socket}),
    lager:debug("fsm= ~p (~p)", [Session, Transport]),
    loop(Socket, Transport, Session).

loop(Socket, Transport, Session) ->
    %TODO: do not use *infinity* timeout (handle incorrectly closed sockets)
    %      we can use PINGS to check socket state
    case Transport:recv(Socket, 0, infinity) of %5000) of
        {ok, Data} ->
            case route(Socket, Transport, Session, Data) of
                continue ->
                    loop(Socket, Transport, Session);
                _ ->
                    stop
            end;

        {error, timeout} ->
            lager:debug("socket timeout. Sending ping"),
            Transport:send(Socket, mqtt_msg:encode(#mqtt_msg{type='PINGREQ'})),
            loop(Socket, Transport, Session);

        % socket closed by peer
        {error, closed} ->
            lager:debug("err:closed"),
            mqtt_session:disconnect(Session, peer_sock_closed),
            ok;

        % TCP keepalive timeout
        {error, etimedout} ->
            lager:debug("err:tcp keepalive timeout"),
            mqtt_session:disconnect(Session, peer_tcp_ka_timeout),
            ok;

        Err ->
            lager:debug("err ~p. closing socket", [Err]),
            ok = Transport:close(Socket)
    end,

    Transport:close(Socket),
    ok.

route(_,_,_, <<>>) ->
    continue;
route(Socket, Transport, Session, Raw) ->
    case mqtt_msg:decode(Raw) of
        {error, disconnect, _} ->
            lager:info("closing connection"),
            Transport:close(Socket),
            stop;

        {ok, Msg, Rest} ->
            lager:info("ok ~p", [Msg]),

            %case answer(Msg) of
            case mqtt_session:handle(Session, Msg) of
                {ok, Resp=#mqtt_msg{}} ->
                    lager:info("sending resp ~p", [Resp]),
                    Transport:send(Socket, mqtt_msg:encode(Resp)),
                    route(Socket, Transport, Session, Rest);

                {ok, undefined}  ->
                    lager:info("nothing to return"),
                    route(Socket, Transport, Session, Rest);

                {ok, disconnect} ->
                    lager:info("closing socket"),
                    %Transport:close(Socket),
                    stop
            end
    end.

answer(#mqtt_msg{type='CONNECT'}) ->
	#mqtt_msg{type='CONNACK', payload=[{retcode, 0}]};
answer(#mqtt_msg{type='PUBLISH'}) ->
	#mqtt_msg{type='CONNACK', payload=[{retcode, 0}]};
answer(#mqtt_msg{type='PINGREQ'}) ->
	#mqtt_msg{type='PINGRESP'};
answer(#mqtt_msg{type='SUBSCRIBE', payload=P}) ->
	MsgId = proplists:get_value(msgid, P),

	#mqtt_msg{type='SUBACK', payload=[{msgid,MsgId},{qos,[1]}]};
answer(#mqtt_msg{type='PINGRESP'}) ->
    ok;
answer(_) ->
    error.

ping(Transport, Socket) ->
    %Transport:send(Socket, mqtt_msg:encode(#mqtt_msg{type='PINGREQ'})).
    %Msg = #mqtt_msg{type='PUBLISH', payload=[{topic,<<"foobar">>}, {msgid,1234}, {content, <<"chello">>}]},
    Msg = #mqtt_msg{type='PINGREQ'},
    Transport:send(Socket, mqtt_msg:encode(Msg)).

crlfping(T, S) ->
    T:send(S, <<"">>).

send(Transport, Socket, Msg) ->
    Transport:send(Socket, mqtt_msg:encode(Msg)).

close(Transport, Socket) ->
    Transport:close(Socket).

