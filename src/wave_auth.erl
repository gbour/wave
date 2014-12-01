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

-module(wave_auth).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([check/4]).

check(device, DeviceID, Username, Password) ->
    lager:info("auth check ~p (~p: ~p)", [DeviceID, Username, Password]),
    {ok, C} = eredis:start_link(),
    {ok, Key} = eredis:q(C, ["GET", ["key:device/deviceid/", DeviceID]]),
    lager:info("check= ~p", [Key]),

    case Key of
        undefined ->
            {error, wrong_id};

        Key ->
            {ok, Record} = as_proplist(eredis:q(C, ["HGETALL", Key])),
            lager:info("rec= ~p", [Record]),

            case {proplists:get_value(<<"username">>, Record), proplists:get_value(<<"password">>, Record)} of
                {Username, Password} ->
                    {ok, Record};
                _                    ->
                    {error, bad_credentials}
            end
    end.

as_proplist({ok, Resp}) ->
    {ok, as_proplist(Resp, [])};
as_proplist(Err) ->
    Err.

as_proplist([K,V|T], Acc) ->
    as_proplist(T, Acc ++ [{K,V}]);
as_proplist([], Acc) ->
    Acc.
