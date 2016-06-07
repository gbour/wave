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

-module(wave_sup).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(CHILD(I, Type, A), {I, {I, start_link, [A]}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(Args) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Args).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init(Args) ->
    {ok, {{one_for_one, 5, 10}, [
        ?CHILD(mqtt_topic_registry, worker)
        ,?CHILD(mqtt_retain, worker)
        ,?CHILD(mqtt_offline, worker)
        ,?CHILD(mqtt_offline_session, worker)
        ,?CHILD(mqtt_lastwill_session, worker)
        ,?CHILD(wave_ctlmngr, worker)
        ,?CHILD(wave_auth, worker, maps:get(auth, Args, undefined))

        ,?CHILD(wave_sessions_sup, supervisor)
        ,?CHILD(wave_msgworkers_sup, supervisor)
    ]}}.

