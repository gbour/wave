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

-export([init/2, allowed_methods/2, content_types_accepted/2, content_types_provided/2, handle/2, terminate/2]).


init(Req, Opts) ->
    {cowboy_rest, Req, Opts}.

allowed_methods(Req, State) ->
    %{['HEAD', 'GET', 'PUT', 'POST', 'DELETE'], Req, State}.
    {[<<"HEAD">>, <<"GET">>, <<"PUT">>, <<"POST">>, <<"DELETE">>], Req, State}.

content_types_accepted(Req, State) ->
    {[
        {<<"application/json">>, handle}
    ], Req, State}.

content_types_provided(Req, State) ->
    {[
        {<<"application/json">>, handle}
    ], Req, State}.

handle(Req, State) ->
    io:format("plop ~p~n",[Req]),

    Method  = cowboy_req:method(Req),
    Binding = cowboy_req:bindings(Req),
    Qs      = cowboy_req:qs(Req),
    Path    = cowboy_req:path_info(Req), % [...]
    io:format("binds: ~p ~p ~p ~p~n", [Method, Binding, Qs, Path]),

    Body = <<"{\"validation_link\": \"foo/bar/x3eooorj484f1ammdpk4dd43fl\", \"expiration\": \"2015-01-22T20:14:23Z\"}">>,
    {Body, Req, State}.

ws([<<"management">>,<<"user">>,<<"create">>], Req) ->
    ok.


terminate(Req, State) ->
    ok.

