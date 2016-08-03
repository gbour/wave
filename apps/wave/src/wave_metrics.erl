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
-module(wave_metrics).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").
-define(DFT_TIMEOUT, 5000).


% public API
-export([get/1]).
% gen_server internals
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
% internal funs

-record(state, {
    start
 }).

-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    %NOTE: currently we set ONE global registry service for the current erlang server
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    erlang:send_after(?DFT_TIMEOUT, self(), timeout),
    {ok, #state{start=?TIME}}.

%%
%% PUBLIC API
%%

-spec get(atom()) -> {ok|atom(), any()}.
% active sessions
get(active)   ->
    {ok, proplists:get_value(active, supervisor:count_children(wave_sessions_sup), 0)};
% offline sessions
get(offline)  ->
    wave_db:count(<<"session:*">>);
% retained messages (in redis)
get(retained) ->
    wave_db:count(<<"retain:*">>);
% stored messages (in redis)
get(stored)   ->
    wave_db:count(<<"msg:*:refcount">>);
% server uptime
get(uptime)  ->
    {ok, gen_server:call(?MODULE, uptime)}.


%%
%% INTERNAL CALLBACKS
%%

handle_call(uptime, _, State=#state{start=Start}) ->
    Uptime = ?TIME - Start,
    {reply, Uptime, State};

handle_call(Event,_,State) ->
    lager:warning("non catched call: ~p", [Event]),
    {reply, ok, State}.


handle_cast(Event, State) ->
    lager:warning("non catched cast: ~p", [Event]),
    {noreply, State}.


handle_info(timeout, State) ->
    lager:debug("timeout"),
    [ publish(metric(T, State)) || T <- [version, uptime, sent, received, clients] ],

    ExoMetrics = [
        {[wave,sessions], [
            {active , <<"broker/clients/connected">>},
            {offline, <<"broker/clients/disconnected">>}
        ]}
        ,{[wave,packets,received] , [{count, <<"broker/messages/received">>}]}
        ,{[wave,packets,sent]     , [{count, <<"broker/messages/sent">>}]}
        ,{[wave,messages,in,0]    , [{count, <<"broker/publish/messages/received/qos 0">>}]}
        ,{[wave,messages,in,1]    , [{count, <<"broker/publish/messages/received/qos 1">>}]}
        ,{[wave,messages,in,2]    , [{count, <<"broker/publish/messages/received/qos 2">>}]}
        ,{[wave,messages,out,0]   , [{count, <<"broker/publish/messages/sent/qos 0">>}]}
        ,{[wave,messages,out,1]   , [{count, <<"broker/publish/messages/sent/qos 1">>}]}
        ,{[wave,messages,out,2]   , [{count, <<"broker/publish/messages/sent/qos 2">>}]}
        ,{[wave,messages,inflight], [{value, <<"broker/messages/inflight">>}]}
        ,{[wave,messages], [
            {retained, <<"broker/retained messages/count">>},
            {stored  , <<"broker/messages/stored">>}
        ]}
        ,{[wave,subscriptions]    , [{value, <<"broker/subscriptions/count">>}]}
    ],
    exometrics(ExoMetrics),

    erlang:send_after(?DFT_TIMEOUT, self(), timeout),
    {noreply, State};

handle_info(Info, State) ->
    lager:warning("non catched info: ~p", [Info]),
    {noreply, State}.


terminate(_,_) ->
    lager:error("~p terminated", [?MODULE]),
    ok.


code_change(_, State, _) ->
    {ok, State}.


%%
%% INTERNAL FUNS
%%


%TODO: should be computed once at start only (maybe recomputed on code_change)
metric(version, _) ->
    [Version] = lists:filtermap(
        fun({X,_,V}) -> if X =:= wave -> {true, V}; true -> false end end,
        application:loaded_applications()
    ),

    {<<"broker/version">>, Version};

metric(uptime, #state{start=Start}) ->
    Uptime = ?TIME - Start,
    %NOTE: we use same format as mosquitto (string :: "%d seconds")
    {<<"broker/uptime">>, <<(wave_utils:bin(Uptime))/binary, " seconds">>};

% sent messages: sum of sent messages for each topic
metric(sent, _) ->
    Sum = lists:foldl(
        fun({_, DPs}, Acc) -> proplists:get_value(count, DPs, 0)+Acc end,
        0, exometer:get_values([wave,messages,out])
    ),
    {<<"broker/publish/messages/sent">>, Sum};

% received messages: sum of received messages for each topic
metric(received, _) ->
    Sum = lists:foldl(
        fun({_, DPs}, Acc) -> proplists:get_value(count, DPs, 0)+Acc end,
        0, exometer:get_values([wave,messages,in])
    ),
    {<<"broker/publish/messages/received">>, Sum};

% sum of connected and offline (disconnected) clients
metric(clients, _) ->
   {ok, Values} = exometer:get_value([wave,sessions]),
    Sum = lists:foldl(
        fun({_, Value}, Acc) -> Value+Acc end,
        0, Values
    ),
    {<<"broker/clients/total">>, Sum}.


exometrics([])                      ->
    ok;
exometrics([{Name, DPs} | T]) ->
    case exometer:get_value(Name) of
        {ok, Values} -> exometrics2(Name, DPs, Values);
        Err          -> lager:info("Exometer ~p metric not found", [Name])
    end,
    exometrics(T).

exometrics2(_, [], _) ->
    ok;
exometrics2(Name, [{DP, Topic} | T], Values) ->
    case proplists:get_value(DP, Values) of
        undefined -> lager:info("Exometer datapoint ~p not found for ~p metric", [DP, Name]);
        Value     -> publish({Topic, Value})
    end,
    exometrics2(Name, T, Values).


publish({Topic, Content}) ->
    Msg = #mqtt_msg{type='PUBLISH', qos=0, payload=[
        {topic, <<"$SYS/", Topic/binary>>}, {msgid, 0}, {data, wave_utils:bin(Content)}]
    },

    {ok, MsgWorker} = supervisor:start_child(wave_msgworkers_sup, []),
    mqtt_message_worker:publish(MsgWorker, self(), Msg). % async

