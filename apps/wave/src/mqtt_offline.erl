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
-module(mqtt_offline).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-include("mqtt_msg.hrl").

% public API
-export([register/2]).
% gen_server internals
-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
% internal funs

-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    % name = mqtt_offline
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_) ->
    {ok, #{}}.

%%
%% PUBLIC API
%%

-spec register(binary(), list({binary(), 0|1|2})) -> ok.
register(DeviceID, TopicFs) ->
    gen_server:call(?MODULE, {register, DeviceID, TopicFs}).


-spec recover(binary()) -> list({Topic:: binary(), Qos :: integer()}).
recover(DeviceID) ->
    gen_server:call(?MODULE, {recover, DeviceID}).


%%
%% INTERNAL CALLBACKS
%%


handle_call({register, DeviceID, TopicFs}, _, State) ->
    priv_register(DeviceID, TopicFs),

    {reply, ok, State#{DeviceID => TopicFs}};

    %TODO: optimisation: for messages shorted than len(HMAC),
    %      store directly the message in the queue
    MsgID = wave_utils:bin(hmac:hexlify(hmac:hmac("", Content))),
    Ret = wave_db:set({s, <<"msg:", MsgID/binary>>}, Content),
    lager:info("~p", [Ret]),

    [
        case T2 of
            TopicMatch ->
                wave_db:push(<<"queue:", DeviceID/binary>>, [Topic, MsgID]),
                wave_db:incr(<<"msg:", MsgID/binary, ":refcount">>);

            _     ->
                pass
        end

        || {T2, DeviceID} <- R
    ],

    {reply, ok, State};

handle_call(_,_,State) ->
    {reply, ok, State}.

handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.

terminate(_,_) ->
    lager:error("~p terminated", [?MODULE]),
    ok.

code_change(_, State, _) ->
    {ok, State}.


%%
%% INTERNAL FUNS
%%

-spec priv_register(binary(), list({TopicF::binary(), mqtt_qos()})) -> ok.
priv_register(_       , []) ->
    ok;
priv_register(DeviceID, [{TopicF, Qos} |T]) ->
    mqtt_topic_registry:subscribe(TopicF, Qos, {?MODULE, publish, self(), DeviceID}),
    priv_register(DeviceID, T).

