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

-module(wave_app).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(application).

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
    lager:start(),
    lager:set_loglevel(lager_console_backend, debug),

    application:start(gproc),

    % HTTP server (+dependencies)
    application:start(crypto),
    application:start(asn1),
    application:start(public_key),
    application:start(ssl),

    application:start(ranch),
	application:start(wave).


start(_StartType, _StartArgs) ->
	lager:debug("starting wave app"),

    % start topics registry
    % TODO: use supervisor
    mqtt_topic_registry:start_link(),
    wave_ctlmngr:start_link(),

	% start mqtt listener
	{ok, MqttPort} = application:get_env(wave, mqtt_port),
    {ok, _} = ranch:start_listener(wave, 1, ranch_tcp, [{port, MqttPort}], mqtt_ranch_protocol, []),

	wave_sup:start_link().

stop(_State) ->
    ok.
