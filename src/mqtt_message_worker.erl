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

-module(mqtt_message_worker).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_fsm).

-include("include/mqtt_msg.hrl").

-export([start_link/0]).

% API
-export([publish/3, ack/3]).
% gen_server
%-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
% gen_fsm
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
% INTERNAL STATES
-export([start/2, waitacks/2]).

-record(state, {
    publisher,
    subscribers,
    message
}).

-define(CONNECT_TIMEOUT  , 5000). % ms
-define(DEFAULT_KEEPALIVE, 300).  % secs

start_link() ->
    gen_fsm:start_link(?MODULE, [], []).

init(_) ->
    {ok, start, #state{}}.


%%
%% API
%%

publish(Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {publish, From, Msg}).

ack(Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {ack, From, Msg}).

%%
%% INTERNAL STATES
%%

start({publish, From, Msg=#mqtt_msg{type='PUBLISH', qos=Qos, payload=P}}, State) ->
    lager:debug("publish: ~p from ~p", [Msg, From]),

    Topic   = proplists:get_value(topic, P),
    Content = proplists:get_value(data, P),

    Subscribers = mqtt_topic_registry:match(Topic),
    lager:info("subscribers= ~p", [Subscribers]),
    Qoses = lists:map(fun({TopicMatch, Subscriber={_,_,Pid}, _}) ->
            case is_process_alive(Pid) of
                true ->
                    send(Subscriber, {Topic, TopicMatch}, Content, Qos);

                _    ->
                    %NOTE: SHOULD NEVER HAPPEND
                    lager:error("deadbeef: ~p subscriber is dead", [Pid]),
                    0
            end

        end, Subscribers
    ),
    lager:debug("Qoses = ~p", [Qoses]),

    case {Qos, maxqos(Qoses)} of
        {0, _} ->
            lager:info("Qos 0: exit immediately"),
            {stop, normal, State};

        {_, 0} ->
            % send PUBACK/PUBREL immediately
            {stop, normal, State};

        {_, _} ->
            % wait subscribers acknowledgement
            {next_state, waitacks, State#state{publisher=From, subscribers=Subscribers, message=Msg}}
    end.

waitacks({ack, From, Msg}, State) ->
    {next_state, waitacks, State}.

%%
%% GENERIC FSM CALLBACKS
%%

handle_event(_Event, _StateName, StateData) ->
	lager:debug("event ~p", [_StateName]),
    {stop, error, StateData}.

handle_sync_event(_Event, _From, _StateName, StateData) ->
	lager:debug("syncevent ~p", [_StateName]),
    {stop, error, error, StateData}.

handle_info(_Info, _StateName, StateData) ->
	lager:debug("info ~p", [_StateName]),
    {stop, error, StateData}.

terminate(_Reason, StateName, _StateData) ->
    lager:debug("terminate: ~p ~p ~p", [_Reason, StateName, _StateData]),
    terminate.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


%%
%% PRIVATE
%%

%
% QoS=0 => fire and forget
send({Mod,Fun,Pid}, Topic, Payload, Qos=0) ->
    Mod:Fun(Pid, Topic, Payload, Qos),
    0.

maxqos([]) ->
    0;
maxqos(List) ->
    lists:max(List).


