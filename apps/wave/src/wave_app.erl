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
-export([start/0, start/2, stop/1, loglevel/1, fuzz/0]).

fuzz() ->
    io:format("fuzz~n").

%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
    lager:start(),

    application:ensure_all_started(gproc),
    application:ensure_all_started(shotgun),

    % redis pool
    ok = application:start(sharded_eredis),

    % HTTP server (+dependencies)
    application:start(crypto),
    application:start(asn1),
    application:start(public_key),
    application:start(ssl),

    application:start(ranch),

    % our main application
    application:start(wave).


start(_StartType, _StartArgs) ->
	lager:debug("starting wave app"),

    % start topics registry
    % TODO: use supervisor
    mqtt_topic_registry:start_link(),
    mqtt_offline:start_link(),
    wave_ctlmngr:start_link(),

	% start mqtt listeners
    {ok, _} = ranch:start_listener(wave, 1, ranch_tcp, [
            {port, env([plain, port])}
            ,{keepalive, true}
        ], mqtt_ranch_protocol, []),

    Ciphers = check_ciphers(env([ssl, ciphers])),
    lager:info("ciphers= (~p) ~p", [erlang:length(Ciphers), Ciphers]),
    {ok, _} = ranch:start_listener(wave_ssl, 1, ranch_ssl, [
            {port    , env([ssl, port])},
            {keepalive, true},
            {certfile, filename:join([
                                      filename:dirname(code:which(wave_app)),
                                      "../../../../..", "etc", "wave_cert.pem"])},
            {keyfile , filename:join([filename:dirname(code:which(wave_app)),
                                      "../../../../..", "etc", "wave_key.pem"])},

            % increase security level
            {secure_renegotiate, true},
            {reuse_sessions, false},
            {honor_cipher_order, true},
            {versions, env([ssl, versions])},
            {ciphers , Ciphers},
            % reduce memory usage
            {hibernate_after, 1000}

        ], mqtt_ranch_protocol, []),

    App = wave_sup:start_link(),

    %% loading modules
    ok = load_modules(),

    App.

stop(_State) ->
    ok.


env([Key|T]) ->
    env(application:get_env(wave, Key), T).


env(undefined, _) ->
    error;
env({ok, Node}, []) ->
    Node;
env({ok, Node}, [Key|T]) ->
    env({ok, proplists:get_value(Key, Node)}, T).

check_ciphers(Ciphers) ->
    lists:filter(fun(Cipher) ->
        try ssl_cipher:openssl_suite(Cipher) of
            _   -> true
        catch
            _:_ -> false
        end end,
        Ciphers
    ).

loglevel(Level) ->
    lager:set_loglevel(lager_console_backend, Level).


%%
%% MODULES MANAGEMENT
%%

load_modules() ->
    {ok, Mods} = application:get_env(wave, modules),

    Enabled = proplists:get_value(enabled, Mods),
    Opts    = proplists:get_value(settings, Mods, []),

    module_init(Enabled, Opts).

module_init([], _) ->
    ok;
module_init([Modname|Rest], Opts) ->
    lager:info("initializing ~p module", [Modname]),
    M = (wave_utils:atom("wave_mod_" ++ wave_utils:str(Modname))),

    % webservice entries
    case erlang:function_exported(M, ws, 0) of
        true  -> M:ws();
        false -> ok
    end,

    % start module
    M:start(proplists:get_value(Modname, Opts, [])),

    module_init(Rest, Opts).
