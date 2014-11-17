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

-include("include/mqtt_msg.hrl").

start_link(Ref, Socket, Transport, Opts) ->
    Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
    {ok, Pid}.

init(Ref, Socket, Transport, _Opts = []) ->
    ok = ranch:accept_ack(Ref),
    loop(Socket, Transport).

loop(Socket, Transport) ->
    %TODO: do not use *infinity* timeout (handle incorrectly closed sockets) 
    %      we can use PINGS to check socket state
    case Transport:recv(Socket, 0, 5000) of
        {ok, Data} ->
            %Transport:send(Socket, Data),
            route(Socket, Transport, Data),
            loop(Socket, Transport);

        {error, timeout} ->
            lager:debug("socket timeout. Sending ping"),
            Transport:send(Socket, mqtt_msg:encode(#mqtt_msg{type='PINGREQ'})),
            loop(Socket, Transport);

        Err ->
            lager:debug("err ~p. closing socket", [Err]),
            ok = Transport:close(Socket)
    end.

route(_,_, <<>>) ->
    continue;
route(Socket, Transport, Raw) ->
    case mqtt_msg:decode(Raw) of
        {error, disconnect, _} ->
            lager:info("closing connection"),
            Transport:close(Socket),
            stop;

        {ok, Msg, Rest} ->
            lager:info("ok ~p", [Msg]),
            
            case answer(Msg) of
                ok ->
                    lager:debug("no response to provide");

                error ->
                    lager:info("invalid query. closing socket"),
                    Transport:close(Socket);

                Resp  ->
                    lager:info("sending ~p", [Resp]),
                    Transport:send(Socket, mqtt_msg:encode(Resp)),

                    route(Socket, Transport, Rest)
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


