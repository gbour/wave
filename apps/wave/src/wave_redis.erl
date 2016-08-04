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

-module(wave_redis).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([device/1]).

-spec device({deviceid, binary()}) -> {error, notfound} 
                                        | {error, binary()|[binary()]}
                                        | {ok, jiffy:json_value()}.
device({deviceid, DeviceID}) ->
    device2({id, eget(<<"d:", DeviceID/binary, ":id">>)}).

device2({id, Err={error, _}}) ->
    Err;
device2({id, {ok, ID}})->
    decode(eget(<<"d:", ID/binary>>)).

-spec eget(binary()) -> {error, notfound} | wave_db:return().
eget(Q) ->
    case wave_db:get({s, Q}) of
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
