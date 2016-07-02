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

-module(mqtt_offline_session).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_fsm).

-include("mqtt_msg.hrl").

% public API
-export([start_link/0]).
% gen_fsm funs
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
% gen_fsm internals
-export([run/2]).

-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    gen_fsm:start_link({local, offline_session}, ?MODULE, [], []).

init([]) ->
    {ok, run, undefined}.


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

run({ack, _MsgID, _Qos, _}, State) ->
    % do nothing
    lager:debug("recv PUBCOMP/PUBACK (qos= ~p)", [_Qos]),
    {next_state, run, State};

run({'msg-landed', MsgID}, State) ->
    lager:debug("msg ~p landed", [MsgID]),
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
    lager:notice("session terminate with undefined state: ~p", [_Reason]),
    terminate.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


%%
%% PRIVATE FUNS
%%

