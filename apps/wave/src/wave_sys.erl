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
-module(wave_sys).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").
-define(DFT_TIMEOUT, 5000).

-record(state, {
    start
}).

%
-export([]).
% gen_server API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    %NOTE: currently we set ONE global registry service for the current erlang server
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    erlang:send_after(?DFT_TIMEOUT, self(), timeout),
    {ok, #state{start=?TIME}}.

%%
%% PUBLIC API
%%

%%
%% PRIVATE API
%%

handle_call(_,_,State) ->
    {reply, ok, State}.


handle_cast(_, State) ->
    {noreply, State}.

handle_info(timeout, State) ->
    lager:error("timeout"),
    emit(<<"broker/version">>, State),
    emit(<<"broker/uptime">>, State),

    erlang:send_after(?DFT_TIMEOUT, self(), timeout),
    {noreply, State};

handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.

%%
%% PRIVATE FUNS
%%

emit(T= <<"broker/version">>, _) ->
    [Version] = lists:filtermap(
        fun({X,_,V}) -> if X =:= wave -> {true, V}; true -> false end end,
        application:loaded_applications()
    ),

    publish(T, wave_utils:bin(Version));

emit(T= <<"broker/uptime">>, #state{start=Start}) ->
    Uptime = ?TIME - Start,
    %NOTE: we use same format as mosquitto (string :: "%d seconds")
    publish(T, <<(wave_utils:bin(Uptime))/binary, " seconds">>).


publish(Topic, Content) ->
    Msg = #mqtt_msg{type='PUBLISH', qos=0, payload=[
        {topic, <<"$SYS/", Topic/binary>>}, {msgid, 0}, {data, Content}]
    },

    {ok, MsgWorker} = supervisor:start_child(wave_msgworkers_sup, []),
    mqtt_message_worker:publish(MsgWorker, self(), Msg). % async

