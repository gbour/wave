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

    MsgID   = proplists:get_value(msgid, P),
    Topic   = proplists:get_value(topic, P),
    Content = proplists:get_value(data, P),

    Subscribers = mqtt_topic_registry:match(Topic),
    lager:info("subscribers= ~p", [Subscribers]),
    S2 = lists:filtermap(fun(S={TopicMatch, SQos, Subscriber={_,_,Pid}, _}) ->
            EQos = min(Qos, SQos),
            lager:debug("~p: effective qos=~p", [Pid, EQos]),

            case is_process_alive(Pid) of
                true ->
                    send(publish, Subscriber, {Topic, TopicMatch}, Content, EQos);

                _    ->
                    %NOTE: SHOULD NEVER HAPPEND
                    lager:error("deadbeef: ~p subscriber is dead", [Pid])
            end,

            if
                EQos > 0 -> {true, {EQos, Pid, S}};
                true     -> false
            end

        end, Subscribers
    ),
    lager:debug("Subscrivers w/ qos > 0 = ~p", [S2]),

    case {Qos, length(S2)} of
        {0, 0} ->
            lager:info("Qos 0: exit immediately"),
            {stop, normal, State};

        {_, 0} ->
            % send PUBACK/PUBREL immediately
            send(ack, From, MsgID, Qos),
            {stop, normal, State};

        {_, _} ->
            % wait subscribers acknowledgement
            {next_state, waitacks, State#state{publisher=From, subscribers=S2, message=Msg}}
    end.

waitacks({ack, From, Msg}, State=#state{publisher=Pub, subscribers=S, message=#mqtt_msg{qos=Qos, payload=P}}) ->
    lager:debug("received ack from ~p: ~p", [From, Msg]),
    case lists:partition(fun({_,Pid,_}) -> Pid =:= From end, S) of
        {[], _} ->
            lager:error("~ not found in message subscribers", [From]),
            {next_state, waitacks, State};

        {[{_,From,_}], []} ->
            lager:debug("message delivery acknowledged by all subscribers: sending ack to publisher"),
            MsgID = proplists:get_value(msgid, P),
            send(ack, Pub, MsgID, Qos),
            {stop, normal, State};

        {[{_,From,_}], S2} ->
            lager:debug("waiting all acknowledgements (~p remaining)", [length(S2)]),
            {next_state, waitacks, State#state{subscribers=S2}};

        Invalid ->
            lager:error("smth is going wrong: ~p", [Invalid]),
            {next_state, wait_acks, State}
    end.

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
send(publish, {Mod,Fun,Pid}, Topic, Payload, Qos=0) ->
    Mod:Fun(Pid, self(), Topic, Payload, Qos),
    0;

send(publish, {Mod,Fun,Pid}, Topic, Payload, Qos=1) ->
    Mod:Fun(Pid, self(), Topic, Payload, Qos),
    0.

send(ack, Publisher, MsgID, Qos) ->
    mqtt_session:ack(Publisher, MsgID, Qos).



