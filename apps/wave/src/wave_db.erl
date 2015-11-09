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

-module(wave_db).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([get/1, set/2, set/3,
        push/2, pop/1
    ]).

get(Key) ->
    sharded_eredis:q(["GET", Key]).

set(Key, Value) when is_map(Value) ->
    % #{A => B}  => [Key, A, B].
    Param = lists:flatmap(fun({X,Y}) -> [X,Y] end, maps:to_list(Value)),
    {ok, <<"OK">>} = sharded_eredis:q(["HMSET", Key | Param]),
    
    ok;

set(Key, Value) ->
    noop.

% set with expiration
set(Key, Value, Expiration) ->
    case set(Key, Value) of
        ok ->
            {ok, _ } = sharded_eredis:q(["EXPIRE", Key, Expiration]),
            ok;

        noop ->
            noop
    end.

push(List, Value) ->
    {ok, _} = sharded_eredis:q(["RPUSH", List, Value]),
    ok.

pop(List) ->
    sharded_eredis:q(["LPOP", List]).
