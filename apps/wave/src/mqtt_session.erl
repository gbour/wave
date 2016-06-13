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

-module(mqtt_session).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_fsm).

-include("mqtt_msg.hrl").

-export([start_link/2]).

% gen_fsm
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

-export([handle/2, publish/7, ack/4, provisional/4, is_alive/1, garbage_collect/1, disconnect/2, landed/2]).
-export([initiate/3, initiate/2, connected/2, connected/3]).
%
% role
%   store active sessions (== 1 device connection)
%   session key
%       device id (~ name)
%       ip addr
%       port (facultative => a device may not be able to reuse the same port; think about NAT/proxies)
%
%       /!\ several devices could be serialized in 1 socket ?
%
% storage
%   - in memory (1 session = 1 process)
%   - in db
%       . redis/mnesia/...
%       . serialized, json
%

%
% NOTE: mqtt CONNECT message is mandatory !
%
% new socket
%   decode 1st message
%
% flow
%       open connection -> CONNECT
%
%       on PINGRESQ   : reset ; send PINGRESP
%       on timeout#1  : send PINGREQ ; set timeout#2
%       on PINGRESP   : reset timeout#2 ; set timeout#1
%       on timeout#2  : close connection ; destroy session (or go to idle state)
%
%       on ANY incoming message : reset timeout#1 ; ... ; set timeout #1

-record(session, {
    deviceid               :: binary(),
    topics     = []        :: list({Topic::binary(), Qos::integer()}), % list of subscribed topics
    transport              :: mqtt_ranch_protocol:transport(),
    opts                   :: list({Key::atom(), Val::any()}),
    pingid     = undefined :: undefined,
    keepalive              :: integer(),
    %TODO: use maps instead (test performances improvement)
    %NOTE: not sure msgid is binary
    %       theres a msgid in mqtt_msg() messages
    %       another one generate by mqtt_session (integer)
    inflight   = []        :: list({MsgID::binary(), MsgWorker::pid()}),
    %TODO: initialize with random value
    next_msgid = 1         :: integer(),
    % stores client will settings (topic + message)
    will       = undefined :: undefined|map()
}).
-type session() :: #session{}.

-define(CONNECT_TIMEOUT  , 5000). % ms
-define(DEFAULT_KEEPALIVE, 300).  % secs

-spec start_link(mqtt_ranch_protocol:transport(), list({atom(), any()})) -> {ok, pid()} 
                                                                            | ignore | {error, any()}.
start_link(Transport, Opts) ->
    gen_fsm:start_link(?MODULE, [Transport, Opts], []).

init([Transport, Opts]) ->
    random:seed(?SEED),

    % timeout on socket connection: close socket is no CONNECT message received after timeout
    {ok, initiate, #session{transport=Transport, opts=Opts, next_msgid=random:uniform(65535)}, 
         ?CONNECT_TIMEOUT}.

%
% process message received on socket
% TODO: error cases
-spec handle(pid(), mqtt_msg()) -> {ok, any()}.
handle(Pid, Msg) ->
	Resp = gen_fsm:sync_send_event(Pid, Msg),
	{ok, Resp}.

-spec landed(pid(), binary()) -> ok.
landed(Pid, MsgID) ->
    gen_fsm:send_event(Pid, {'msg-landed', MsgID}).

% peer client disconnection
%
-spec disconnect(pid(), atom()) -> ok.
disconnect(Pid, Reason) ->
    gen_fsm:send_all_state_event(Pid, {disconnect, Reason}).

%
%
% return true if client connection still alive
% (check socket status => kill mqtt_session if socket is in error (closed))
-spec is_alive(pid()) -> true|false.
is_alive(Pid) ->
    case is_process_alive(Pid) of
        true ->
            case gen_fsm:sync_send_event(Pid, ping) of
                ok -> true;
                _  -> false
            end;

        _    ->
            false
    end.

%TODO: unused ?
-spec garbage_collect(pid()) -> ok.
garbage_collect(_Pid) ->
    ok.

%
% a message is published for me
%
-spec publish(pid(), pid(), mqtt_clientid(), {Topic::binary(), TopicF::binary()}, 
              binary(), mqtt_qos(), mqtt_retain()) -> integer().
publish(Pid, From, _DeviceID, Topic, Content, Qos, Retain) ->
    MsgID = gen_fsm:sync_send_event(Pid, {next_msgid, Qos}),
    gen_fsm:send_event(Pid, {publish, MsgID, From, Topic, Content, Qos, Retain}),

    MsgID.

-spec provisional(request|response, pid(), binary(), pid()) -> ok.
provisional(request, Pid, MsgID, From) ->
    gen_fsm:send_event(Pid, {provreq, MsgID, From});
provisional(response, Pid, MsgID, From) ->
    gen_fsm:send_event(Pid, {provresp, MsgID, From}).

-spec ack(pid(), binary(), integer(), pid()) -> ok.
ack(Pid, MsgID, Qos, From) ->
    gen_fsm:send_event(Pid, {ack, MsgID, Qos, From}).

%% STATES

initiate(#mqtt_msg{type='CONNECT', payload=P}, _, StateData=#session{opts=Opts}) ->
	%gen_fsm:start_timer(5000, timeout1),
	%lager:info("timeout set"),
    DeviceID = proplists:get_value(clientid, P),
    %lager:info("received CONNECT - deviceid = <<\"~ts\">>", [DeviceID]),

    User     = proplists:get_value(username, P),
    Pwd      = proplists:get_value(password, P),
    Ka       = case proplists:get_value(keepalive, P, ?DEFAULT_KEEPALIVE) of
        0   -> infinity;
        _Ka -> round(_Ka * 1000 * 1.5)
    end,
    Clean    = proplists:get_value(clean, P, 1),

    % load device settings from db
    Settings = case wave_redis:device({deviceid, DeviceID}) of
        {error, Err} ->
            lager:info("~p settings: ~p", [DeviceID, Err]),
            [];

        {ok, Setts} ->
            Setts
    end,

    {MSecs, Secs, _} = os:timestamp(),
    Vals             = [{state,connecting},{username,User},{ts, MSecs*1000000+Secs},{clean, Clean} | Opts],

    Res1 = case {Clean, DeviceID} of
        {0, <<>>} ->
            % 0-length DeviceID is forbidden when clean-session unset
            lager:debug("invalid empty client-id with Clean Session 0"),
            {error, wrong_id};

        {1, <<>>} ->
            %NOTE: if DeviceID is empty, we do not register process
            %      (we could have an infinite number of processes with empty deviceid)
            %TODO: should we generate (optionally) a random clientid ?
            ok;

        % non-empty deviceid
        {_, DeviceID} ->
            % register process with deviceid as key
            % returns 'ok' if deviceid not used, {error, taken} if deviceid already used

            %NOTE: registration is AUTOMATICALLY removed when process ends

            %TODO: optionaly, if deviceid already defined, replace instead of reject ?
            %      make it configurable (globally/per device) -> optionaly replace old device
            %      (and disconnect old device)
            %      /!\ there may be a flickering risk of both devices retries to reconnect
            %      alternativelly
            %TODO: should be moved AFTER auth check, so we don't block another client w/ same id
            %      to connect
            syn:register(DeviceID, self())
    end,

    Res2 = case Res1 of
        ok ->
            wave_auth:check(application:get_env(wave, auth_required), DeviceID, {User, Pwd}, Settings);

        Err1 -> Err1
    end,

    {Retcode, SessionPresent, Topics} = case Res2 of
        {ok, _} ->
            {Exists, Topics2} = offline_unstore(DeviceID, Clean),
            lager:debug("restored topics: ~p", [Topics2]),
            {0, Exists, Topics2};

        {error, taken}   ->
            {2, false, []};
        {error, wrong_id} ->
            {2, false, []};
        {error, bad_credentials} ->
            {4, false, []} % not authorized
    end,

    wave_event_router:route(<<"$/mqtt/CONNECT">>, [{deviceid, DeviceID}, {retcode, Retcode}]),

    % update device status in redis
    lager:debug("~p CONNECT status: ~p", [DeviceID, Res2]),
    Resp = #mqtt_msg{type='CONNACK', payload=[{session, wave_utils:int(SessionPresent)},{retcode, Retcode}]},

    case Retcode of
        0 ->
            % remove offline subscriptions, publish stored messages
            mqtt_offline:release(self(), DeviceID, Clean),

            Will = proplists:get_value(will, P),
            {reply, Resp, connected, StateData#session{deviceid=DeviceID, keepalive=Ka, opts=Vals, 
                                                       topics=Topics, will=Will}, Ka};

        _ ->
            % because we need to close connection after having sent non-zero CONNACK
            {stop, normal, {disconnect, Resp}, undefined}
    end;

initiate(#mqtt_msg{type=Type}, _, _StateData=#session{transport={Callback,Transport,Sock}}) ->
    lager:info("first packet MUST be CONNECT (is ~p)", [Type]),
    Callback:close(Transport, Sock),
    {stop, normal, disconnect, undefined};
% TODO: is it ever executed ?
initiate({timeout, _, timeout1}, _, _StateData) ->
	lager:info("initiate timeout"),
	{stop, disconnect, []}.

initiate(timeout, StateData=#session{transport={Callback,Transport,Sock}}) ->
    lager:notice("initiate:: timeout ~p", [StateData]),
    Callback:close(Transport, Sock),
    %TODO: disconnect reason is throwing a log error w/ CRASH REPORT
    %      which reason should we use
    {stop, disconnect, StateData}.

connected(#mqtt_msg{type='DISCONNECT'}, _, StateData) ->
    {stop, normal, disconnect, StateData#session{will=undefined}};

connected(#mqtt_msg{type='PINGREQ'}, _, StateData=#session{keepalive=Ka}) ->
    Resp = #mqtt_msg{type='PINGRESP'},
    {reply, Resp, connected, StateData, Ka};

connected(#mqtt_msg{type='PINGRESP'}, _, StateData=#session{pingid=_Ref,keepalive=Ka}) ->
    %lager:info("received PINGRESP"),
    %BUG? timer never started
    %gen_fsm:cancel_timer(Ref),
    {reply, undefined, connected, StateData#session{pingid=undefined}, Ka};


connected(Msg=#mqtt_msg{type='PUBLISH', qos=0, payload=P}, _,
          StateData=#session{deviceid=_DeviceID,keepalive=Ka}) ->

    Topic = <<Prefix:1/binary, _/binary>> = proplists:get_value(topic, P),
    case Prefix of
        <<"$">> ->
            lager:notice("~p: publishing to '$' prefixed topic is forbidden", [Topic]),
            {stop, normal, disconnect, StateData};

        _       ->
            % only if retain=1
            mqtt_retain:store(Msg),

            %TODO: save message in DB
            %      pass MsgID to message_worker
            {ok, MsgWorker} = supervisor:start_child(wave_msgworkers_sup, []),
            mqtt_message_worker:publish(MsgWorker, self(), Msg#mqtt_msg{retain=0}), % async

            {reply, undefined, connected, StateData, Ka}
    end;

% qos > 0
connected(Msg=#mqtt_msg{type='PUBLISH', payload=P, dup=Dup}, _,
          StateData=#session{deviceid=_DeviceID,keepalive=Ka,inflight=Inflight}) ->

    Topic = <<Prefix:1/binary, _/binary>> = proplists:get_value(topic, P),
    %TODO: save message in DB
    MsgID     = proplists:get_value(msgid, P),
    case {Prefix, proplists:get_value(MsgID, Inflight)} of
        % $... topic
        {<<"$">>, _}   ->
            lager:notice("~p: publishing to '$' prefixed topic is forbidden", [Topic]),
            {stop, normal, disconnect, StateData};

        {_, undefined} ->
            % only if retain=1
            mqtt_retain:store(Msg),
            %      pass MsgID to message_worker
            {ok, MsgWorker} = supervisor:start_child(wave_msgworkers_sup, []),
            mqtt_message_worker:publish(MsgWorker, self(), Msg#mqtt_msg{retain=0}), % async
            
            {reply, undefined, connected, StateData#session{inflight=[{MsgID, MsgWorker} | Inflight]}, Ka};

        % message is already inflight
        _ ->
            lager:notice("message %~p already inflight (dup=~p). Ignored", [MsgID, Dup]),
            {reply, undefined, connected, StateData, Ka}
    end;


%TODO: factorize PUBACK/PUBREC/PUBREL/PUBCOMP code
connected(Msg=#mqtt_msg{type='PUBACK', payload=P}, _, StateData=#session{keepalive=Ka,inflight=Inflight}) ->
    %TODO: find matching
    MsgID  = proplists:get_value(msgid, P),
    %Worker = gproc:where({n,l,{msgworker, MsgID}}),
    case proplists:get_value(MsgID, Inflight) of
        % invalid msgid: message ignored
        undefined ->
            lager:notice("PUBACK: inflight '~p' MsgID not found", [MsgID]);

        Worker ->
            lager:debug("received PUBACK (msgid= ~p): forwarded to ~p message worker", [MsgID, Worker]),
            mqtt_message_worker:ack(Worker, self(), Msg)
    end,

    {reply, undefined, connected, StateData, Ka};

connected(Msg=#mqtt_msg{type='PUBREC', payload=P}, _, StateData=#session{keepalive=Ka,inflight=Inflight}) ->
    MsgID  = proplists:get_value(msgid, P),

    case proplists:get_value(MsgID, Inflight) of
        % invalid msgid: message ignored
        undefined ->
            lager:notice("PUBREC: inflight '~p' MsgID not found", [MsgID]);

        Worker ->
            lager:debug("received PUBREC (msgid= ~p): forwarded to ~p message worker", [MsgID, Worker]),
            mqtt_message_worker:provisional(request, Worker, self(), Msg)
    end,

    {reply, undefined, connected, StateData, Ka};

connected(Msg=#mqtt_msg{type='PUBREL', payload=P}, _, StateData=#session{keepalive=Ka,inflight=Inflight}) ->
    MsgID  = proplists:get_value(msgid, P),

    case proplists:get_value(MsgID, Inflight) of
        % invalid msgid: message ignored
        undefined ->
            lager:notice("PUBREL: inflight '~p' MsgID not found", [MsgID]);

        Worker ->
            lager:debug("received PUBREL (msgid= ~p): forwarded to ~p message worker", [MsgID, Worker]),
            mqtt_message_worker:provisional(response, Worker, self(), Msg)
    end,

    {reply, undefined, connected, StateData, Ka};

connected(Msg=#mqtt_msg{type='PUBCOMP', payload=P}, _, StateData=#session{keepalive=Ka,inflight=Inflight}) ->
    MsgID  = proplists:get_value(msgid, P),

    case proplists:get_value(MsgID, Inflight) of
        % invalid msgid: message ignored
        undefined ->
            lager:notice("PUBCOMP: inflight '~p' MsgID not found", [MsgID]);

        Worker ->
            lager:debug("received PUBCOMP (msgid= ~p): forwarded to ~p message worker", [MsgID, Worker]),
            mqtt_message_worker:ack(Worker, self(), Msg)
    end,

    {reply, undefined, connected, StateData, Ka};

%TODO: prevent subscribing multiple times to the same topic
connected(#mqtt_msg{type='SUBSCRIBE', payload=P}, _, 
          StateData=#session{deviceid=DeviceID, topics=T, keepalive=Ka}) ->
	MsgId  = proplists:get_value(msgid, P),
    Topics = proplists:get_value(topics, P),

    % subscribe to all listed topics (creating it if it don't exists)
    EQoses = lists:map(fun({Topic, TQos}) ->
            mqtt_topic_registry:subscribe(Topic, TQos, {?MODULE, publish, self(), DeviceID}),
            S = {?MODULE, publish, self(), DeviceID},
            mqtt_retain:publish(S, Topic, TQos),

            TQos
        end, Topics
    ),

    Resp  = #mqtt_msg{type='SUBACK', payload=[{msgid,MsgId},{qos, EQoses}]},

    {reply, Resp, connected, StateData#session{topics=Topics++T}, Ka};

connected(#mqtt_msg{type='UNSUBSCRIBE', payload=P}, _, 
          StateData=#session{deviceid=DeviceID, topics=OldTopics, keepalive=Ka}) ->
	MsgId  = proplists:get_value(msgid, P),
    Topics = proplists:get_value(topics, P),

    % subscribe to all listed topics (creating it if it don't exists)
    lists:foreach(fun(T) ->
            mqtt_topic_registry:unsubscribe(T, {?MODULE,publish,self(), DeviceID})
        end,
        Topics
    ),

    NewTopics = lists:subtract(OldTopics, Topics),
	Resp  = #mqtt_msg{type='UNSUBACK', payload=[{msgid,MsgId}]},

    {reply, Resp, connected, StateData#session{topics=NewTopics}, Ka};


connected(ping, _, StateData=#session{transport={Callback,Transport,Socket}}) ->
    Ret = Callback:crlfping(Transport, Socket),
    lager:debug("sending CRLF ping= ~p", [Ret]),
    case Ret of
        {error, _Err} ->
            {stop, normal, disconnect, StateData};

        ok ->
            {reply, ok, connected, StateData, 5000}
    end;

connected({next_msgid, _Qos=0}, _, State) ->
    {reply, 0, connected, State};
connected({next_msgid, _}, _, State=#session{next_msgid=MsgID}) ->
    {reply, MsgID, connected, State#session{next_msgid=next_msgid(MsgID)}};

connected(Event, _, State) ->
    lager:error("unknown event: ~p", [Event]),
    {stop, error, disconnect, State}.

connected({timeout, _, timeout1}, _StateData) ->
	lager:notice("timeout after connection"),
	{stop, disconnect, []};

% ASYNC

% publish message with QoS 0 (fire n forget)
% TODO: match DeviceID
connected({publish, _, _, {Topic, _}, Content, Qos=0, Retain},
          StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka}) ->
    lager:debug("send PUBLISH(topic=~p, qos=~p)", [Topic, Qos]),

    Msg   = #mqtt_msg{type='PUBLISH', qos=Qos, retain=Retain, payload=[{topic,Topic}, {content, Content}]},
    State = Callback:send(Transport, Socket, Msg),

    case State of
        {error, _Err} -> {stop, normal};
        ok            -> {next_state, connected, StateData, Ka}
    end;

% QoS 1 or 2
% NOTE: MsgID as already been impl. in {next_msgid, Qos} handler
connected({publish, MsgID, From, {Topic,_}, Content, Qos, Retain},
          StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka,inflight=Inflight}) ->
    lager:debug("send PUBLISH(topic=~p, msgid=~p, qos=~p)", [Topic, MsgID, Qos]),

    Msg   = #mqtt_msg{type='PUBLISH', qos=Qos, retain=Retain,
                      payload=[{topic,Topic}, {msgid, MsgID}, {content, Content}]},
    State = Callback:send(Transport, Socket, Msg),

    case State of
        {error, _Err} -> {stop, normal};
        ok            -> {next_state, connected, StateData#session{inflight=[{MsgID, From}|Inflight]}, Ka}
    end;

%
% send provisional request PUBREC (QoS 2)
% (to publisher)
%
connected({provreq, MsgID, _From}, StateData=#session{transport={Clb,Transport,Sock},keepalive=Ka}) ->
    lager:debug("send PUBREC"),

    Msg = #mqtt_msg{type='PUBREC', qos=0, payload=[{msgid, MsgID}]},
    case Clb:send(Transport, Sock, Msg) of
        {error, _} -> {stop, normal};
        ok         -> {next_state, connected, StateData, Ka}
    end;

%
% send provisional response - PUBREL (QoS 2)
% (to subscriber)
%
connected({provresp, MsgID, _From}, StateData=#session{transport={Clb,Transport,Sock},keepalive=Ka}) ->
    lager:debug("send PUBREL"),

    Msg = #mqtt_msg{type='PUBREL', qos=1, payload=[{msgid, MsgID}]},
    case Clb:send(Transport, Sock, Msg) of
        {error, _} -> {stop, normal};
        ok         -> {next_state, connected, StateData, Ka}
    end;

%
% sending PUBACK acknowledgement (QOS=1)
%
connected({ack, MsgID, _Qos=1, _}, StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka}) ->
    lager:debug("send PUBACK"),

    Msg = #mqtt_msg{type='PUBACK', qos=0, payload=[{msgid, MsgID}]},
    case Callback:send(Transport, Socket, Msg) of
        {error, _} -> {stop, normal};
        ok         -> {next_state, connected, StateData, Ka}
    end;

% PUBCOMP (QOS=2)
connected({ack, MsgID, _Qos=2, _}, StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka}) ->
    lager:debug("send PUBCOMP"),

    Msg = #mqtt_msg{type='PUBCOMP', qos=0, payload=[{msgid, MsgID}]},
    case Callback:send(Transport, Socket, Msg) of
        {error, _} -> {stop, normal};
        ok         -> {next_state, connected, StateData, Ka}
    end;

%
%TODO: what if peer disconnected between ack received and message landed ?
%      do a pre-check when message received (qos1 = PUBACK, qos2 = PUBCOMP) ? 
connected({'msg-landed', MsgID}, StateData=#session{keepalive=Ka, inflight=Inflight,
                                                    deviceid=DeviceID}) ->
    lager:debug("#~p message-id is no more in-flight", [MsgID]),
    {next_state, connected, StateData#session{inflight=proplists:delete(MsgID, Inflight)}, Ka};

% KeepAlive was set and no PINREG (or any other ctrl packet) received in the interval
connected(timeout, StateData=#session{transport={Callback,Transport,Socket}}) ->
    lager:notice("KEEPALIVE timeout expired"),
    % sending ping
    %Callback:ping(Transport, Socket),
    %Ref = gen_fsm:send_event_after(1000, ping_timeout),
    _Ref=0,

    Callback:close(Transport, Socket),
    %{next_state, connected, StateData#session{pingid=Ref}};
    {stop, normal, StateData};

%TODO: ever executed
connected(ping_timeout, _StateData=#session{transport={Callback,Transport,Socket}}) ->
    lager:notice("PING timeout"),
    Callback:close(Transport, Socket),
    {stop, normal, undefined}.



handle_event({disconnect, Reason}, _StateName, StateData) ->
    lager:notice("session terminated. cause: ~p", [Reason]),
    {stop, normal, StateData};

handle_event(_Event, _StateName, StateData) ->
	lager:error("event ~p", [_StateName]),
    {stop, error, StateData}.


handle_sync_event(_Event, _From, _StateName, StateData) ->
	lager:error("syncevent ~p", [_StateName]),
    {stop, error, error, StateData}.

handle_info(_Info, _StateName, StateData) ->
	lager:error("info ~p", [_StateName]),
    {stop, error, StateData}.

%
% Executed when either
%   - clients ask disconnection (received DISCONNECT message)
%   - network issue (socket closed, tcp keepalive timeout)
%   - gen_fsm/erlang issue (gen_fsm is terminated)
%
%
terminate(_Reason, _StateName, undefined) ->
    lager:info("session terminate with undefined state: ~p", [_Reason]),
    terminate;

%NOTE: process/deviceid automatically unregistered from syn when process terminate
terminate(_Reason, StateName, StateData=#session{deviceid=DeviceID, topics=T, inflight=Inflight, opts=Opts}) ->
    lager:debug("~n * deviceid : ~p~n * reason   : ~p~n * stateName: ~p~n * stateData: ~p", 
                [DeviceID, _Reason, StateName, StateData]),
    
    if 
        length(Inflight) > 0 -> lager:notice("~p: remaining inflight messages: ~p", [DeviceID, Inflight]);
        true                 -> ok
    end,


    %TODO: if unsubscribe THEN subscribe in offline, there is a small interval of time
    %      where topic is not registered
    %      instead, update target process in topic registry
    lists:foreach(fun({Topic, _Qos}) ->
            mqtt_topic_registry:unsubscribe(Topic, {?MODULE, publish, self(), DeviceID})
        end,
        T
    ),

    % saving topics if clean unset
    offline_store(DeviceID, proplists:get_value(clean, Opts, 1), T),
    send_last_will(StateData),
    terminate.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


%%
%% PRIVATE FUNS
%%

% return next message id
% bounded to 2^16 (2 bytes long)
%
%TODO: improve algorithm (MsgID =:= 65535)
-spec next_msgid(integer()) -> integer().
next_msgid(MsgID) ->
    if
        MsgID+1 > 65535 -> 1;
        true         -> MsgID+1
    end.


% send Client last will testament if exists
%
-spec send_last_will(session()) -> ok.
send_last_will(#session{will=undefined}) ->
    % do nothing
    ok;
send_last_will(#session{will=#{topic := Topic, message := Data, qos := Qos, retain := Retain}}) ->
    lager:debug("sending last will"),

    Msg = #mqtt_msg{type='PUBLISH', qos=Qos, retain=Retain, payload=[{msgid, -1},{topic, Topic}, {data, Data}]},
    {ok, MsgWorker} = supervisor:start_child(wave_msgworkers_sup, []),
    mqtt_message_worker:publish(MsgWorker, lastwill_session, Msg), % async

    ok.


-spec offline_store(DeviceID::binary(), CleanSession::0|1, Topics::list({binary(), 0|1|2})) -> ok.
offline_store(_, 1, _) ->
    ok;
%offline_store(_, 0, []) ->
%    ok;
offline_store(DeviceID, 0, Subscriptions) ->
    lager:debug("storing offline subscriptions: ~p", [Subscriptions]),
    wave_db:set({s, <<"session:", DeviceID/binary>>}, 1),

    Flatten = offline_store2(Subscriptions, []),
    wave_db:push(["topics:", DeviceID], Flatten),

    mqtt_offline:register(DeviceID, Subscriptions),
    ok.

% serialize topics
offline_store2([], Acc) ->
    Acc;
offline_store2([{Topic, Qos}| T], Acc) ->
    offline_store2(T, [Topic, Qos| Acc]).


-spec offline_unstore(DeviceID::binary(), CleanSession::0|1) -> {boolean(), list({binary(), 0|1|2})}.
offline_unstore(DeviceID, 1) ->
    lager:debug("cleansession unset, deleting saved topics"),
    wave_db:del(<<"session:", DeviceID/binary>>),
    wave_db:del(<<"topics:", DeviceID/binary>>),
    {false, []};
offline_unstore(DeviceID, 0) ->
    Exists = case wave_db:exists(<<"session:", DeviceID/binary>>) of
        {ok, <<"0">>} -> false;
        {ok, <<"1">>} -> 
            wave_db:del(<<"session:", DeviceID/binary>>),
            true
    end,

    {Exists, offline_unstore2(Exists, DeviceID)}.

offline_unstore2(false, _) ->
    [];
offline_unstore2(true , DeviceID) -> 
    {ok, FlatTopics} = wave_db:range(<<"topics:", DeviceID/binary>>),
    wave_db:del(<<"topics:", DeviceID/binary>>),

    offline_unstore3(DeviceID, FlatTopics, []).

% unserialize topics
offline_unstore3(_       , []             , Acc) ->
    Acc;
offline_unstore3(DeviceID, [Topic, Qos| T], Acc) ->
    Qos2 = wave_utils:int(Qos),
    % register topic for this session
    mqtt_topic_registry:subscribe(Topic, Qos2, {?MODULE,publish,self(),DeviceID}),

    offline_unstore3(DeviceID, T, [{Topic, Qos2} | Acc]).

