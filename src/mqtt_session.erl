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

-module(mqtt_session).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_fsm).

-include("include/mqtt_msg.hrl").

-export([start_link/1]).

% gen_server
%-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
% gen_fsm
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

-export([handle/2, publish/4, is_alive/1, garbage_collect/1, disconnect/2]).
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
    deviceid,
    topics = [], % list of subscribed topics
    transport,
    pingid = undefined,
    keepalive
}).

-define(CONNECT_TIMEOUT  , 5000). % ms
-define(DEFAULT_KEEPALIVE, 300).  % secs

start_link(Transport) ->
    gen_fsm:start_link(?MODULE, Transport, []).

init(Transport) ->
	% timeout on socket connection: close socket is no CONNECT message received after timeout
	{ok, initiate, #session{transport=Transport}, ?CONNECT_TIMEOUT}.

%%

handle(Pid, Msg) ->
	Resp = gen_fsm:sync_send_event(Pid, Msg),
	lager:info("return: ~p", [Resp]),

	{ok, Resp}.

% peer client disconnection
%
disconnect(Pid, Reason) ->
    gen_fsm:send_all_state_event(Pid, {disconnect, Reason}).

%
%
% return true if client connection still alive
% (check socket status => kill mqtt_session if socket is in error (closed))
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

garbage_collect(_Pid) ->
    ok.

%
% a message is published for me
%
publish(Pid, Topic, Content, Qos) ->
    gen_fsm:sync_send_event(Pid, {publish, Topic, Content, Qos}).

%% STATES

initiate(#mqtt_msg{type='CONNECT', payload=P}, _, StateData) ->
	lager:info("received CONNECT"),
	%gen_fsm:start_timer(5000, timeout1),
	%lager:info("timeout set"),
    DeviceID = proplists:get_value(clientid, P),
    User     = proplists:get_value(username, P),
    Pwd      = proplists:get_value(password, P),
    KeepAlive = proplists:get_value(keepalive, P, ?DEFAULT_KEEPALIVE) * 1000,

    % load device settings from db
    Settings = case wave_redis:device({deviceid, DeviceID}) of
        {error, Err} ->
            lager:info("~p: failed to get settings (~p)", [DeviceID, Err]),
            [];

        {ok, Setts} ->
            Setts
    end,

    Retcode = case wave_auth:check(application:get_env(wave, auth_required), DeviceID, {User, Pwd}, Settings) of
        {ok, _} ->
            case gproc:where({n,l,DeviceID}) of
                undefined ->
                    gproc:reg({n,l,DeviceID}),

                    % if connection is successful, we need to check if we have offline messages
                    % 
                    Topics = mqtt_offline:recover(DeviceID),
                    lager:info("offline topics: ~p", [Topics]),
                    [ mqtt_topic_registry:subscribe(Topic, {?MODULE,publish,self()}) || {Topic,_} <- Topics ],
                    % flush is async
                    case Topics of
                        [] -> ok;
                        _  ->
                            mqtt_offline:flush(DeviceID, {?MODULE,publish,self()})
                    end,

                    0;

                Pid       ->
                    %TODO: check if processus is alive / socket is opened (try read)
                    case mqtt_session:is_alive(Pid) of
                        true ->
                            lager:info("~p device already registered", [DeviceID]),
                            5;

                        _    ->
                            %mqtt_session:garbage_collect(Pid),
                            gproc:reg({n,l,DeviceID}),
                            0
                    end
            end;

        {error, wrong_id} ->
            2;
        {error, bad_credentials} ->
            4 % not authorized
    end,

    wave_event_router:route(<<"$/mqtt/CONNECT">>, [{deviceid, DeviceID}, {retcode, Retcode}]),

	Resp = #mqtt_msg{type='CONNACK', payload=[{retcode, Retcode}]},
	{reply, Resp, connected, StateData#session{deviceid=DeviceID, keepalive=KeepAlive}, round(KeepAlive*1.5)};
initiate(#mqtt_msg{}, _, _StateData) ->
	% close socket
	{stop, disconnect, []};
initiate({timeout, _, timeout1}, _, _StateData) ->
	lager:info("initiate timeout"),
	{stop, disconnect, []}.

connected(#mqtt_msg{type='DISCONNECT'}, _, _StateData) ->
    {stop, normal, disconnect, undefined};

connected(#mqtt_msg{type='PINGREQ'}, _, StateData=#session{keepalive=Ka}) ->
    Resp = #mqtt_msg{type='PINGRESP'},
    {reply, Resp, connected, StateData, round(Ka*1.5)};

connected(#mqtt_msg{type='PINGRESP'}, _, StateData=#session{pingid=Ref,keepalive=Ka}) ->
    lager:info("received PINGRESP"),
    gen_fsm:cancel_timer(Ref),
    {reply, undefined, connected, StateData#session{pingid=undefined}, round(Ka*1.5)};

connected(#mqtt_msg{type='PUBLISH', qos=Qos, payload=P}, _, StateData=#session{deviceid=_DeviceID,keepalive=Ka}) ->
    Topic   = proplists:get_value(topic, P),
    Content = proplists:get_value(data, P),

    MatchList = mqtt_topic_registry:match(Topic),
    lager:info("matchlist= ~p", [MatchList]),
    [
        case is_process_alive(Pid) of
            true ->
                %TODO: add MatchTopic in parameters
                %      ie the matching topic rx that lead to executing this callback
                %
                %      in case of error (socket closed), subscriber is automatically registered
                %      to offline
                lager:info("candidate: pid=~p, topic=~p, content=~p", [Pid, Topic, Content]),
                Ret = Mod:Fun(Pid, {Topic,TopicMatch}, Content, Qos),
                lager:info("publish to client: ~p", [Ret]),
                case {Qos, Ret} of
                    {0, disconnect} ->
                        lager:debug("client ~p disconnected but QoS = 0. message dropped", [Pid]);

                    {_, disconnect} ->
                        lager:debug("client ~p disconnected while sending message", [Pid]),
%                        mqtt_topic_registry:unsubscribe(Subscr),
%                        mqtt_offline:register(Topic, DeviceID),
                        mqtt_offline:event(undefined, {Topic, Qos}, Content),
                        ok;

                    _ ->
                        ok
                end;

            _ ->
                % SHOULD NEVER HAPPEND
                lager:error("deadbeef ~p", [Pid])

        end

        || _Subscr={TopicMatch, {Mod,Fun,Pid}, _Fields} <- MatchList
    ],

    Resp = case Qos of
        2 ->
            #mqtt_msg{type='PUBREC', payload=[{msgid,1}]};
        1 ->
	        #mqtt_msg{type='PUBACK', payload=[{msgid,1}]};
        _ ->
            undefined
    end,
	{reply, Resp, connected, StateData, round(Ka*1.5)};

%TODO: prevent subscribing multiple times to the same topic
connected(#mqtt_msg{type='SUBSCRIBE', payload=P}, _, StateData=#session{topics=T, keepalive=Ka}) ->
	MsgId  = proplists:get_value(msgid, P),
    Topics = proplists:get_value(topics, P),
  
    % subscribe to all listed topics (creating it if it don't exists)
    [ mqtt_topic_registry:subscribe(Topic, {?MODULE,publish,self()}) || {Topic,_Qos} <- Topics ],

	Resp  = #mqtt_msg{type='SUBACK', payload=[{msgid,MsgId},{qos,[1]}]},

    lager:info("Ka=~p", [Ka]),
    {reply, Resp, connected, StateData#session{topics=Topics++T}, round(Ka*1.5)};

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
	Resp  = #mqtt_msg{type='SUBACK', payload=[{msgid,MsgId},{qos,[1]}]},

    lager:info("Ka=~p ~p", [Ka, OldTopics]),
    {reply, Resp, connected, StateData#session{topics=NewTopics}, round(Ka*1.5)};

connected({publish, {Topic,_}, Content, Qos}, _,
          StateData=#session{transport={Callback,Transport,Socket},keepalive=Ka}) ->
    lager:debug("~p: publish message to client with QoS=~p", [self(), Qos]),

    Msg   = #mqtt_msg{type='PUBLISH', payload=[{topic,Topic}, {content, Content}]},
    State = case Qos of 
        0 -> 
            Callback:send(Transport, Socket, Msg);

        _ ->
            %TODO
            lager:error("NOT IMPLEMENTED"),
            ok
    end,

	lager:info("publish msg status= ~p", [State]),
	case State of
		{error, _Err} ->
			{stop, normal, disconnect, StateData};

		ok ->
			{reply, ok, connected, StateData, round(Ka*1.5)}
	end;

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

connected(timeout, StateData=#session{transport={Callback,Transport,Socket}}) ->
    %lager:info("5s timeout"),
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

terminate(_Reason, _StateName, _StateData=#session{deviceid=DeviceID, topics=T}) ->
    lager:info("session terminate: ~p (~p ~p)", [_Reason, _StateName, _StateData]),
    [
        case Qos of
            0 ->
                lager:debug("~p: forget ~p topic (QoS=~p)", [self(), Topic, Qos]),
                mqtt_topic_registry:unsubscribe(Topic, {?MODULE,publish,self()});

            _ ->
                lager:debug("~p: set ~p topic in offline mode (QoS=~p)", [self(), Topic, Qos]),
                % TODO: add a mqtt_topic_register:substitute()
                %       replacing client session process by offline process
                mqtt_topic_registry:unsubscribe(Topic, {?MODULE,publish,self()}),
                mqtt_offline:register(Topic, DeviceID)
        end

        || {Topic, Qos} <- T
    ],
    terminate;

% publisher disconnection
terminate(_Reason, _StateName, undefined) ->
    lager:info("terminate for ~p/~p", [_Reason, _StateName]),
    terminate.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.

