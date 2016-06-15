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
%-behaviour(gen_server).


% public API
-export([get/1]).
% gen_server internals
%-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
% internal funs

%-record(state, {
% }).

%-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
%start_link() ->
%    % name = mqtt_offline
%    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
%
%init(_) ->
%    {ok, #state{}}.

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
    wave_db:count(<<"msg:*:refcount">>).

%%
%% INTERNAL CALLBACKS
%%


%handle_call(Event,_,State) ->
%    lager:warning("non catched call: ~p", [Event]),
%    {reply, ok, State}.
%
%
%handle_cast(Event, State) ->
%    lager:warning("non catched cast: ~p", [Event]),
%    {noreply, State}.
%
%
%handle_info(Info, State) ->
%    lager:warning("non catched info: ~p", [Info]),
%    {noreply, State}.
%
%terminate(_,_) ->
%    lager:error("~p terminated", [?MODULE]),
%    ok.
%
%code_change(_, State, _) ->
%    {ok, State}.
%

%%
%% INTERNAL FUNS
%%

