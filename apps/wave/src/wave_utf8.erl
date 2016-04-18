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

-module(wave_utf8).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([validate/1]).

% @doc validate utf8 binary string
%
%
-spec validate(unicode:unicode_binary()) -> ok | {invalid, string(), integer()}.
validate(<<>>) ->
    ok;
% NULL character
validate(<<H/utf8, _/binary>>) when H =:= 0  ->
    {invalid, "MQTT-1.5.3-2", H};
% control characters
validate(<<H/utf8, _/binary>>) when H >= 16#01, H =< 16#1F     ->
    {invalid, "MQTT-1.5.3-2", H};
validate(<<H/utf8, _/binary>>) when H >= 16#7F, H =< 16#97     ->
    {invalid, "MQTT-1.5.3-2", H};
% invalid unicode range
validate(<<H/utf8, _/binary>>) when H >= 16#D800, H =< 16#D8FF ->
    {invalid, "MQTT-1.5.3-1", H};
validate(<<_/utf8, Rest/binary>>) ->
    validate(Rest);
validate(<<_/binary>>) ->
    {invalid, "not utf8 character"}.
