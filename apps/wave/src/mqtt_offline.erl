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

%%
%% NOTE: current implementation is really naive
%%       we have to go through the whole list to match each subscriber topic regex
%%       will be really slow w/ hundred thousand subscribers !
%%
-module(mqtt_offline).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").

% public API
-export([register/2, release/3, publish/7]).
-ifdef(DEBUG).
    -export([debug_cleanup/0]).
-endif.
% gen_server internals
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
% internal funs

-record(state, {
    next_msgid    = 1   :: integer(),
    subscriptions = #{} :: map()
 }).

-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    % name = mqtt_offline
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_) ->
    {ok, #state{}}.

%%
%% PUBLIC API
%%

-spec register(binary(), list({binary(), 0|1|2})) -> ok.
register(DeviceID, TopicFs) ->
    gen_server:call(?MODULE, {register, DeviceID, TopicFs}).

-spec release(pid(), binary(), 0|1) -> ok.
release(Session, DeviceID, Clean) ->
    gen_server:cast(?MODULE, {release, Session, DeviceID, Clean}).

%
%NOTE: msg_worker, calling publish(), needs to know the MsgID assigned to
%      MQTT PUBLISH msg sent to peer client, in order to match responses (provreq and/or ack)
-spec publish(pid(), pid(), mqtt_clientid(), {Topic::binary(), TopicF::binary()}, 
              binary(), mqtt_qos(), mqtt_retain()) -> integer().
publish(Pid, From, DeviceID, Topic, Content, Qos, Retain) ->
    gen_server:call(?MODULE, {publish, DeviceID, Topic, Content, Qos, Retain, From}).

-ifdef(DEBUG).
debug_cleanup() ->
    gen_server:call(?MODULE , debug_cleanup).
-endif.

%%
%% INTERNAL CALLBACKS
%%

handle_call(debug_cleanup, _, _State) ->
    lager:warning("clearing offline"),
    {reply, ok, #state{}};

handle_call({register, DeviceID, TopicFs}, _, State=#state{subscriptions=Subs}) ->
    priv_register(DeviceID, TopicFs),

    {reply, ok, State#state{subscriptions=maps:put(DeviceID, TopicFs, Subs)}};

%
%NOTE: Qos here is min(publish qos, subscribe qos), so don't need to store original subscribed qos
%
handle_call({publish, DeviceID, {Topic, TopicF}, Content, Qos, Retain, MsgWorker}, _, 
            State=#state{next_msgid=MsgID}) ->
    %TODO: optimisation: for messages shorted than len(HMAC),
    %      store directly the message in the queue
    MsgHash = wave_utils:hex(crypto:hash(sha256, Content)),
    wave_db:set({s, <<"msg:", MsgHash/binary>>}, Content, [nx]),

    %TODO: store TopicF also ?
    wave_db:push(<<"queue:", DeviceID/binary>>, [Topic, Qos, MsgHash]),
    R3 = wave_db:incr(<<"msg:", MsgHash/binary, ":refcount">>),
    lager:info("~p", [R3]),

    % when qos > 0, message must be acknowledged
    priv_ack(Qos, MsgWorker, MsgID),
    {reply, MsgID, State#state{next_msgid=next_msgid(MsgID)}};
 

handle_call(Event,_,State) ->
    lager:warning("non catched call: ~p", [Event]),
    {reply, ok, State}.


%TODO: operations should be atomic
handle_cast({release, Session, DeviceID, Clean}, State=#state{subscriptions=Subs}) ->
    lager:debug("release: ~p :: ~p", [DeviceID, maps:get(DeviceID, Subs, undefined)]),
   
    % unregistering from topic registry
    lists:foreach(fun({TopicF, Qos}) ->
            mqtt_topic_registry:unsubscribe(TopicF, {?MODULE, publish, self(), DeviceID})
        end, maps:get(DeviceID, Subs, [])
    ),

    % publishing stored messages
    priv_release(Clean, Session, DeviceID, wave_db:range(<<"queue:", DeviceID/binary>>)),
    wave_db:del(<<"queue:", DeviceID/binary>>),

    {noreply, State#state{subscriptions=maps:remove(DeviceID, Subs)}};

handle_cast(Event, State) ->
    lager:warning("non catched cast: ~p", [Event]),
    {noreply, State}.


%NOTE: this is a very special case, where this gen_server receives a gen_fsm event
%      mqtt_offline is acting as a subscriber for a mqtt_message_worker sending qos 2 message
%      msg worker received a PUBREC (see priv_ack) and is sending back a PUBREL through
%      mqtt_session:provisional(response, ...) API
%NOTE: need to set msgid to pair ack msg w/ publish
handle_info({'$gen_event', {provresp, MsgID, MsgWorker}}, State) ->
    mqtt_message_worker:ack(MsgWorker, self(), #mqtt_msg{type='PUBCOMP', payload=[{msgid, MsgID}]}),
    {noreply, State};

handle_info(Info, State) ->
    lager:warning("non catched info: ~p", [Info]),
    {noreply, State}.

terminate(_,_) ->
    lager:error("~p terminated", [?MODULE]),
    ok.

code_change(_, State, _) ->
    {ok, State}.


%%
%% INTERNAL FUNS
%%

-spec priv_register(binary(), list({TopicF::binary(), mqtt_qos()})) -> ok.
priv_register(_       , []) ->
    ok;
priv_register(DeviceID, [{TopicF, Qos} |T]) ->
    mqtt_topic_registry:subscribe(TopicF, Qos, {?MODULE, publish, self(), DeviceID}),
    priv_register(DeviceID, T).


% "unstore" & "emit" messages from db
% - decrement message reference counter
% - if counter is 0, deletes message content
%
-spec priv_release(0|1, pid(), binary(), {ok, list(binary())}) -> ok.
priv_release(Clean, Session, DeviceID, {ok, Msgs}) ->
    lager:debug("queue: ~p", [Msgs]),
    priv_release2(Clean, Session, DeviceID, Msgs).

priv_release2(_,       _,        _, []) ->
    ok;
priv_release2(1, Session, DeviceID, [_,_,MsgID|T]) ->
    {ok, Cnt}  = wave_db:decr(<<"msg:", MsgID/binary, ":refcount">>),
    priv_clean_msg(wave_utils:int(Cnt), MsgID),
    priv_release2(1, Session, DeviceID, T);
priv_release2(0, Session, DeviceID, [Topic, Qos, MsgID |T]) ->
    {ok, Data} = wave_db:get({s, <<"msg:", MsgID/binary>>}),
    {ok, Cnt}  = wave_db:decr(<<"msg:", MsgID/binary, ":refcount">>),
    priv_clean_msg(wave_utils:int(Cnt), MsgID),
    lager:debug("publishing ~p (q ~p):: ~p)", [Topic, Qos, Data]),

    Msg = #mqtt_msg{type='PUBLISH', qos=wave_utils:int(Qos), retain=0, payload=[{topic, Topic}, {data, Data}]},
    %              {TopicF, Qos, Subscriber, Matches}
    %              TopicF never used
    Subscription = {undefined, wave_utils:int(Qos), {mqtt_session, publish, Session, DeviceID}, []},
    {ok, MsgWorker} = supervisor:start_child(wave_msgworkers_sup, []),
    mqtt_message_worker:publish(MsgWorker, offline_session, Msg, [Subscription]),
    
    priv_release2(0, Session, DeviceID, T).

-spec priv_clean_msg(integer(), binary()) -> ok.
priv_clean_msg(  0, MsgID)              ->
    wave_db:del(<<"msg:", MsgID/binary>>),
    wave_db:del(<<"msg:", MsgID/binary, ":refcount">>),
    ok;
priv_clean_msg(Cnt, MsgID) when Cnt < 0 ->
    lager:error("~p msg count is negative", [MsgID]),
    priv_clean_msg(0, MsgID);
priv_clean_msg(  _,     _)              ->
    ok.


-spec priv_ack(0|1|2, pid(), integer()) -> ok.
priv_ack(1, MsgWorker, MsgID) ->
    mqtt_message_worker:ack(MsgWorker, self(), #mqtt_msg{type='PUBACK', payload=[{msgid, MsgID}]});
priv_ack(2, MsgWorker, MsgID) ->
    mqtt_message_worker:provisional(request, MsgWorker, self(), 
                                    #mqtt_msg{type='PUBREC', payload=[{msgid, MsgID}]});
priv_ack(_, _, _) ->
    ok.

% return next message id
% bounded to 2^16 (2 bytes long)
% TODO: MsgID is not sent on MQTT wire, so is not bounded
-spec next_msgid(integer()) -> integer().
next_msgid(MsgID) ->
    if
        MsgID =:= 65535 -> 1;
        true            -> MsgID+1
    end.

