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

-module(wave_app).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(application).

%% Application callbacks
-export([start/0, start/2, stop/1, loglevel/1]).

-define(DEBUGW(X), ok).
-ifdef(DEBUG).
    -export([debug_cleanup/0]).

    -undef(DEBUGW).
    -define(DEBUGW(X), lager:error(X)).
-endif.


%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
    lager:start(),
    lager:warning("Starting wave in debug mode"),

    {ok, _Apps} = application:ensure_all_started(wave),
    lager:debug("loaded apps: ~p", [_Apps]),
    ok.

start(_StartType, _StartArgs) ->
	lager:debug("starting wave app"),
    ?DEBUGW("DEBUG MODE ACTIVATED"),

    % initialize syn (global process registry)
    syn:init(),

    % start master supervisor (starting named servers)
    {ok, WaveSup} = wave_sup:start_link(),

    % start modules supervisor, add it as master sup child
    supervisor:start_child(WaveSup, {wave_modules_sup,
        {wave_modules_sup, start_link, []}, 
        permanent, 5000, supervisor, [wave_modules_sup]}
    ),

	% start mqtt listeners
    supervisor:start_child(WaveSup, ranch:child_spec(wave_tcp, 1, ranch_tcp, [
            {port, env([plain, port])}
            ,{keepalive, true}
        ], mqtt_ranch_protocol, [])),

    Ciphers = check_ciphers(env([ssl, ciphers])),
    lager:info("ciphers= (~p) ~p", [erlang:length(Ciphers), Ciphers]),
    supervisor:start_child(WaveSup, ranch:child_spec(wave_ssl, 1, ranch_ssl, [
            {port    , env([ssl, port])},
            {keepalive, true},
            {certfile, env([ssl, certfile])},
            {keyfile , env([ssl, keyfile])},

            % increase security level
            {secure_renegotiate, true},
            {reuse_sessions, false},
            {honor_cipher_order, true},
            {versions, env([ssl, versions])},
            {ciphers , Ciphers},
            % reduce memory usage
            {hibernate_after, 1000}

        ], mqtt_ranch_protocol, [])),
    
    % websocket listener
	Dispatch = cowboy_router:compile([
		{'_', [
			{"/websocket", wave_websocket_handler, []}
		]}
	]),

	{ok, _} = cowboy:start_http(ws, 1, [
            {port, 1884}
        ], [{env, [{dispatch, Dispatch}]}]),

	{ok, _} = cowboy:start_https(wss, 1, [
            {port, 8884},
            {certfile, env([ssl, certfile])},
            {keyfile , env([ssl, keyfile])},

            % increase security level
            {secure_renegotiate, true},
            {reuse_sessions, false},
            {honor_cipher_order, true},
            {versions, env([ssl, versions])},
            {ciphers , Ciphers},
            % reduce memory usage
            {hibernate_after, 1000}

        ], [{env, [{dispatch, Dispatch}]}]),
	%websocket_sup:start_link().

    {ok, WaveSup}.

stop(_State) ->
    ok.


-spec env([atom()]) -> term().
env([Key|T]) ->
    env(application:get_env(wave, Key), T).


env(undefined, _) ->
    error;
env({ok, Node}, []) ->
    Node;
env({ok, Node}, [Key|T]) ->
    env({ok, proplists:get_value(Key, Node)}, T).

-spec check_ciphers(list(string())) -> list(string()).
check_ciphers(Ciphers) ->
    lists:filter(fun(Cipher) ->
        try ssl_cipher:openssl_suite(Cipher) of
            _   -> true
        catch
            _:_ -> false
        end end,
        Ciphers
    ).

%TODO: what is lager:set_loglevel() return ?
-spec loglevel(integer) -> any().
loglevel(Level) ->
    lager:set_loglevel(lager_console_backend, Level).


-ifdef(DEBUG).
debug_cleanup() ->
    mqtt_topic_registry:debug_cleanup(),
    mqtt_offline:debug_cleanup(),

    ok.
-endif.
