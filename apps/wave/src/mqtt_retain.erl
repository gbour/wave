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

-module(mqtt_retain).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_fsm).

%%
%% NOTE: this module is mixing plain funs and fsm behaviour
%%       should it be splitted ?
%% NOTE: gen_fsm is doing same thing as mqtt_lastwill_session (fake publisher session)
%%       should we merge both ?
%%       => mqtt_loopback_session

-include("mqtt_msg.hrl").

% public API
-export([start_link/0, store/1, publish/3]).
% gen_fsm funs
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
% gen_fsm internals
-export([run/2]).

-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    gen_fsm:start_link({local, retain_session}, ?MODULE, [], []).

init([]) ->
    {ok, run, undefined}.

%%
%% PUBLIC API
%%

-spec store(mqtt_msg()) -> pass|retained.
store(#mqtt_msg{type='PUBLISH', retain=0}) ->
    % non-retainable message
    pass;
store(#mqtt_msg{type='PUBLISH', retain=1, qos=Qos, payload=Payload}) ->
    Topic = proplists:get_value(topic, Payload),
    Data  = proplists:get_value(data, Payload),

    store2(Topic, Data, Qos),
    retained.

% empty payload: delete retained message
store2(Topic, <<>>, _) ->
    lager:debug("deleting retained message under ~p", [Topic]),
    wave_db:del(<<"retain:", Topic/binary>>),
    ok;
store2(Topic, Data, Qos) ->
    lager:debug("saving retained message (t= ~p, m=~p)", [Topic, Data]),
    wave_db:set({h, <<"retain:", Topic/binary>>}, #{data => Data, qos => Qos}),
    ok.


-spec publish(mqtt_topic_registry:subscriber(), mqtt_topic(), mqtt_qos()) -> ok.
publish(Subscriber, TopicF, Qos) ->
    % "/foo/+/bar/#" => "/foo/*/bar/*"
    RTopic     = topic2redis(TopicF, <<"retain:">>),
    {ok, Keys} = wave_db:search(RTopic),
    Keys2      = lists:filter(fun(<<"retain:", T/binary>>) -> topicmatch(TopicF, T) end, Keys),

    lager:debug("found retained topics: ~p", Keys2),
    publish2(Keys2, {TopicF, Qos, Subscriber, []}).

publish2(                                        [], _) ->
    ok;
publish2([Match = <<"retain:", Topic/binary>>|Keys], Subscription) ->
    {ok, Values} = wave_db:get({h, Match}),

    Data = proplists:get_value(<<"data">>, Values),
    Qos  = wave_utils:int(proplists:get_value(<<"qos">> , Values, "0")),
    Msg  = #mqtt_msg{type='PUBLISH', qos=Qos, retain=1, payload=[{topic, Topic}, {data, Data}]},

    {ok, MsgWorker} = mqtt_message_worker:start_link(),
    mqtt_message_worker:publish(MsgWorker, retain_session, Msg, [Subscription]), 

    publish2(Keys, Subscription).

% NOTE: specific to redis, needs abstraction
%
topic2redis(<<>>, Acc) ->
    Acc;
topic2redis(<<$#>>, Acc) ->
    <<Acc/binary, $*>>;
topic2redis(<<$+, Rest/binary>>, Acc) ->
    topic2redis(Rest, <<Acc/binary, $*>>);
topic2redis(<<H/utf8, Rest/binary>>, Acc) ->
    topic2redis(Rest, <<Acc/binary, H>>).

topicmatch(<<>>  , <<>>) ->
    true;
topicmatch(<<$#>>,    _) ->
    true;
topicmatch(<<$+>>, <<>>) ->
    true;
topicmatch(<<$+, Rest/binary>>, T= <<$/, _/binary>>) ->
    topicmatch(Rest, T);
topicmatch(TF= <<$+, _/binary>>, <<_/utf8, Rest2/binary>>) ->
    topicmatch(TF, Rest2);
topicmatch(<<H/utf8, Rest/binary>>, <<H/utf8, Rest2/binary>>) ->
    topicmatch(Rest, Rest2);
topicmatch(_, _) ->
    false.


%%
%% INTERNAL STATES
%%

run({provreq, MsgID, Worker}, State) ->
    % do nothing, but sending fake provisional response to mqtt_message_worker
    lager:debug("recv PUBREC, sending fake PUBREL"),
    % NOTE: mqtt_message_worker is only matching MsgID, other fields are useless
    Msg = #mqtt_msg{type='PUBREL', payload=[{msgid, MsgID}]},
    mqtt_message_worker:provisional(response, Worker, self(), Msg),

    {next_state, run, State};

run({ack, _MsgID, _Qos, _Worker}, State) ->
    % do nothing
    lager:debug("recv PUBCOMP/PUBACK (qos= ~p)", [_Qos]),
    {next_state, run, State};

run({'msg-landed', MsgID}, State) ->
    lager:error("msg ~p landed", [MsgID]),
    {next_state, run, State}.

handle_event(_Event, _StateName, StateData) ->
    lager:debug("event ~p", [_StateName]),
    {stop, error, StateData}.

handle_sync_event(_Event, _From, _StateName, StateData) ->
    lager:debug("syncevent ~p", [_StateName]),
    {stop, error, error, StateData}.

handle_info(_Info, _StateName, StateData) ->
    lager:debug("info ~p", [_StateName]),
    {stop, error, StateData}.

terminate(_Reason, _StateName, _State) ->
    lager:info("session terminate with undefined state: ~p", [_Reason]),
    terminate.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


%%
%% PRIVATE FUNS
%%


