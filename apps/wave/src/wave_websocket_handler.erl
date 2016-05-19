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

-module(wave_websocket_handler).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([init/2, websocket_handle/3, websocket_info/3]).

init(Req, Opts) ->
    % is it standard ??
	Req2 = cowboy_req:set_resp_header(<<"sec-websocket-protocol">>, <<"mqttv3.1">>, Req),

    % starts bridge ranch transport
    {ok, Transport} = wave_websocket:start(),
	{cowboy_websocket, Req2, #{transport => Transport}}.

%%
%% we support only binary frames
%%
websocket_handle({binary, Raw}, Req, State=#{transport := Transport}) ->
    lager:debug("received binary frame"),
    % forwarded to transport layer
    Transport ! {feed, Raw},

    {ok, Req, State};

websocket_handle(Data, Req, State) ->
	lager:notice("unsupported frame: ~p", [Data]),
	{ok, Req, State}.


% response generated from wave internals (session) : forwarded to peer
websocket_info({response, Data}, Req, State) ->
    lager:debug("sending binary frame"),
    {reply, {binary, Data}, Req, State};

% stop websocket & close connection
websocket_info(stop, Req, State) ->
    {stop, Req, State};

% timeout
websocket_info({timeout, _Ref, Msg}, Req, State) ->
    lager:debug("timeout"),
	{ok, Req, State};

% unhandleded message
websocket_info(_Info, Req, State) ->
	lager:error("info: ~p", [_Info]),
	{ok, Req, State}.
