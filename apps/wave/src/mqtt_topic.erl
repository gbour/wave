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

-module(mqtt_topic).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").

%
-export([get/1, subscribe/2, publish/2]).
% gen_server API
-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    subscribers,
    name
}).

start_link(Name) ->
    gen_server:start_link(?MODULE, [Name], []).

init([Name]) ->
    lager:debug("creating ~p topic", [Name]),
    Tid = ets:new(subscribers, [set,private]),
    gproc:reg({n,l,{topic,Name}}),

    {ok, #state{name=Name,subscribers=Tid}}.

%%
%% PUBLIC API
%%

%
% todo: there may be wildcard in topic name => need to do a search
%
subscribe(Name, Subscriber={Mod,Fun,SPid}) ->
    {ok, Pid} = ?MODULE:get(Name),

    lager:debug("~p subscribing to ~p topic", [SPid, Name]),
    gen_server:call(Pid, {subscribe, Subscriber}).


% Get a topic by its name
% create it of not exists
%
get(Name) ->
    case gproc:where({n,l,{topic,Name}}) of
        undefined ->
            ?MODULE:start_link(Name);

        Pid       ->
            {ok, Pid}
    end.


publish(Name, Content) ->
    lager:debug("~p publish to ~p", [self(), Name]),

    {ok, Pid} = ?MODULE:get(Name),
    gen_server:call(Pid, {publish, Content}).



%%
%% PRIVATE API
%%

handle_call({subscribe, Subscriber}, _, State=#state{subscribers=Subscribers}) ->
    ets:insert(Subscribers, {Subscriber}),

    {reply, ok, State};

handle_call({publish, Content}, _, State=#state{name=Topic, subscribers=Subscribers}) ->
    dispatch(Subscribers, ets:first(Subscribers), Topic, Content),

    {reply, ok, State};

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


dispatch(_, '$end_of_table', _, _)       ->
    ok;
dispatch(Subscribers, S={Mod,Fun,Pid}, Topic, Content) ->
	Next = ets:next(Subscribers, S),

	case is_process_alive(Pid) of
		true ->
			%NOTE: delete if send failed ?
			Mod:Fun(Pid, Topic, Content);

		_    ->
			lager:info("removing dead subscriber ~p", [Pid]),
			ets:delete(Subscribers, S)
	end,

    dispatch(Subscribers, Next, Topic, Content).


