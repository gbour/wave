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

-module(mqtt_topic_match).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([fields/1, match/2]).

% Count wildcard characters
%
% fields(<<"foo/bar">>)     : []
% fields(<<"foo/+/bar">>)   : [0]
% fields(<<"foo/+/bar/+">>) : [0,1]
% fields(<<"foo/bar/#">>)   : [0]
%
-spec fields(binary()) -> list(integer()).
fields(TopicName) ->
    lists:seq(0, fields(TopicName, -1)).

-spec fields(binary(), integer()) -> integer().
fields(<<>>  , C) ->
    C;
fields(<<$#>>, C) ->
    C+1;
fields(<<$+, Rest/binary>>, C)  ->
    fields(Rest, C+1);
%TODO: raise exception
%fields(<<$#, Rest/binary>>, C)  ->
%    fields(Rest, C+1);
fields(<<_:1/binary, Rest/binary>>, C) ->
    fields(Rest, C).


% tries to match a message topic with a subscribed topic regex
% if match, also extract values matching wildcards
%
%NOTE: BUG OR NOT ?? 
%   11> mqtt_topic_match:match(<<"foo/ba+">>, {<<"foo/bar">>,[0]}).
%   {ok,[{0,<<"r">>}]}
%
-spec match(Re :: binary(), {Topic :: binary(), Fields :: list(integer())}) -> 
        fail | {ok, list(mqtt_topic_registry:match())}.
match(Re, {Topic, Fields}) ->
    case match(Re, Topic, []) of
        {ok, []} ->
            {ok, []};
        {ok, Matches} ->
            % /!\ Matches was built in reverse order
            {ok, fieldsmap(Matches, Fields, [])};
        fail ->
            fail
    end.


% match or not a topic with a subscription regex 
%
% ie:
%   /foo/bar MATCH         /foo/+
%   /foo/bar MATCH        /foo/#
%   /foo/bar MATCH        /foo/bar
%   /foo/bar DO NOT MATCH /foo/baz
%
% if matches, returns 'sections' matching wildcards
%
% match(<<"/foo/bar">>, <<"/foo/bar">>) -> {ok, []}
% match(<<"/foo/+">>  , <<"/foo/bar">>) -> {ok, [<<"bar">>]}
% match(<<"/#">>      , <<"/foo/bar">>) -> {ok, [<<"foo/bar">>]}
%
% NOTE: returned matches are in reverse order (because of optimized list appending)
%
-spec match(Re :: binary(), Topic :: binary(), Matches :: list(binary())) -> fail | {ok, list(binary())}.
match(<<$#>>, _Match, Matches) ->
    %lager:info("# match ~p", [_Match]),
    {ok, [_Match|Matches]};
match(<<"/#">>, <<$/, _Match/binary>>, Matches) ->
    %lager:info("2: # match ~p", [_Match]),
    {ok, [_Match|Matches]};
match(<<"/#">>, <<"">> = _Match, Matches) ->
    %lager:info("3: # match ~p", [_Match]),
    {ok, [_Match|Matches]};
match(<<C:1/binary, Re/binary>>, <<C:1/binary, Rest/binary>>, Matches) ->
    match(Re, Rest, Matches);
match(<<$+, _/binary>>, <<$#, _/binary>>, _) ->
    fail;
match(<<$+, Re/binary>>, Rest, Matches) ->
    {Rest2, Match} = eat(Rest, <<"">>),
    %lager:info("+ match ~p", [Match]),
    match(Re, Rest2, [Match|Matches]);
match(<<"">>, <<"">>, M) ->
    {ok, M};
match(_, _, _) ->
    fail.


% "Eat" all topic characters until next '/' separator or end of string
% returns 'section' string
%
% eat(<<"foo/bar/baz">>,<<"">>) -> {<<"bar/baz">>, <<"foo">>}
%
-spec eat(Topic :: binary(), Accumulator :: binary()) -> {binary(), binary()}.
eat(<<>>, Acc) ->
    {<<>>, Acc};
eat(Rest= <<$/, _/binary>>, Acc) ->
    {Rest, Acc};
eat(<<H:1/binary, Rest/binary>>, Acc) ->
    eat(Rest, <<Acc/binary, H/binary>>).



% merge Matches with match positions, also reversing to right order
%
% fieldsmap([<<"bar">>, <<"foo">>], [1,0], []) -> [{1,<<"foo">>}, {0, <<"bar">>}]
%
%NOTE: match positions is in wrong order. BUG OR NOT ?
%
-spec fieldsmap(Matches :: list(binary()), Fields :: list(integer()), Accumulator :: list()) ->
        list(mqtt_topic_registry:match()).
fieldsmap(_, [], Acc) ->
    Acc;
fieldsmap([H|T], [F|Fields], Acc) ->
    fieldsmap(T, Fields, [{F,H}|Acc]);
fieldsmap([], _, Acc) ->
    Acc.

