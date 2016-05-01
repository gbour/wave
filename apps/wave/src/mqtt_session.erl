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

-export([handle/2, publish/6, ack/4, provisional/4, is_alive/1, garbage_collect/1, disconnect/2, landed/2]).
-export([initiate/3, connected/2, connected/3]).
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

%%
-spec handle(pid(), mqtt_msg()) -> {ok, any()}.
handle(Pid, Msg) ->
	Resp = gen_fsm:sync_send_event(Pid, Msg),
	lager:info("return: ~p", [Resp]),

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
-spec publish(pid(), pid(), binary(), binary(), mqtt_qos(), mqtt_retain()) -> ok.
publish(Pid, From, Topic, Content, Qos, Retain) ->
    gen_fsm:send_event(Pid, {publish, From, Topic, Content, Qos, Retain}).

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
    lager:info("received CONNECT - deviceid = <<\"~ts\">>", [DeviceID]),

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
            lager:info("~p: failed to get settings (~p)", [DeviceID, Err]),
            [];

        {ok, Setts} ->
            Setts
    end,

    {MSecs, Secs, _} = os:timestamp(),
    Vals             = [{state,connecting},{username,User},{ts, MSecs*1000000+Secs},{clean, Clean} | Opts],

    Res = case wave_redis:connect(DeviceID, Vals) of
        % device already connected
        {error, exists} ->
            %TODO: reject connections
            %TODO: make it configurable (globally/per device) -> optionaly replace old device
            %      (and disconnect old device)
            %      /!\ there may be a flickering risk of both devices retries to reconnect
            %      alternativelly
            {error, exists};

        _ ->
            wave_auth:check(application:get_env(wave, auth_required), DeviceID, {User, Pwd}, Settings)
    end,

    {Retcode, Topics} = case Res of
        {ok, _} ->
            % if connection is successful, we need to check if we have offline messages
            Topics1 = mqtt_offline:recover(DeviceID),
            lager:info("offline topics: ~p", [Topics1]),
            [ mqtt_topic_registry:subscribe(Topic, Qos, {?MODULE,publish,self()}) || {Topic,Qos} <- Topics1 ],
            % flush is async
            case Topics1 of
                [] -> ok;
                _  ->
                    mqtt_offline:flush(DeviceID, {?MODULE,publish,self()})
            end,

            Topics2 = wave_redis:topic(DeviceID, 0),
            lager:debug("qos 0 saved topics= ~p", [Topics2]),
            lists:foreach(fun({T,_}) -> mqtt_topic_registry:subscribe(T, 0, {?MODULE,publish,self()}) end, Topics2),

            {0, Topics1++Topics2};

        {error, exists}   ->
            {2, []};
        {error, wrong_id} ->
            {2, []};
        {error, bad_credentials} ->
            {4, []} % not authorized
    end,

    wave_event_router:route(<<"$/mqtt/CONNECT">>, [{deviceid, DeviceID}, {retcode, Retcode}]),

    % update device status in redis
    lager:debug("RES= ~p", [Res]),
    NextState = case Res of
        {error, exists} -> initiate;
        {error, _}      ->
            wave_redis:update(DeviceID, state, disconnected),
            initiate;

        _               ->
            wave_redis:update(DeviceID, state, connected),
            connected
    end,

    Resp = #mqtt_msg{type='CONNACK', payload=[{session,0},{retcode, Retcode}]},

    case Retcode of
        0 ->
            Will = proplists:get_value(will, P),
            {reply, Resp, NextState,
                StateData#session{deviceid=DeviceID, keepalive=Ka, opts=Vals, topics=Topics, will=Will}, Ka
            };

        _ ->
            % because we need to close connection after having sent non-zero CONNACK
            {stop, normal, {disconnect, Resp}, undefined}
    end;

initiate(#mqtt_msg{type=Type}, _, _StateData=#session{transport={Callback,Transport,Sock}}) ->
    lager:info("first packet MUST be CONNECT (is ~p)", [Type]),
    Callback:close(Transport, Sock),
    {stop, normal, disconnect, undefined};
initiate({timeout, _, timeout1}, _, _StateData) ->
	lager:info("initiate timeout"),
	{stop, disconnect, []}.

initiate(timeout, StateData) ->
    lager:error("initiate:: timeout"),
    {stop, disconnect, StateData}.

connected(#mqtt_msg{type='DISCONNECT'}, _, StateData) ->
    {stop, normal, disconnect, StateData#session{will=undefined}};

connected(#mqtt_msg{type='PINGREQ'}, _, StateData=#session{keepalive=Ka}) ->
    Resp = #mqtt_msg{type='PINGRESP'},
    {reply, Resp, connected, StateData, Ka};

connected(#mqtt_msg{type='PINGRESP'}, _, StateData=#session{pingid=_Ref,keepalive=Ka}) ->
    lager:info("received PINGRESP"),
    %BUG? timer never started
    %gen_fsm:cancel_timer(Ref),
    {reply, undefined, connected, StateData#session{pingid=undefined}, Ka};


connected(Msg=#mqtt_msg{type='PUBLISH', qos=0}, _, StateData=#session{deviceid=_DeviceID,keepalive=Ka}) ->
    % only if retain=1
    mqtt_retain:store(Msg),

    %TODO: save message in DB
    %      pass MsgID to message_worker
    {ok, MsgWorker} = mqtt_message_worker:start_link(),
    mqtt_message_worker:publish(MsgWorker, self(), Msg#mqtt_msg{retain=0}), % async

    {reply, undefined, connected, StateData, Ka};

% qos > 0
connected(Msg=#mqtt_msg{type='PUBLISH', payload=P}, _,
          StateData=#session{deviceid=_DeviceID,keepalive=Ka,inflight=Inflight}) ->
    % only if retain=1
    mqtt_retain:store(Msg),
    %TODO: save message in DB
    MsgID = proplists:get_value(msgid, P),
    %      pass MsgID to message_worker
    {ok, MsgWorker} = mqtt_message_worker:start_link(),
    mqtt_message_worker:publish(MsgWorker, self(), Msg#mqtt_msg{retain=0}), % async

    {reply, undefined, connected, StateData#session{inflight=[{MsgID,MsgWorker}|Inflight]}, Ka};

connected(Msg=#mqtt_msg{type='PUBACK', payload=P}, _, StateData=#session{keepalive=Ka,inflight=Inflight}) ->
    %TODO: find matching
    MsgID  = proplists:get_value(msgid, P),
    %Worker = gproc:where({n,l,{msgworker, MsgID}}),
    case proplists:get_value(MsgID, Inflight) of
        % invalid msgid: message ignored
        undefined ->
            lager:warning("PUBACK: unmatched '~p' MsgID", [MsgID]);

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
            lager:warning("PUBREC: unmatched '~p' MsgID", [MsgID]);

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
            lager:warning("PUBREL: unmatched '~p' MsgID", [MsgID]);

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
            lager:warning("PUBCOMP: unmatched '~p' MsgID", [MsgID]);

        Worker ->
            lager:debug("received PUBCOMP (msgid= ~p): forwarded to ~p message worker", [MsgID, Worker]),
            mqtt_message_worker:ack(Worker, self(), Msg)
    end,

    {reply, undefined, connected, StateData, Ka};

%TODO: prevent subscribing multiple times to the same topic
connected(#mqtt_msg{type='SUBSCRIBE', payload=P}, _, StateData=#session{topics=T, keepalive=Ka}) ->
	MsgId  = proplists:get_value(msgid, P),
    Topics = proplists:get_value(topics, P),

    % subscribe to all listed topics (creating it if it don't exists)
    EQoses = lists:map(fun({Topic, TQos}) ->
            mqtt_topic_registry:subscribe(Topic, TQos, {?MODULE, publish, self()}),
            S = {?MODULE, publish, self()},
            mqtt_retain:publish(S, Topic, TQos),

            TQos
        end, Topics
    ),

    Resp  = #mqtt_msg{type='SUBACK', payload=[{msgid,MsgId},{qos, EQoses}]},

    lager:info("Ka=~p", [Ka]),
    {reply, Resp, connected, StateData#session{topics=Topics++T}, Ka};

connected(#mqtt_msg{type='UNSUBSCRIBE', payload=P}, _, StateData=#session{topics=OldTopics, keepalive=Ka}) ->
	MsgId  = proplists:get_value(msgid, P),
    Topics = proplists:get_value(topics, P),

    % subscribe to all listed topics (creating it if it don't exists)
    lists:foreach(fun(T) ->
            mqtt_topic_registry:unsubscribe(T, {?MODULE,publish,self()})
        end,
        Topics
    ),

    NewTopics = lists:subtract(OldTopics, Topics),
	Resp  = #mqtt_msg{type='UNSUBACK', payload=[{msgid,MsgId}]},

    lager:info("Ka=~p ~p", [Ka, OldTopics]),
    {reply, Resp, connected, StateData#session{topics=NewTopics}, Ka};


connected(ping, _, StateData=#session{transport={Callback,Transport,Socket}}) ->
    Ret = Callback:crlfping(Transport, Socket),
    lager:info("send CRLF ping= ~p", [Ret]),
    case Ret of
        {error, _Err} ->
            {stop, normal, disconnect, StateData};

        ok ->
            {reply, ok, connected, StateData, 5000}
    end;

connected(_,_, _StateData) ->
    {stop, normal, disconnect, undefined}.

connected({timeout, _, timeout1}, _StateData) ->
	lager:info("timeout after connection"),
	{stop, disconnect, []};

% ASYNC

% publish message with QoS 0 (fire n forget)
connected({publish, _, {Topic,_}, Content, Qos=0, Retain},
          StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka}) ->
    lager:debug(">PUBLISH ~p (qos ~p) to subscr", [Topic, Qos]),

    Msg   = #mqtt_msg{type='PUBLISH', qos=Qos, retain=Retain, payload=[{topic,Topic}, {content, Content}]},
    State = Callback:send(Transport, Socket, Msg),
    lager:info("publish msg status= ~p", [State]),

    case State of
        {error, _Err} ->
            {stop, normal};

        ok ->
            lager:debug("OK, continue"),
            {next_state, connected, StateData, Ka}
    end;

% QoS 1 or 2
connected({publish, From, {Topic,_}, Content, Qos, Retain},
          StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka,inflight=Inflight,next_msgid=MsgID}) ->
    lager:debug("~p: publish message to subscriber with QoS=~p (msgid= ~p)", [self(), Qos, MsgID]),

    Msg   = #mqtt_msg{type='PUBLISH', qos=Qos, retain=Retain,
                      payload=[{topic,Topic}, {msgid, MsgID}, {content, Content}]},
    State = Callback:send(Transport, Socket, Msg),
    lager:info("publish msg status= ~p", [State]),

    case State of
        {error, _Err} ->
            {stop, normal};

        ok ->
            lager:debug("OK, continue"),
            {next_state, connected,
             StateData#session{next_msgid=next_msgid(MsgID),inflight=[{MsgID, From}|Inflight]}, Ka
            }
    end;

%
% send provisional request PUBREC (QoS 2)
% (to publisher)
%
connected({provreq, MsgID, _From}, StateData=#session{transport={Clb,Transport,Sock},keepalive=Ka}) ->
    lager:debug("sending PUBREC"),
    Msg = #mqtt_msg{type='PUBREC', qos=0, payload=[{msgid, MsgID}]},
    case Clb:send(Transport, Sock, Msg) of
        {error, _} ->
            {stop, normal};

        ok ->
            {next_state, connected, StateData, Ka}
    end;

%
% send provisional response - PUBREL (QoS 2)
% (to subscriber)
%
connected({provresp, MsgID, _From}, StateData=#session{transport={Clb,Transport,Sock},keepalive=Ka}) ->
    lager:debug("sending PUBREL"),
    Msg = #mqtt_msg{type='PUBREL', qos=1, payload=[{msgid, MsgID}]},
    case Clb:send(Transport, Sock, Msg) of
        {error, _} ->
            {stop, normal};

        ok ->
            {next_state, connected, StateData, Ka}
    end;

%
% sending PUBACK acknowledgement (QOS=1)
%
connected({ack, MsgID, _Qos=1, _}, StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka}) ->
    lager:debug("sending PUBACK"),
    Msg = #mqtt_msg{type='PUBACK', qos=0, payload=[{msgid, MsgID}]},
    case Callback:send(Transport, Socket, Msg) of
        {error, _} ->
            {stop, normal};

        ok ->
            {next_state, connected, StateData, Ka}
    end;
% PUBCOMP (QOS=2)
connected({ack, MsgID, _Qos=2, _}, StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka}) ->
    lager:debug("sending PUBCOMP"),
    Msg = #mqtt_msg{type='PUBCOMP', qos=0, payload=[{msgid, MsgID}]},
    case Callback:send(Transport, Socket, Msg) of
        {error, _} ->
            {stop, normal};

        ok ->
            {next_state, connected, StateData, Ka}
    end;

%
%TODO: what if peer disconnected between ack received and message landed ?
%      do a pre-check when message received (qos1 = PUBACK, qos2 = PUBCOMP) ? 
connected({'msg-landed', MsgID}, StateData=#session{keepalive=Ka, inflight=Inflight}) ->
    lager:debug("#~p message-id is no more in-flight", [MsgID]),
    {next_state, connected, StateData#session{inflight=proplists:delete(MsgID, Inflight)}, Ka};

% KeepAlive was set and no PINREG (or any other ctrl packet) received in the interval
connected(timeout, StateData=#session{transport={Callback,Transport,Socket}}) ->
    lager:info("KEEPALIVE timeout expired"),
    % sending ping
    %Callback:ping(Transport, Socket),
    %Ref = gen_fsm:send_event_after(1000, ping_timeout),
    _Ref=0,

    Callback:close(Transport, Socket),
    %{next_state, connected, StateData#session{pingid=Ref}};
    {stop, normal, StateData};

connected(ping_timeout, _StateData=#session{transport={Callback,Transport,Socket}}) ->
    Callback:close(Transport, Socket),
    {stop, normal, undefined}.



handle_event({disconnect, Reason}, _StateName, StateData) ->
    lager:info("session terminated. cause: ~p", [Reason]),
    {stop, normal, StateData};

handle_event(_Event, _StateName, StateData) ->
	lager:debug("event ~p", [_StateName]),
    {stop, error, StateData}.


handle_sync_event(_Event, _From, _StateName, StateData) ->
	lager:debug("syncevent ~p", [_StateName]),
    {stop, error, error, StateData}.

handle_info(_Info, _StateName, StateData) ->
	lager:debug("info ~p", [_StateName]),
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

terminate(_Reason, StateName, StateData=#session{deviceid=DeviceID, topics=T, opts=Opts}) ->
    lager:info("~n * deviceid : ~p~n * reason   : ~p~n * stateName: ~p~n * stateData: ~p", [DeviceID, _Reason, StateName, StateData]),

    lists:foreach(fun({Topic, _Qos}) ->
            mqtt_topic_registry:unsubscribe(Topic, {?MODULE, publish, self()})
        end,
        T
    ),

    case proplists:get_value(clean, Opts, 1) of
        0 ->
            lager:debug("clean=0: saving client's subscriptions qos 1 & 2 messages will be stored until client reconnects"),

            lists:foreach(fun({Topic, Qos}) ->
                    case Qos of
                        0 ->
                            lager:debug("qps 0 topics: ~p/~p/~p", [DeviceID, Topic, Qos]),
                            wave_redis:topic(DeviceID, Topic, Qos);

                        _ ->
                            mqtt_offline:register(Topic, Qos, DeviceID)
                    end
                end,
                T
            );

        _ ->
            lager:debug("clean=1: cleaning client subscriptions")
    end,

    % change redis device state only if connected
    case StateName of
        connected -> wave_redis:update(DeviceID, state, disconnected);
        _         -> pass
    end,

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
    {ok, MsgWorker} = mqtt_message_worker:start_link(),
    mqtt_message_worker:publish(MsgWorker, lastwill_session, Msg), % async

    ok.

