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

-export([get/1, set/2, set/3, del/1]).
-export([incr/1, decr/1]).
-export([
        append/2, push/2, pop/1, range/1, del/2]).


%% @doc
%% Function: get/1
%% Purpose: get Value from database
%% Returns:
%%
-spec get({s, binary()}) -> {ok, any()}|{error, atom()|binary()}.
get({s, Key}) ->
    sharded_eredis:q(["GET", Key]);
%% get hash field value
get({h, Key, Field}) ->
    sharded_eredis:q(["HGET", Key, Field]).

%% @doc
%% Function: set/2
%% Purpose: insert key/value in database
%%
-spec set({s|h, binary()}, any()) -> {ok, binary()}|{error, atom()|binary()}.
set({s, Key}, Value) ->
    sharded_eredis:q(["SET", Key, Value]);
set({h, Key}, Value) when is_list(Value) ->
    sharded_eredis:q(["HMSET", Key | Value]);
set({h, Key}, Value) when is_map(Value) ->
    % #{A => B}  => [A, B].
    Params = lists:flatmap(fun({X,Y}) -> [X,Y] end, maps:to_list(Value)),
    set({h, Key}, Params);
set({h, Key, Field}, Value) ->
    sharded_eredis:q(["HSET", Key, Field, Value]).

%% @doc
%%
%%
-spec set({s|h, binary()}, any(), list()) -> {ok, binary()}|{error, atom()|binary()}.
set(Key, Value, []) ->
    set(Key, Value);
set(Key={_,K}, Value, [{expiration,Expiration}|Opts]) -> 
    lager:debug("set db expiration: ~p", [Expiration]),

    case set(Key, Value, Opts) of
        {ok, X} ->
            case sharded_eredis:q(["EXPIRE", K, Expiration]) of
                {ok, _} -> {ok, X};
                Err2    -> Err2
            end;

        Err -> Err
    end.

-spec del(binary()) -> {ok, binary()}|{error, atom()|binary()}.
del(Key) ->
    sharded_eredis:q(["DEL", Key]).

-spec del(binary(), integer()) -> {ok, binary()}|{error, atom()|binary()}.
del(Key, Start) ->
    sharded_eredis:q(["LTRIM", Key, Start, -1]).


%%
%% Counters operations
%%
-spec incr(binary()) -> {ok, binary()}|{error, atom()|binary()}.
incr(Key) ->
    sharded_eredis:q(["INC", Key]).

-spec decr(binary()) -> {ok, binary()}|{error, atom()|binary()}.
decr(Key) ->
    sharded_eredis:q(["DECR", Key]).


%%
%% Lists specific operations
%%
-spec append(binary(), any()) -> {ok, binary()}|{error, atom()|binary()}.
append(List, Value) ->
    sharded_eredis:q(["LPUSH", List, Value]).

-spec push(binary(), any()) -> {ok, binary()}|{error, atom()|binary()}.
push(List, Value) when is_list(Value) ->
    sharded_eredis:q(["RPUSH", List|Value]);

push(List, Value) ->
    sharded_eredis:q(["RPUSH", List, Value]).

-spec pop(binary()) -> {ok, binary()}|{error, atom()|binary()}.
pop(List) ->
    sharded_eredis:q(["LPOP", List]).

-spec range(binary()) -> {ok, binary()}|{error, atom()|binary()}.
range(List) ->
    sharded_eredis:q(["LRANGE", List, 0, -1]).
