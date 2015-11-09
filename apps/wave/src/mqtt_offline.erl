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

-include("mqtt_msg.hrl").

-record(state, {
    registrations = [],
    redis % redis connection
}).

%
%-export([get/1, subscribe/2, get_subscribers/1]).
-export([register/3, recover/1, flush/2, dump/0, event/3]).
% gen_server API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    {ok, Redis} = application:get_env(wave, redis),

    {ok, #state{redis=Redis}}.

%%
%% PUBLIC API
%%

%
% todo: there may be wildcard in topic name => need to do a search
%w
%unsubscribe(Subscriber) ->
%    gen_server:call(?MODULE, {unsubscribe, Subscriber}).
register(Topic, Qos, DeviceID) ->
    gen_server:call(?MODULE, {register, Topic, Qos, DeviceID}).


recover(DeviceID) ->
    gen_server:call(?MODULE, {recover, DeviceID}).

flush(DeviceID, Session) ->
    gen_server:cast(?MODULE, {flush, DeviceID, Session}).

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

handle_call({register, Topic, Qos, DeviceID}, _, State=#state{registrations=R}) ->
    mqtt_topic_registry:subscribe(Topic, Qos, {?MODULE, event, self()}),

    {reply, ok, State#state{registrations=[{Topic, Qos, DeviceID}|R]}};

handle_call({recover, DeviceID}, _, State=#state{registrations=R}) ->
    {R2, DTopics} = lists:partition(fun({_Topic, _Qos, DeviceID2}) -> DeviceID2 =/= DeviceID end, R),
    lager:info("~p / ~p", [R2, DTopics]),
    lists:foreach(fun({Topic, _, _}) ->
            mqtt_topic_registry:unsubscribe(Topic, {?MODULE,event,self()})
        end,
        DTopics
    ),

    {reply, DTopics, State#state{registrations=R2}};

%TODO: add MatchTopic in parameters
%      ie the matching topic rx that lead to executing this callback
handle_call({event, {Topic,TopicMatch}, Content}, _, State=#state{registrations=R, redis=Redis}) ->
    lager:info("received event on ~p (matched with ~s)", [Topic, TopicMatch]),

    %TODO: optimisation: for messages shorted than len(HMAC),
    %      store directly the message in the queue
    MsgID = erlang:list_to_binary(hmac:hexlify(hmac:hmac("", Content))),
    Ret = eredis:q(Redis, ["SET", <<"msg:", MsgID/binary>>, Content]),
    lager:info("~p", [Ret]),

    [
        case T2 of
            TopicMatch ->
                eredis:q(Redis, ["RPUSH", <<"queue:", DeviceID/binary>>, Topic, MsgID]),
                eredis:q(Redis, ["INCR",  <<"msg:", MsgID/binary, ":refcount">>]);

            _     ->
                pass
        end

        || {T2, DeviceID} <- R
    ],

    {reply, ok, State};

handle_call(_,_,State) ->
    {reply, ok, State}.

handle_cast({flush, DeviceID, Device={_M,_F,_Pid}}, State=#state{redis=Redis}) ->
    lager:info("flush ~p", [DeviceID]),

    {ok, MsgIDs} = eredis:q(Redis, ["LRANGE", <<"queue:", DeviceID/binary>>, 0, -1]),
    priv_flush(Redis, MsgIDs, Device),

    %TODO: delete queue
    eredis:q(Redis, ["LTRIM", <<"queue:",DeviceID/binary>>, length(MsgIDs), -1]),

    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.


priv_flush(C, [Topic, MsgID |T], Device={M,F,Pid}) ->
    {ok, Msg} = eredis:q(C, ["GET", <<"msg:", MsgID/binary>>]),
    lager:info("flush msg: ~p (id: ~p, topic= ~p)", [Msg, MsgID, Topic]),
    M:F(Pid, {Topic, undefined}, Msg),

    %TODO: operation must be atomic (including the LRANGE ?)
    %      use MULTI/EXEC
    {ok, Cnt} = eredis:q(C, ["DECR", <<"msg:", MsgID/binary,":refcount">>]),
    Cnt2 = erlang:binary_to_integer(Cnt),
    if 
        Cnt2 =< 0 ->
            eredis:q(C, ["DEL", <<"msg:", MsgID/binary>>]),
            eredis:q(C, ["DEL", <<"msg:", MsgID/binary, ":refcount">>]);

        true ->
            ok
    end,

    % next queued message
    priv_flush(C, T, Device);

priv_flush(_, [], _) ->
    ok.
