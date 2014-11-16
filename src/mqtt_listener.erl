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

-module(mqtt_listener).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-export([acceptor/2, processor/2, handle/2, reader/1]).
-export([start_link/3, init/1, handle_call/3, handle_info/2, handle_cast/2, code_change/3, terminate/2]).

-define(TCP_OPTIONS,[binary, {packet,raw},{active,false},{reuseaddr,true}]).

-include("include/mqtt_msg.hrl").

start_link(Mod, Args, Opts) ->
	gen_server:start_link(?MODULE, Args++[{mqtt_listener, reader}], Opts).


init([{port, Port},Callback]) ->
	lager:debug("starting mqtt listener on tcp ~p port", [Port]),

	case gen_tcp:listen(Port, ?TCP_OPTIONS) of
		{ok, Socket} -> 
			%% spawn accept process
			proc_lib:spawn_link(?MODULE, acceptor, [Socket, Callback]),
			{ok, Socket};

		{error, Reason} ->
			lager:error("fail opening mqtt socket= ~p", [Reason]),
			{stop, Reason}
	end.

%% accept loop
acceptor(LSocket, Callback) ->
	case gen_tcp:accept(LSocket) of
		{ok, Socket}   -> 
			lager:debug("new incoming connexion: ~w -> ~w~n", [inet:peername(Socket), inet:sockname(Socket)]),

			%% should use a supervisor to manage a pool of processors
			P = proc_lib:spawn_link(?MODULE, processor, [Socket, Callback]);
			%%gen_tcp:controlling_process(Socket, P),
			
		{error, Reason} ->
			lager:error("acceptor, fail to accept socket= ~p", [Reason])
	end,

	acceptor(LSocket, Callback).

%% process incoming connection
processor(Socket, {M,C}) ->
	%{Status, Messages} = M:C(Socket),
	M:C(Socket),

	%%TODO: handle messages
%	lager:debug("processor:end= ~p, ~p", [Status, Messages]),
%	case Status of
%		ok ->
%			%% spawn a new process to handle message
%			%% thus we can receive another data
%			%% TODO: handle this smarter
%			proc_lib:spawn(fun() ->
%				lists:foreach(fun(M) -> 
%							handle(M, Socket) end, Messages)
%			end),
%			processor(Socket, {M,C});
%		_ -> 
%			%gen_tcp:close(Socket),
%			pass
%	end.
    ok.

%% decode SIP message
reader(Socket) ->
	%% read socket
	lager:debug("waiting for data ~w~n", [inet:sockname(Socket)]),

	case gen_tcp:recv(Socket, 0) of %, 3000) of
		{ok, Data} -> 
            case doit(Socket, Data) of
                continue ->
                    reader(Socket);
                _ -> stop
            end;

		{error, Reason} ->
			lager:error("reader= ~p", [Reason]),
			{error, Reason}
	end.

doit(_,<<>>) ->
    continue;
doit(Socket, Raw) ->
    lager:debug("raw: ~p", [Raw]),
    case mqtt_msg:decode(Raw) of
        {error, disconnect, _} ->
            lager:info("closing connection"),
            gen_tcp:close(Socket),
            stop;

        {ok, Msg, Rest} ->
            lager:info("ok ~p", [Msg]),
            Resp = answer(Msg),
            lager:info("sending ~p", [Resp]),
            gen_tcp:send(Socket, mqtt_msg:encode(Resp)),

            doit(Socket, Rest),
            continue
    end.

answer(#mqtt_msg{type='CONNECT'}) ->
	#mqtt_msg{type='CONNACK', payload=[{retcode, 0}]};
answer(#mqtt_msg{type='PUBLISH'}) ->
	#mqtt_msg{type='CONNACK', payload=[{retcode, 0}]};
answer(#mqtt_msg{type='PINGREQ'}) ->
	#mqtt_msg{type='PINGRESP'};
answer(#mqtt_msg{type='SUBSCRIBE', payload=P}) ->
	MsgId = proplists:get_value(msgid, P),

	#mqtt_msg{type='SUBACK', payload=[{msgid,MsgId},{qos,[1]}]}.


handle(M, Sock) ->
	ok.

%%
%% unused

code_change(_OldVersion, Library, _Extra) ->
	{ok, Library}.
terminate(_Reason, _Library) ->
	ok.
handle_call(Msg, _Caller, State) ->
	{reply, ok, ok}.

handle_info(_Msg, Library) ->
	{noreply, Library}.
handle_cast({free, Ch}, State) ->
	{noreply, State}.

