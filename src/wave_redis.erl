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

-module(wave_redis).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([connect/2, update/3, device/1, topic/2, topic/3]).

%
% new device connects
connect(DeviceID, Values) ->
    {ok, C} = application:get_env(wave, redis),

    Key   = "wave:deviceid:" ++ DeviceID,
    case eredis:q(C, ["HGET", Key, "state"]) of
        {ok, <<"connected">>} ->
            {error, exists};

        _             ->
            Pairs = lists:foldr(fun ({X,Y},Acc) -> [X,Y|Acc] end, [], Values),
            eredis:q(C, ["HMSET", Key|Pairs])
    end.

update(DeviceID, Key, Value) ->
    {ok, C} = application:get_env(wave, redis),

    eredis:q(C, ["HSET", "wave:deviceid:" ++ DeviceID, Key, Value]).

% save registered topic
% topics are stored in a redis list, per QOS
%
% i.e: wave:deviceid:foobar:qos:0:topics -> [topic1, topic2, ...]
%
topic(DeviceID, Topic, Qos) ->
    {ok, C} = application:get_env(wave, redis),
    eredis:q(C, ["LPUSH", <<"wave:deviceid:", DeviceID/binary, ":qos:", (erlang:integer_to_binary(Qos))/binary, ":topics">>, Topic]).


% returns saved topics
% for give DeviceID and Qos
%
% returns: [{Topic1, Qos}, {Topic2, Qos}, ...]
%
topic(DeviceID, Qos) ->
    {ok, C} = application:get_env(wave, redis),
    {ok, Topics} = eredis:q(C, ["LRANGE", <<"wave:deviceid:", DeviceID/binary, ":qos:", (erlang:integer_to_binary(Qos))/binary, ":topics">>, 0, -1]),

    lists:map(fun(T) -> {T, 0} end, Topics).



device({id, Err={error, _}}) ->
    Err;
device({id, {ok, ID}})->
    lager:info("id=~p", [ID]),
    decode(eget(<<"d:", ID/binary>>));

device({deviceid, DeviceID}) ->
    lager:info("id>=~p", [DeviceID]),
    device({id, eget(<<"d:", DeviceID/binary, ":id">>)}).

eget(Q) ->
    {ok, C} = application:get_env(wave, redis),
    case eredis:q(C, ["GET", Q]) of
        {error, Err}    ->
            {error, Err};
        {ok, undefined} ->
            {error, notfound};

        Res ->
            lager:info("res=~p", [Res]),
            Res
    end.

decode({error, Err}) ->
    {error, Err};
decode({ok, Raw})    ->
    {Obj} = jiffy:decode(Raw),
    {ok, Obj}.
