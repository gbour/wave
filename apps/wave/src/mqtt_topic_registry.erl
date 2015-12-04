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

-include("mqtt_msg.hrl").

-record(state, {
    subscriptions = [], % {topicname, [Pid*]}
    peers
}).

%
%-export([get/1, subscribe/2, get_subscribers/1]).
-export([dump/0, subscribe/3, unsubscribe/1, unsubscribe/2, match/1]).
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
%
% Name: TopicName | {TopicName, Fields}
subscribe(Name, Qos, Subscriber) ->
    lager:debug("~p subscribing to ~p topic (qos ~p)", [Subscriber, Name, Qos]),
    gen_server:call(?MODULE, {subscribe, Name, Qos, Subscriber}).

unsubscribe(Subscriber) ->
    gen_server:call(?MODULE, {unsubscribe, Subscriber}).

unsubscribe(Name, Subscriber) ->
    gen_server:call(?MODULE, {unsubscribe, Name, Subscriber}).

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

handle_call({subscribe, Topic, Qos, Subscriber}, _, State=#state{subscriptions=Subscriptions}) ->
    {TopicName, Fields} = case Topic of
        {T, M} -> 
            {T, M};
        Topic  -> 
            {Topic, mqtt_topic_match:fields(Topic)}
    end,

    {Reply, S2} = case lists:filter(fun({T,F,_,S}) -> {T,F,S} =:= {TopicName,Fields,Subscriber} end, Subscriptions) of
        [] ->
            {ok, Subscriptions ++ [{TopicName,Fields,Qos,Subscriber}]};

        _  ->
            lager:error("~p already subscribed to ~p (~p)", [Subscriber, TopicName, Fields]),
            {duplicate, Subscriptions}
    end,

    {reply, Reply, State#state{subscriptions=S2}};

handle_call({unsubscribe, Subscriber}, _, State=#state{subscriptions=S}) ->
    S2 = priv_unsubscribe(Subscriber, S, []),
    {reply, ok, State#state{subscriptions=S2}};

handle_call({unsubscribe, TopicName, Subscriber}, _, State=#state{subscriptions=S}) ->
    S2 = lists:filter(fun({T,_,_,Sub}) ->
            {T,Sub} =/= {TopicName, Subscriber}
        end, S
    ),
    lager:debug("unsub2 ~p / ~p", [S, S2]),
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


priv_dump([{Topic, Fields, Subscriber} |T]) ->
    lager:info("~p (~p) -> ~p", [Topic, Fields, Subscriber]),
    priv_dump(T);

priv_dump([]) ->
    ok.

priv_unsubscribe(_, [], S2) ->
    S2;
priv_unsubscribe(S, [S|T], S2) ->
    priv_unsubscribe(S, T, S2);
priv_unsubscribe(S, [H|T], S2) ->
    priv_unsubscribe(S, T, [H|S2]).

% exact match
priv_match(Topic, [{Topic, _, Qos, S}|T], M) ->
    priv_match(Topic, T, [{Topic,Qos,S,[]}|M]);
% regex
priv_match(Topic, [{Re, Fields, Qos, S}|T], M) ->
    MatchList = case mqtt_topic_match:match(Re, {Topic, Fields}) of
        {ok, MatchFields} ->
            [{Re,Qos,S,MatchFields}|M];

        fail ->
            M
    end,

    priv_match(Topic, T, MatchList);

priv_match(_, [], M) ->
    M.

