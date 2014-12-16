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

%%
%% NOTE: current implementation is really naive
%%       we have to go through the whole list to match each subscriber topic regex
%%       will be really slow w/ hundred thousand subscribers !
%%
-module(mqtt_offline).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("include/mqtt_msg.hrl").

-record(state, {
    msgid,
    registrations = []
}).

%
%-export([get/1, subscribe/2, get_subscribers/1]).
-export([register/2, dump/0, event/3]).
% gen_server API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    {ok, #state{msgid=1}}.

%%
%% PUBLIC API
%%

%
% todo: there may be wildcard in topic name => need to do a search
%w
%unsubscribe(Subscriber) ->
%    gen_server:call(?MODULE, {unsubscribe, Subscriber}).
register(Topic, DeviceID) ->
    gen_server:call(?MODULE, {register, Topic, DeviceID}).

dump() ->
    gen_server:call(?MODULE,dump).

event(_Pid, Topic, Content) ->
    gen_server:call(?MODULE, {event, Topic, Content}).

%%
%% PRIVATE API
%%

handle_call(dump, _, State=#state{registrations=R}) ->
    lager:info("~p", [R]),
    {reply, ok, State};

handle_call({register, Topic, DeviceID}, _, State=#state{registrations=R}) ->
    mqtt_topic_registry:subscribe(Topic, {?MODULE, event, self()}),

    {reply, ok, State#state{registrations=[{Topic, DeviceID}|R]}};

%TODO: add MatchTopic in parameters
%      ie the matching topic rx that lead to executing this callback
handle_call({event, Topic, Content}, _, State=#state{msgid=MsgID, registrations=R}) ->
    lager:info("received event on ~p", [Topic]),
    {reply, ok, State#state{msgid=MsgID+1}};

handle_call(_,_,State) ->
    {reply, ok, State}.


handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.


