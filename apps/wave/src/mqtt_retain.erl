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

-module(mqtt_retain).
-author("Guillaume Bour <guillaume@bour.cc>").

-include("mqtt_msg.hrl").

% public API
-export([store/1]).

-spec store(mqtt_msg()) -> pass|retained.
store(#mqtt_msg{type='PUBLISH', retain=0}) ->
    % non-retainable message
    pass;
store(#mqtt_msg{type='PUBLISH', retain=1, qos=Qos, payload=Payload}) ->
    Topic = proplists:get_value(topic, Payload),
    Data  = proplists:get_value(data, Payload),

    store2(Topic, Data, Qos),
    retained.

% empty payload: delete retained message
store2(Topic, <<>>, _) ->
    lager:debug("deleting retained message under ~p", [Topic]),
    wave_db:del(<<"retain:", Topic/binary>>),
    ok;
store2(Topic, Data, Qos) ->
    lager:debug("saving retained message (t= ~p, m=~p)", [Topic, Data]),
    wave_db:set({h, <<"retain:", Topic/binary>>}, #{data => Data, qos => Qos}),
    ok.

