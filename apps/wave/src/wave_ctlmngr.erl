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
-module(wave_ctlmngr).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").

-record(state, {
}).

%
-export([process/3]).
% gen_server API
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

init(_) ->
    mqtt_topic_registry:subscribe(<<"/adm/wavectl/+">>, 0, {?MODULE,process,self()}),

    {ok, #state{}}.

%%
%% PUBLIC API
%%

%
% todo: there may be wildcard in topic name => need to do a search
%w
process(Pid, Topic, Content) ->
    P = jiffy:decode(Content, [return_maps]),
    lager:debug("process wavectl request: ~p > ~p", [Topic, P]),
    case maps:find(<<"request">>, P) of 
        error ->
            lager:info("request not found in payload");

        {ok, Cmd} ->
            gen_server:cast(Pid, {Cmd, Topic, P})
    end.


%%
%% PRIVATE API
%%

handle_call(_,_,State) ->
    lager:info("unmatched"),
    {reply, ok, State}.


handle_cast({<<"ping">>, Topic, Msg}, State) ->
    {ok, Id} = maps:find(<<"id">>, Msg),

    publish(<<Topic/binary, "/resp">>, #{id => Id, response => pong}),
    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.


%% 
%% PRIVATE functions
%%

publish(Topic, Msg) ->
    Content   = jiffy:encode(Msg),
    lager:info("publishing to ~p: ~p", [Topic, Msg]),
    MatchList = mqtt_topic_registry:match(Topic),
    lager:info("matchlist= ~p", [MatchList]),
    [
        case is_process_alive(Pid) of
            true ->
                Mod:Fun(Pid, Topic, Content);

            _ ->
                lager:info("deadbeef ~p", [Pid]),
                mqtt_topic_registry:unsubscribe(Subscr)

        end

        || Subscr={_, _, {Mod,Fun,Pid}} <- MatchList
    ].

