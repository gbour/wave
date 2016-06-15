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
-module(mqtt_topic_registry).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").

-record(state, {
    subscriptions = [], % {topicname, [Pid*]}
    peers
}).

-type subscriber()   :: {Module :: module(), Fun :: atom(), Pid :: pid(), DeviceID :: mqtt_clientid()|undefined}.
-type subscription() :: {Re :: binary(), Fields :: list(integer()), Qos :: integer(), Subscriber :: subscriber()}.
-type match()        :: {Position :: integer(), Value :: binary()}.
-type match_result() :: {Re :: binary(), Qos :: integer(), Subscriber :: subscriber(), Matches :: list(match())}.


%
-export([count/0, dump/0, subscribe/3, unsubscribe/1, unsubscribe/2, match/1]).
-ifdef(DEBUG).
    -export([debug_cleanup/0]).
-endif.
% gen_server API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    %NOTE: currently we set ONE global registry service for the current erlang server
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    exometer:update([wave,subscriptions], 0),
    {ok, #state{}}.

%%
%% PUBLIC API
%%

%
% todo: there may be wildcard in topic name => need to do a search
%
% Name: TopicName | {TopicName, Fields}
-spec subscribe(Topic :: binary(), Qos :: integer(), Subscriber :: subscriber()) -> ok | duplicate.
subscribe(Name, Qos, Subscriber) ->
    gen_server:call(?MODULE, {subscribe, Name, Qos, Subscriber}).


-spec unsubscribe(Subscription :: subscription()) -> ok.
unsubscribe(Subscription) ->
    gen_server:call(?MODULE, {unsubscribe, Subscription}).


-spec unsubscribe(Topic :: binary(), Subscriber :: subscriber()) -> ok.
unsubscribe(Name, Subscriber) ->
    gen_server:call(?MODULE, {unsubscribe, Name, Subscriber}).


-spec match(Topic :: binary()) -> list(match_result()).
match(Name) ->
    gen_server:call(?MODULE, {match, Name}).


-spec count() -> integer().
count() ->
    {ok, gen_server:call(?MODULE, count)}.
    
-spec dump() -> ok.
dump() ->
    gen_server:call(?MODULE, dump).

% flush all registry
-ifdef(DEBUG).
debug_cleanup() ->
    gen_server:call(?MODULE, debug_cleanup).
-endif.

%%
%% PRIVATE API
%%

handle_call(count, _, State=#state{subscriptions=S}) ->
    {reply, erlang:length(S), State};    

handle_call(dump, _, State=#state{subscriptions=S}) ->
    priv_dump(S),
    {reply, ok, State};

handle_call(debug_cleanup, _, _State) ->
    lager:warning("clearing registry"),
    exometer:update([wave,subscriptions], 0),

    {reply, ok, #state{}};

handle_call({subscribe, Topic, Qos, Subscriber}, _, State=#state{subscriptions=Subscriptions}) ->
    lager:debug("~p: subscribe to '~p' topic w/ qos ~p", [Subscriber, Topic, Qos]),

    {TopicName, Fields} = case Topic of
        {T, M} -> 
            {T, M};
        Topic  -> 
            {Topic, mqtt_topic_match:fields(Topic)}
    end,

    {Reply, S2} = case lists:filter(fun({T,F,_,S}) -> {T,F,S} =:= {TopicName,Fields,Subscriber} end, Subscriptions) of
        [] ->
            exometer:update([wave,subscriptions], length(Subscriptions)+1),
            {ok, Subscriptions ++ [{TopicName,Fields,Qos,Subscriber}]};

        _  ->
            lager:notice("~p already subscribed to ~p (~p)", [Subscriber, TopicName, Fields]),
            {duplicate, Subscriptions}
    end,

    {reply, Reply, State#state{subscriptions=S2}};

handle_call({unsubscribe, Subscriber}, _, State=#state{subscriptions=S}) ->
    S2 = priv_unsubscribe(Subscriber, S, []),
    exometer:update([wave,subscriptions], length(S2)),
    {reply, ok, State#state{subscriptions=S2}};

handle_call({unsubscribe, TopicName, Subscriber}, _, State=#state{subscriptions=S}) ->
    lager:debug("unsubscribe ~p from ~p", [Subscriber, TopicName]),

    S2 = lists:filter(fun({T,_,_,Sub}) ->
            {T,Sub} =/= {TopicName, Subscriber}
        end, S
    ),
    
    exometer:update([wave,subscriptions], length(S2)),
    %lager:debug("unsub2 ~p / ~p", [S, S2]),
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

%%
%% PRIVATE FUNS
%%

% dump subscribers list
%
-spec priv_dump(list(subscription())) -> ok.
priv_dump([{Topic, Fields, Qos, Subscriber} |T]) ->
    lager:info("~p (~p) (qos ~p) -> ~p", [Topic, Fields, Qos, Subscriber]),
    priv_dump(T);

priv_dump([]) ->
    ok.


% remove a subscriber from subscription list
%
-spec priv_unsubscribe(Subscriber :: subscription(), Subscribers :: list(subscription()), 
                       Acc :: list(subscription)) -> list(subscription()).
priv_unsubscribe(_, [], S2) ->
    S2;
priv_unsubscribe(S, [S|T], S2) ->
    priv_unsubscribe(S, T, S2);
priv_unsubscribe(S, [H|T], S2) ->
    priv_unsubscribe(S, T, [H|S2]).


% find subscriptions matching topic
%
-spec priv_match(Topic :: binary(), Subscriptions :: list(subscription()), Acc :: list(match_result())) ->
        list(match_result()).
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

