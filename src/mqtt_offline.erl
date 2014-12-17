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
-export([register/2, recover/1, flush/2, dump/0, event/3]).
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

handle_call({register, Topic, DeviceID}, _, State=#state{registrations=R}) ->
    mqtt_topic_registry:subscribe(Topic, {?MODULE, event, self()}),

    {reply, ok, State#state{registrations=[{Topic, DeviceID}|R]}};

handle_call({recover, DeviceID}, _, State=#state{registrations=R}) ->
    {R2, DTopics} = lists:partition(fun({_Topic, DeviceID2}) -> DeviceID2 =/= DeviceID end, R),
    lager:info("~p / ~p", [R2, DTopics]),
    lists:foreach(fun({Topic, _}) ->
            mqtt_topic_registry:unsubscribe({Topic, {?MODULE,event,self()}})
        end,
        DTopics
    ),

    {reply, DTopics, State#state{registrations=R2}};

%TODO: add MatchTopic in parameters
%      ie the matching topic rx that lead to executing this callback
handle_call({event, Topic, Content}, _, State=#state{msgid=MsgID, registrations=R}) ->
    {ok, C} = eredis:start_link(),
    lager:info("received event on ~p", [Topic]),

    MsgIDs = erlang:integer_to_binary(MsgID),
    Ret = eredis:q(C, ["SET", <<"msg:", (erlang:integer_to_binary(MsgID))/binary>>, Content]),
    lager:info("~p", [Ret]),

    [
        case mqtt_top of
            _ ->
            %Topic ->
                eredis:q(C, ["LPUSH", <<"queue:", DeviceID/binary>>, MsgIDs]),
                eredis:q(C, ["INCR",  <<"msg:", MsgIDs/binary, ":refcount">>]);

            _     ->
                pass
        end

        || {T2, DeviceID} <- R
    ],

    {reply, ok, State#state{msgid=MsgID+1}};

handle_call(_,_,State) ->
    {reply, ok, State}.

handle_cast({flush, DeviceID, {M,F,Pid}}, State=#state{}) ->
    lager:info("flush ~p", [DeviceID]),
    {ok, C} = eredis:start_link(),

    {ok, MsgIDs} = eredis:q(C, ["LRANGE", <<"queue:", DeviceID/binary>>, 0, -1]),
    lists:foreach(fun(Id) ->
            {ok, Msg} = eredis:q(C, ["GET", <<"msg:", Id/binary>>]),
            lager:info("~p flush msg: ~p (id: ~p)", [DeviceID, Msg, Id]),
            M:F(Pid, <<"/offline">>, Msg),
            {ok, Cnt} = eredis:q(C, ["DECR", <<"msg:", Id/binary,":refcount">>]),
            Cnt2 = erlang:binary_to_integer(Cnt),
            if Cnt2 =< 0 ->
                eredis:q(C, ["DEL", <<"msg:", Id/binary>>]),
                eredis:q(C, ["DEL", <<"msg:", Id/binary, ":refcount">>])
            end,

            ok
        end, 
        MsgIDs
    ),
    %TODO: delete queue
    eredis:q(C, ["LTRIM", <<"queue:",DeviceID/binary>>, length(MsgIDs), -1]),

    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.


