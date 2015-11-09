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

-module(mqtt_topic_match).
-author("Guillaume Bour <guillaume@bour.cc>").

%-export([validate/1, match/2]).
-export([fields/1, match/2]).

%validate(<<>>) ->
%    {error, invalid};
%validate(Topic) ->
%    validate(x).
%
%validate(_, <<>>)   ->
%    text;
%validate(<<$/>>, <<$#>>) ->
%    rx;
%validate(<<>>  , <<$#>>) ->
%    rx;
%validate(<<$/>>, <<$+, Rest/binary>>) ->
%    union(
%      validate(

fields(TopicName) ->
    lists:seq(0, fields(TopicName, -1)).

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

match(Re, {Topic, Fields}) ->
    case match(Re, Topic, []) of
        {ok, []} ->
            {ok, []};
        {ok, Matches} ->
            % /!\ Matches was built in reverse order
            {ok, fieldsmap(Matches, Fields, [])};
        fail ->
            fail
    end;

match(Re, Topic) ->
    case match(Re, Topic, []) of
        {ok, []} ->
            {ok, []};
        {ok, Matches} ->
            % /!\ Matches was built in reverse order
            {ok, fieldsmap(Matches, lists:reverse(lists:seq(0, length(Matches)-1)), [])};
        fail ->
            fail
    end.


%
% /foo/bar
% /foo/+
% /foo/#
%
match(<<$#>>, _Match, Matches) ->
    lager:info("# match ~p", [_Match]),
    {ok, [_Match|Matches]};
match(<<"/#">>, <<$/, _Match/binary>>, Matches) ->
    lager:info("2: # match ~p", [_Match]),
    {ok, [_Match|Matches]};
match(<<"/#">>, <<"">> = _Match, Matches) ->
    lager:info("3: # match ~p", [_Match]),
    {ok, [_Match|Matches]};
match(<<C:1/binary, Re/binary>>, <<C:1/binary, Rest/binary>>, Matches) ->
    match(Re, Rest, Matches);
match(<<$+, Re/binary>>, Rest, Matches) ->
    {Rest2, Match} = eat(Rest, <<"">>),
    lager:info("+ match ~p", [Match]),
    match(Re, Rest2, [Match|Matches]);
match(<<"">>, <<"">>, M) ->
    {ok, M};
match(_, _, _) ->
    fail.

eat(<<>>, Acc) ->
    {<<>>, Acc};
eat(Rest= <<$/, _/binary>>, Acc) ->
    {Rest, Acc};
eat(<<H:1/binary, Rest/binary>>, Acc) ->
    eat(Rest, <<Acc/binary, H/binary>>).

fieldsmap([H|T], [F|Fields], Acc) ->
    fieldsmap(T, Fields, [{F,H}|Acc]);
fieldsmap([], _, Acc) ->
    Acc.
