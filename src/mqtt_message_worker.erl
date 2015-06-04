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
-export([publish/3, provisional/4, ack/3]).
% gen_server
%-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
% gen_fsm
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
% INTERNAL STATES
-export([start/2, provisional/2, waitacks/2]).

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

provisional(request, Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {provreq, From, Msg});
provisional(response, Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {provresp, From, Msg}).

ack(Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {ack, From, Msg}).

%%
%% INTERNAL STATES
%%

start({publish, From, Msg=#mqtt_msg{type='PUBLISH', qos=Qos, payload=P}}, _State) when Qos =:= 2 ->
    lager:debug("publish: ~p from ~p (qos=2)", [Msg, From]),

    %TODO: store message
    MsgID   = proplists:get_value(msgid, P),
    send(provreq, From, MsgID, 2),

    {next_state, provisional, #state{publisher=From, message=Msg}};

start({publish, From, Msg=#mqtt_msg{type='PUBLISH', qos=Qos, payload=P}}, State) ->
    lager:debug("publish: ~p from ~p (qos=~p)", [Msg, From, Qos]),
    S2 = publish_to_subscribers(From, Msg),

    case {Qos, length(S2)} of
        {0, 0} ->
            lager:info("Qos 0: exit immediately"),
            {stop, normal, State};

        {_, 0} ->
            % send PUBACK/PUBREL immediately
            MsgID   = proplists:get_value(msgid, P),
            send(ack, From, MsgID, Qos),
            {stop, normal, State};

        {_, _} ->
            % wait subscribers acknowledgement
            {next_state, waitacks, #state{publisher=From, subscribers=S2, message=Msg}}
    end.

% qos=2
provisional({provresp, From, Msg=#mqtt_msg{type='PUBREL', payload=P}}, State=#state{publisher=Pub, message=PubMsg}) ->
    lager:debug("provisional state: received provisional response ~p", [Msg]),
    Subscribers = publish_to_subscribers(Pub, PubMsg),
    case length(Subscribers) of
        0 ->
            % send PUBCOMP immediately
            MsgID   = proplists:get_value(msgid, P),
            send(ack, From, MsgID, 2),
            {stop, normal, State};

        _ ->
            % wait subscribers acknowledgement
            {next_state, waitacks, State#state{subscribers=Subscribers}}
    end.

%
% waiting subscribers acknowledgements
%
% for QOS 1, they must send back a PUBACK message
% for QOS 2, they must send back a PUBREC, then latter on a PUBCOMP
%

waitacks({provreq, From, Msg=#mqtt_msg{payload=P}}, State=#state{subscribers=S}) ->
    lager:debug("received provisional response from ~p: ~p", [From, Msg]),
    case lists:partition(fun({_,_,Pid,_}) -> Pid =:= From end, S) of
        {[], _} ->
            lager:error("~ not found in message subscribers", [From]),
            {next_state, waitacks, State};

        {[{2,provisional,From,_}], _} ->
            lager:info("Provisional response duplicate for ~", [From]),
            {next_state, waitacks, State};

        % PUBREC
        {[{2,published,From,Args}], S2} ->
            lager:debug("~p: matched provisional response. waiting acknowledgment", [From]),
            MsgID = proplists:get_value(msgid, P),
            send(provresp, From, MsgID, 2),

            {next_state, waitacks, State#state{subscribers=[{2,provisional,From,Args}|S2]}};

        {[{Qos,_,_,_}], _}              ->
            lager:info("~p: no provisional response needed for ~p QoS", [Qos]),
            {next_state, waitacks, State}
    end;

waitacks({ack, From, Msg}, State=#state{publisher=Pub, subscribers=S, message=#mqtt_msg{qos=Qos, payload=P}}) ->
    lager:debug("received ack from ~p: ~p", [From, Msg]),
    case lists:partition(fun({_,_,Pid,_}) -> Pid =:= From end, S) of
        {[], _} ->
            lager:error("~ not found in message subscribers", [From]),
            {next_state, waitacks, State};

        {[{Qos,Status,From,_}], []} ->
            if
                {Qos, Status} =:= {2, published} ->
                    lager:info("~p: provisional response not received before acknowledgement. accepted anyway");
                true ->
                    pass
            end,

            lager:debug("message delivery acknowledged by all subscribers: sending ack to publisher"),
            MsgID = proplists:get_value(msgid, P),
            send(ack, Pub, MsgID, Qos),
            {stop, normal, State};

        {[{Qos,Status,From,_}], S2} ->
            if
                {Qos, Status} =:= {2, published} ->
                    lager:info("~p: provisional response not received before acknowledgement. accepted anyway");
                true ->
                    pass
            end,

            lager:debug("waiting all acknowledgements (~p remaining)", [length(S2)]),
            {next_state, waitacks, State#state{subscribers=S2}};

        Invalid ->
            lager:error("smth is going wrong: ~p", [Invalid]),
            {next_state, waitacks, State}
    end;

waitacks({Event, From, Msg}, State) ->
    lager:info("~p: invalid ~p event in waitacks state: ~p. Ignored", [From, Event, Msg]),
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
send(publish, {Mod,Fun,Pid}, Topic, Payload, Qos) ->
    Mod:Fun(Pid, self(), Topic, Payload, Qos).

% send provisional response (PUBREC)
% ONLY for QoS 2
%
send(provreq, Publisher, MsgID, _Qos=2) ->
    mqtt_session:provisional(request, Publisher, MsgID);
send(provreq, _, _, _) ->
    pass;

send(provresp, Peer, MsgID, _Qos=2) ->
    mqtt_session:provisional(response, Peer, MsgID);

send(ack, Publisher, MsgID, Qos) ->
    mqtt_session:ack(Publisher, MsgID, Qos).



publish_to_subscribers(_From, #mqtt_msg{type='PUBLISH', qos=Qos, payload=P}) ->
    %MsgID   = proplists:get_value(msgid, P),
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
                EQos > 0 -> {true, {EQos, published, Pid, S}};
                true     -> false
            end

        end, Subscribers
    ),
    lager:debug("Subscrivers w/ qos > 0 = ~p", [S2]),
    S2.

