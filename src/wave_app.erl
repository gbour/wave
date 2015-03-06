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

    application:ensure_all_started(gproc),
    application:ensure_all_started(shotgun),

    % HTTP server (+dependencies)
    application:start(crypto),
    application:start(asn1),
    application:start(public_key),
    application:start(ssl),

    application:start(ranch),
	application:start(wave).


start(_StartType, _StartArgs) ->
	lager:debug("starting wave app"),

    % start redis connection
    {ok, Conn} = eredis:start_link("127.0.0.1", 6379, 1),
    application:set_env(wave, redis, Conn),

    % start topics registry
    % TODO: use supervisor
    mqtt_topic_registry:start_link(),
    mqtt_offline:start_link(),
    wave_ctlmngr:start_link(),

    % start modules
    {ok, Mods} = application:get_env(wave, modules),
    lager:info("~p", [Mods]),
    load_module(Mods),

	% start mqtt listener
	{ok, MqttPort} = application:get_env(wave, mqtt_port),
	{ok, MqttSslPort} = application:get_env(wave, mqtt_ssl_port),

    {ok, _} = ranch:start_listener(wave, 1, ranch_tcp, [{port, MqttPort}], mqtt_ranch_protocol, []),
    Ret = ranch:start_listener(wave_ssl, 1, ranch_ssl, [
            {port, MqttSslPort},
            {certfile, filename:join([filename:dirname(code:which(wave_app)), "..", "etc", "wave_cert.pem"])},
            {keyfile, filename:join([filename:dirname(code:which(wave_app)), "..", "etc", "wave_key.pem"])},

            % increase security level
            {secure_renegotiation, true},
            {reuse_sessions, false},
            {versions, ['tlsv1.1', 'tlsv1.2']},
            {ciphers, [
                "ECDHE-ECDSA-AES128-SHA", "ECDHE-ECDSA-AES128-SHA256",
                "ECDHE-ECDSA-AES256-SHA", "ECDHE-ECDSA-AES256-SHA384",
                "ECDHE-ECDSA-AES256-SHA", "ECDHE-ECDSA-AES256-SHA384",
                "DHE-RSA-AES256-SHA256"
            ]},
            % reduce memory usage
            {hibernate_after, 1000}

        ], mqtt_ranch_protocol, []),
    lager:debug("SSL listener: ~p", [Ret]),

	wave_sup:start_link().

stop(_State) ->
    ok.

load_module([{Mod, Args} |T]) ->
    lager:info("load ~p", [Mod]),
    (erlang:list_to_atom("wave_mod_"++erlang:atom_to_list(Mod))):start_link(Args),

    load_module(T);

load_module([]) ->
    ok.
