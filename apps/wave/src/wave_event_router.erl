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
    lager:debug("routing ~p", [Topic]),
    MatchList = mqtt_topic_registry:match(Topic),
    Qos = 0,
    Content = Msg,

    [
        case is_process_alive(Pid) of
            true ->
                lager:info("candidate: pid=~p, topic=~p, content=~p", [Pid, Topic, Content]),
                Ret = Mod:Fun(Pid, {Topic,TopicMatch}, Content, SQos),
                lager:info("publish to client: ~p", [Ret]),
                case {SQos, Ret} of
                    {0, disconnect} ->
                        lager:debug("client ~p disconnected but QoS = 0. message dropped", [Pid]);

                    {_, disconnect} ->
                        lager:debug("client ~p disconnected while sending message", [Pid]),
%                        mqtt_topic_registry:unsubscribe(Subscr),
%                        mqtt_offline:register(Topic, DeviceID),
                        mqtt_offline:event(undefined, {Topic, SQos}, Content),
                        ok;

                    _ ->
                        ok
                end;

            _ ->
                % SHOULD NEVER HAPPEND
                lager:error("deadbeef ~p", [Pid])

        end

        || _Subscr={TopicMatch, SQos, {Mod,Fun,Pid}, _Fields} <- MatchList
    ],

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

