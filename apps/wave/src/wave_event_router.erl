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

-module(wave_event_router).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").

%
-export([route/2]).
% gen_server API
-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Conf) ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [Conf], []).

init([Conf]) ->
    lager:info("starting ~p module ~p", [?MODULE, Conf]),

    {ok, undefined}.


%%
%% PUBLIC API
%%


route(Topic, Msg) ->
    lager:debug("routing internal message (~p)", [Topic]),

    {ok, Worker} = mqtt_message_worker:start_link(),
    % async
    %NOTE: for now, all internal events are sent using QoS 0
    %      (because we have no fake publisher to receipt qos1/2 replies)
    %TODO: respect subscriber qos (mqtt_router should mimic a mqtt_session then)
    %TODO: config setting for internal events max qos
    mqtt_message_worker:publish(Worker, self(),
        #mqtt_msg{type='PUBLISH', qos=0, payload=[{topic, Topic},{data, jiffy:encode({Msg})}]}
    ),
    ok.

%%
%% PRIVATE API
%%

handle_call(_,_,State) ->
    {reply, ok, State}.


handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.

