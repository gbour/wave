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

-module(webservice).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([init/2, content_types_provided/2, handle/2, terminate/2]).


init(Req, Opts) ->
    {cowboy_rest, Req, Opts}.

content_types_provided(Req, State) ->
    {[
        {<<"application/json">>, handle}
    ], Req, State}.

handle(Req, State) ->
    io:format("plop ~p~n",[Req]),

    Body = <<"{\"rest\": \"Hello World!\"}">>,
    {Body, Req, State}.

terminate(Req, State) ->
    ok.

