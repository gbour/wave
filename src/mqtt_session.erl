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

-export([handle/2,publish/3]).
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
    transport,
    pingid = undefined
}).

start_link(Transport) ->
    gen_fsm:start_link(?MODULE, Transport, []).

init(Transport) ->
	% timeout on socket connection: close socket is no CONNECT message received after timeout
	{ok, initiate, #session{transport=Transport}, 5000}.

%%

handle(Pid, Msg) ->
	Resp = gen_fsm:sync_send_event(Pid, Msg),
	lager:info("return: ~p", [Resp]),

	{ok, Resp}.

%
% a message is published for me
%
publish(Pid, Topic, Content) ->
    gen_fsm:sync_send_event(Pid, {publish, Topic, Content}).

%% STATES

initiate(#mqtt_msg{type='CONNECT', payload=P}, _, StateData) ->
	lager:info("received CONNECT"),
	%gen_fsm:start_timer(5000, timeout1),
	%lager:info("timeout set"),
    DeviceID = proplists:get_value(clientid, P),
    Username = proplists:get_value(username, P),
    Password = proplists:get_value(password, P),

    Retcode = case wave_auth:check(device, DeviceID, Username, Password) of
        {ok, Record} ->
            0; % ok
        {error, wrong_id} ->
            2;
        {error, bad_credentials} ->
            4 % not authorized
    end,

	%Resp = #mqtt_msg{type='CONNACK', payload=[{retcode, Retcode}]},
	Resp = #mqtt_msg{type='CONNACK', payload=[{retcode, 0}]},
	{reply, Resp, connected, StateData, 5000};
initiate(#mqtt_msg{}, _, StateData) ->
	% close socket
	{stop, disconnect, []};
initiate({timeout, _, timeout1}, _, StateData) ->
	lager:info("initiate timeout"),
	{stop, disconnect, []}.

connected(#mqtt_msg{type='DISCONNECT'}, _, StateData) ->
    {stop, normal, disconnect, undefined};

connected(#mqtt_msg{type='PINGREQ'}, _, StateData) ->
    Resp = #mqtt_msg{type='PINGRESP'},
    {reply, Resp, connected, StateData, 5000};

connected(#mqtt_msg{type='PINGRESP'}, _, StateData=#session{pingid=Ref}) ->
    lager:info("received PINGRESP"),
    gen_fsm:cancel_timer(Ref),
    {reply, undefined, connected, StateData#session{pingid=undefined}, 5000};

connected(#mqtt_msg{type='PUBLISH', payload=P}, _, StateData) ->
    Topic   = proplists:get_value(topic, P),
    Content = proplists:get_value(data, P),

    MatchList = mqtt_topic_registry:match(Topic),
    lager:info("matchlist= ~p", [MatchList]),
    [
        case is_process_alive(Pid) of
            true ->
                Mod:Fun(Pid, Topic, Content);

            _ ->
                lager:info("deadbeef ~p", [Pid]),
                mqtt_topic_registry:unsubscribe(Subscr)

        end

        || Subscr={_, {Mod,Fun,Pid}} <- MatchList
    ],

	Resp = #mqtt_msg{type='PUBACK', payload=[{msgid,1}]},
	{reply, Resp, connected, StateData, 5000};

connected(#mqtt_msg{type='SUBSCRIBE', payload=P}, _, StateData) ->
	MsgId  = proplists:get_value(msgid, P),
    Topics = proplists:get_value(topics, P),
  
    % subscribe to all listed topics (creating it if it don't exists)
    [ mqtt_topic_registry:subscribe(Topic, {?MODULE,publish,self()}) || {Topic,Qos} <- Topics ],


	Resp  = #mqtt_msg{type='SUBACK', payload=[{msgid,MsgId},{qos,[1]}]},

    {reply, Resp, connected, StateData, 5000};

connected({publish, Topic, Content}, _, StateData=#session{transport={Callback,Transport,Socket}}) ->
    Ret = Callback:publish(Transport, Socket, Topic, Content),
	lager:info("ret= ~p", [Ret]),
	case Ret of
		{error, Err} ->
			{stop, normal, disconnect, undefined};

		ok ->
			{reply, ok, connected, StateData, 5000}
	end;

connected(_,_, StateData) ->
    {stop, normal, disconnect, undefined}.

connected({timeout, _, timeout1}, StateData) ->
	lager:info("timeout after connection"),
	{stop, disconnect, []};

connected(timeout, StateData=#session{transport={Callback,Transport,Socket}}) ->
    %lager:info("5s timeout"),
    % sending ping
    %Callback:ping(Transport, Socket),
    %Ref = gen_fsm:send_event_after(1000, ping_timeout),
    Ref=0,

    {next_state, connected, StateData#session{pingid=Ref}};

connected(ping_timeout, StateData=#session{transport={Callback,Transport,Socket}}) ->
    Callback:close(Transport, Socket),
    {stop, normal, undefined}.



handle_event(_Event, _StateName, StateData) ->
	lager:debug("event ~p", [_StateName]),
    {stop, error, StateData}.

handle_sync_event(_Event, _From, _StateName, StateData) ->
	lager:debug("syncevent ~p", [_StateName]),
    {stop, error, error, StateData}.

handle_info(_Info, _StateName, StateData) ->
	lager:debug("info ~p", [_StateName]),
    {stop, error, StateData}.

terminate(_Reason, _StateName, _StateData) ->
    lager:info("session terminate"),
    terminate.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.

