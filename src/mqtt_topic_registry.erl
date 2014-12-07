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
-module(mqtt_topic_registry).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("include/mqtt_msg.hrl").

-record(state, {
    subscriptions = [], % {topicname, [Pid*]}
    peers
}).

%
%-export([get/1, subscribe/2, get_subscribers/1]).
-export([dump/0, subscribe/2, unsubscribe/1, match/1]).
% gen_server API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    %NOTE: currently we set ONE global registry service for the current erlang server
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    {ok, #state{}}.

%%
%% PUBLIC API
%%

%
% todo: there may be wildcard in topic name => need to do a search
%w
subscribe(Name, Subscriber) ->
    lager:debug("~p subscribing to ~p topic", [Subscriber, Name]),
    gen_server:call(?MODULE, {subscribe, Name, Subscriber}).

unsubscribe(Subscriber) ->
    gen_server:call(?MODULE, {unsubscribe, Subscriber}).

match(Name) ->
    gen_server:call(?MODULE, {match, Name}).

dump() ->
    gen_server:call(?MODULE, dump).


%%
%% PRIVATE API
%%

handle_call(dump, _, State=#state{subscriptions=S}) ->
    priv_dump(S),
    {reply, ok, State};

handle_call({subscribe, TopicName, Subscriber}, _, State=#state{subscriptions=Subscriptions}) ->
    {reply, ok, State#state{subscriptions=Subscriptions ++ [{TopicName, Subscriber}]}};

handle_call({unsubscribe, Subscriber}, _, State=#state{subscriptions=S}) ->
    S2 = priv_unsubscribe(Subscriber, S, []),
    {reply, ok, State#state{subscriptions=S2}};

handle_call({match, TopicName}, _, State=#state{subscriptions=S}) ->
    Match = priv_match(TopicName, S, []),
    {reply, Match, State};

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


priv_dump([{Topic, Subscriber} |T]) ->
    lager:info("~p -> ~p", [Topic, Subscriber]),
    priv_dump(T);

priv_dump([]) ->
    ok.

priv_unsubscribe(_, [], S2) ->
    S2;
priv_unsubscribe(S, [S|T], S2) ->
    priv_unsubscribe(S, T, S2);
priv_unsubscribe(S, [H|T], S2) ->
    priv_unsubscribe(S, T, [H|S2]).

priv_match(Topic, [{Topic, S}|T], M) ->
    priv_match(Topic, T, [{Topic,S}|M]);

priv_match(Topic, [{Re, S}|T], M) ->
    MatchList = case mqtt_topic_match:match(Re, Topic) of
        ok ->
            [{Re,S}|M];

        fail ->
            M
    end,

    priv_match(Topic, T, MatchList);

priv_match(_, [], M) ->
    M.

