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

%%
%% fake ranch transport
%%

-module(wave_websocket).
-author("Guillaume Bour <guillaume@bour.cc>").
%%
%%TODO: need to implement missing functions (even if empty)
%%-behaviour(ranch_transport).

-export([start/0, init/1, name/0, recv/3, send/2, close/1]).

-record(state, {
    wsh, % websocket handler (pid)
    reader,
    protocol,

    in= <<>>,  % input buffer (binary)
    out % output buffer
}).

%% 
%% PUBLIC API
%% 

start() ->
    %TODO: using proc_lib:start_link()
    Pid = erlang:spawn(?MODULE, init, [#state{wsh=self()}]),
    {ok, Pid}.

init(State) ->
    %                                               ref, socket, transport, opts
    {ok, Protocol} = mqtt_ranch_protocol:start_link(undefined, self(), wave_websocket, []),
    loop(State#state{protocol=Protocol}).

name() ->
    ws.

recv(Socket, Length, Timeout) ->
    Socket ! {recv, self(), Length},

    % wait response (blocking until Timeout)
    receive
        {ok, Data} -> {ok, Data}
    after 
        Timeout -> {error, timeout}
    end.

send(Socket, Packet) ->
    Socket ! {send, self(), Packet},
    ok.

close(Socket) ->
    Socket ! shutdown,
    ok.
%%
%%
%%

%%TODO: use a gen_server instead
loop(State=#state{in=In, reader=Reader, wsh=Wsh}) ->
    receive
        % incoming packet
        {feed, Pkt} ->
            case Reader of
                undefined -> loop(State#state{in= <<In/binary, Pkt/binary>>});
                Reader    -> 
                    Reader ! {ok, Pkt},
                    loop(State#state{reader=undefined})
            end;

        {recv, Pid, _Length} ->
            lager:debug("recv command (from ~p)", [Pid]),
            case In of
                <<>> -> 
                    % no in data - save receiver
                    loop(State#state{reader=Pid});

                In ->
                    Pid ! {ok, In},
                    loop(State#state{reader=undefined,in= <<>>})
            end;

        {send, _Pid, Pkt} ->
            Wsh ! {response, Pkt},
            loop(State);

        shutdown ->
            % notify websocket handler to stop, then exit
            Wsh ! stop;

        _Err -> 
            lager:notice("invalid cmd: ~p", [_Err]),
            loop(State)
    end.
    


