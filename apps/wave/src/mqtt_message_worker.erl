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

-module(mqtt_message_worker).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_fsm).

-include("mqtt_msg.hrl").

-export([start_link/0]).

% API
-export([publish/3, publish/4, provisional/4, ack/3]).
% gen_fsm
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
% INTERNAL STATES
-export([start/2, provisional/2, waitacks/2]).

-type subscriber() :: {EffectiveQos::integer(),published, Receiver::pid(),mqtt_topic_registry:match_result()}.

-record(state, {
    publisher    :: pid(),
    message      :: mqtt_msg(),
    subscribers  :: list(mqtt_topic_registry:match_result()),
    inflight     :: [subscriber()]
}).
-type state() :: #state{}.


-define(CONNECT_TIMEOUT  , 5000). % ms
-define(DEFAULT_KEEPALIVE, 300).  % secs

start_link() ->
    gen_fsm:start_link(?MODULE, [], []).

init(_) ->
    {ok, start, #state{}}.


%%
%% API
%%

%
% Generally speaking, Emitter is a mqtt_session pid,
% But in case of last will message with qos = 2, Emitter acknowledgment as too be faked,
% this is the role of mqtt_lastwill_session server (locally named 'lastwill_session'
%
-spec publish(Worker::pid(), Emitter::pid()|'lastwill_session', Msg::mqtt_msg()) -> ok.
publish(Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {publish, From, Msg, undefined}).

-spec publish(Worker::pid(), Emitter::pid()|'retain_session'|'offline_session', Msg::mqtt_msg(), 
              list(mqtt_topic_registry:match_result())) -> ok.
publish(Pid, From, Msg, Subscribers) ->
    gen_fsm:send_event(Pid, {publish, From, Msg, Subscribers}).

-spec provisional(request|response, Worker::pid(), Emitter::pid(), Msg::mqtt_msg()) -> ok.
provisional(request, Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {provreq, From, Msg});
provisional(response, Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {provresp, From, Msg}).

-spec ack(Worker::pid(), Emitter::pid(), Msg::mqtt_msg()) -> ok.
ack(Pid, From, Msg) ->
    gen_fsm:send_event(Pid, {ack, From, Msg}).

%%
%% INTERNAL STATES
%%

start({publish, From, Msg=#mqtt_msg{type='PUBLISH', qos=Qos, payload=P}, Subscribers}, _State) when Qos =:= 2 ->
    lager:debug("publish: ~p from ~p (qos=2) => subs ~p", [Msg, From, Subscribers]),

    %TODO: store message
    MsgID   = proplists:get_value(msgid, P),
    send(provreq, From, MsgID, 2),

    {next_state, provisional, #state{publisher=From, message=Msg, subscribers=Subscribers}, 5000};

start({publish, From, Msg=#mqtt_msg{type='PUBLISH', qos=Qos, payload=P}, Subscribers}, State) ->
    lager:debug("publish: ~p from ~p (qos=~p) => subs ~p", [Msg, From, Qos, Subscribers]),
    S2 = publish_to_subscribers(From, Msg, Subscribers),

    case {Qos, length(S2)} of
        {0, 0} ->
            lager:info("Qos 0: exit immediately"),
            {stop, normal, State};

        {_, 0} ->
            % send PUBACK/PUBREL immediately
            MsgID   = proplists:get_value(msgid, P),
            send(ack, From, MsgID, Qos),
            mqtt_session:landed(From, MsgID), % message no more in in-flight mode

            {stop, normal, State};

        {_, _} ->
            % wait subscribers acknowledgement
            {next_state, waitacks, #state{publisher=From, message=Msg, inflight=S2}, 5000}
    end.

% qos=2
provisional({provresp, From, Msg=#mqtt_msg{type='PUBREL', payload=P}}, 
            State=#state{publisher=Pub, message=PubMsg, subscribers=Subscribers}) ->
    lager:debug("provisional state: received provisional response ~p", [Msg]),
    Inflight = publish_to_subscribers(Pub, PubMsg, Subscribers),
    case length(Inflight) of
        0 ->
            % send PUBCOMP immediately
            MsgID   = proplists:get_value(msgid, P),
            send(ack, From, MsgID, 2),
            mqtt_session:landed(From, MsgID), % message no more in in-flight mode

            {stop, normal, State};

        _ ->
            % wait subscribers acknowledgement
            {next_state, waitacks, State#state{inflight=Inflight}, 5000}
    end;


provisional({Event, From, Msg}, State) ->
    lager:warning("received invalid ~p event (~p) from ~p while in provisional state", [Event, Msg, From]),
    {next_state, provisional, State, 5000};

provisional(timeout, State=#state{publisher=From, message=#mqtt_msg{qos=Qos}}) ->
    case is_process_alive(From) of
        % publisher still, waiting PUBREL
        true -> {next_state, provisional, State, 5000};

        % publisher dead, stopping worker
        _    -> 
            lager:warning("publisher ~p is dead: canceling message delivery (qos ~p, no PUBREL received)", [From, Qos]),
            {stop, normal, State}
    end.

%
% waiting subscribers acknowledgements
%
% for QOS 1, they must send back a PUBACK message
% for QOS 2, they must send back a PUBREC, then latter on a PUBCOMP
%

waitacks({provreq, From, Msg=#mqtt_msg{payload=P}}, State=#state{inflight=Inflight}) ->
    lager:debug("received provisional response from ~p: ~p", [From, Msg]),

    MsgID         = proplists:get_value(msgid, P),
    {Match, Rest} = lists:partition(fun({_,_,Pid,ID,_}) -> Pid =:= From andalso ID =:= MsgID end, Inflight),

    case {Match, Rest} of 
        {[], _} ->
            lager:error("~p not found in message subscribers", [From]),
            {next_state, waitacks, State, 5000};

        {[{2,provisional,From,_,_}], _} ->
            lager:info("Provisional response duplicate for ~p", [From]),
            {next_state, waitacks, State, 5000};

        % PUBREC
        {[{2,published,From,MsgID,Args}], Rest} ->
            lager:debug("~p: matched provisional response. waiting acknowledgment", [From]),
            send(provresp, From, MsgID, 2),

            {next_state, waitacks, State#state{inflight=[{2,provisional,From,MsgID,Args} | Rest]}, 5000};

        {[{Qos,_,_,_,_}], _}              ->
            lager:info("~p: no provisional response needed for ~p QoS", [From, Qos]),
            {next_state, waitacks, State, 5000};

        {Match, _}                        ->
            lager:error("~p: more than 1 match found: ~p", [From, Match]),
            {next_state, waitacks, State, 5000}
    end;

waitacks({ack, From, Msg=#mqtt_msg{type=MsgType, payload=P}}, State=#state{publisher=Pub, inflight=Inflight}) ->
    lager:debug("received ack from ~p: ~p", [From, Msg]),

    MsgID         = proplists:get_value(msgid, P),
    {Match, Rest} = lists:partition(fun({_,_,Pid,ID,_}) -> Pid =:= From andalso ID =:= MsgID end, Inflight),

    case checkack(MsgType, Match, Rest, State) of
        pass  ->
            {next_state, waitacks, State, 5000};

        stop  ->
            mqtt_session:landed(From, MsgID), % message no more in in-flight mode
            {stop, normal, State};

        acked ->
            mqtt_session:landed(From, MsgID), % message no more in in-flight mode
            {next_state, waitacks, State#state{inflight=Rest}, 5000}
    end;


waitacks({Event, From, Msg}, State) ->
    lager:warning("~p: invalid ~p event in waitacks state: ~p. Ignored", [From, Event, Msg]),
    {next_state, waitacks, State, 5000};

waitacks(timeout, State=#state{inflight=Inflight}) ->
    {Inflight2, Dead} = lists:partition(fun({_,_,Pid,_,_}) -> is_process_alive(Pid) end, Inflight),
    lager:warning("dead subscribers: ~p", [Dead]),
    
    case Inflight2 of
        [] ->
            lager:warning("no more alive subscribers: canceling message delivery"),
            {stop, normal, State};

        Inflight2 ->
            {next_state, waitacks, State#state{inflight=Inflight2}, 5000}
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


% Forward a message to subscriber
%
%TODO: check return status (if sender died => stop message delivery) when possible
%      (when is async, result is always 'ok')
-spec send(publish, Receiver::mqtt_topic_registry:subscriber(), {Topic::binary(), TFilter::binary()}, 
           Payload::binary(), Qos::integer(), Retain::mqtt_retain()) -> integer().
send(publish, {Mod,Fun,Pid,DeviceID}, Topic, Payload, Qos, Retain) ->
    Mod:Fun(Pid, self(), DeviceID, Topic, Payload, Qos, Retain).

% send provisional response (PUBREC)
% ONLY for QoS 2
%
-spec send(provreq|provresp|ack, Emitter::pid(), MsgID::binary(), Qos::integer()) -> ok.
send(provreq, Publisher, MsgID, _Qos=2) ->
    mqtt_session:provisional(request, Publisher, MsgID, self());
send(provreq, _, _, _) ->
    pass;

send(provresp, Peer, MsgID, _Qos=2) ->
    mqtt_session:provisional(response, Peer, MsgID, self());

send(ack, Publisher, MsgID, Qos) ->
    mqtt_session:ack(Publisher, MsgID, Qos, self()).


% Forward published message to all subscribers
%
-spec publish_to_subscribers(Emitter::pid(), Msg::mqtt_msg(), 
                             Subscribers::list(mqtt_topic_registry:match_result()))  -> list(subscriber()).
publish_to_subscribers(From, Msg=#mqtt_msg{payload=P}, undefined) ->
    Topic = proplists:get_value(topic, P),
    publish_to_subscribers(From, Msg, mqtt_topic_registry:match(Topic));

publish_to_subscribers(    _,                                                            _, []) ->
    lager:info("no subscribers to publish message to"),
    [];

publish_to_subscribers(_From, #mqtt_msg{type='PUBLISH', qos=Qos, retain=Retain, payload=P}, Subscribers) ->
    %MsgID   = proplists:get_value(msgid, P),
    Topic   = proplists:get_value(topic, P),
    Content = proplists:get_value(data, P),

    lager:info("subscribers= ~p", [Subscribers]),
    S2 = lists:filtermap(fun(S={TopicMatch, SQos, Subscriber={_,_,Pid,_}, _}) ->
            EQos = min(Qos, SQos),
            lager:debug("~p: effective qos=~p", [Pid, EQos]),

            MsgID = case is_process_alive(Pid) of
                true ->
                    send(publish, Subscriber, {Topic, TopicMatch}, Content, EQos, Retain);

                _    ->
                    %NOTE: SHOULD NEVER HAPPEND
                    lager:error("deadbeef: ~p subscriber is dead", [Pid]),
                    0
            end,

            if
                EQos > 0 andalso MsgID > 0 -> {true, {EQos, published, Pid, MsgID, S}};
                true                       -> false
            end

        end, Subscribers
    ),
    lager:debug("Subscrivers w/ qos > 0 = ~p", [S2]),
    S2.


% Send ACKNOWLEDGEMENT to emitter
%
%
-spec checkack(AckType::'PUBACK'|'PUBCOMP', Subscribers::[subscriber()], Rest::[subscriber()], state()) -> 
        pass|stop|acked.
checkack(_, _Match=[], _, _) ->
    lager:error("~p not found in message subscribers", ["Subscriber"]),
    pass;

% qos 1
% no remaining subscribers waiting for acknowledgement 
% we send acknowledgement back to publisher
checkack('PUBACK', [{_EQos=1, _,_,_,_}], [], #state{publisher=Pub, message=#mqtt_msg{qos=Qos, payload=P}}) ->
    lager:debug("message delivery acknowledged by all subscribers: sending ack to publisher"),
    MsgID = proplists:get_value(msgid, P),
    send(ack, Pub, MsgID, Qos),
    stop;

checkack('PUBACK', [{_EQos=1, _,_,_,_}], Rest, _) ->
    lager:debug("waiting all acknowledgements (~p remaining)", [length(Rest)]),
    acked;

% qos 2
% no remaining subscribers 
% we send
checkack('PUBCOMP', [{_EQos=2, Status, _,_,_}], [], 
         #state{publisher=Pub, message=#mqtt_msg{qos=Qos, payload=P}}) ->
    case Status of
        published ->
            lager:info("~p: provisional response not received before acknowledgement. accepted anyway");
        _         ->
            pass
    end,

    lager:debug("message delivery acknowledged by all subscribers: sending ack to publisher"),
    MsgID = proplists:get_value(msgid, P),
    send(ack, Pub, MsgID, Qos),
    stop;

checkack('PUBCOMP', [{_EQos=2, Status, _,_,_}], Rest, _) ->
    case Status of
        published ->
            lager:info("~p: provisional response not received before acknowledgement. accepted anyway");
        _         ->
            pass
    end,

    lager:debug("waiting all acknowledgements (~p remaining): ~p", [length(Rest), Rest]),
    acked;

checkack(MsgType, [{EQos, _,_,_,_}], _,_) ->
    lager:warning("invalid ~p message for Qos ~p ", [MsgType, EQos]),
    pass;

checkack(MsgType, Invalid, _, _) ->
    lager:error("smth is going wrong: ~p, mst type= ~p", [Invalid, MsgType]),
    pass.

