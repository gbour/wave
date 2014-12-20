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

-export([check/5]).


check(device, _,_,_,[]) ->
    {error, wrong_id};
check(device, DeviceID, Username, Password, Settings) ->
    lager:info("auth check ~p (~p: ~p)", [DeviceID, Username, Password]),
    DbUsername = proplists:get_value(<<"username">>, Settings),
    DbPassword = proplists:get_value(<<"password">>, Settings),

    credential(Username, Password, {DbUsername, DbPassword}).

credential(Username, Password, {Username, Password}) ->
    {ok, match};
credential(_,_,_) ->
    {error, bad_credentials}.

% Set device state (connected or not)
% State: true|false
%
%connected(DeviceID, State) ->
%

%
% return whether this device is already connected or not
%connected(DeviceID)

as_proplist({ok, Resp}) ->
    {ok, as_proplist(Resp, [])};
as_proplist(Err) ->
    Err.

as_proplist([K,V|T], Acc) ->
    as_proplist(T, Acc ++ [{K,V}]);
as_proplist([], Acc) ->
    Acc.
