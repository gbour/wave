
-module(wave_mod_ws_usercreate).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([init/2,allowed_methods/2, content_types_accepted/2, content_types_provided/2, from_usercreate/2, terminate/2, resource_exists/2, handle/2]).

init(Req, Opts) ->
    io:format("init~n"),
    {ok, Req, state}.

handle(Req, State) ->
    io:format("handler~n"),
    {ok, Req, State}.

allowed_methods(Req, State) ->
    %{[<<"HEAD">>, <<"GET">>, <<"PUT">>, <<"POST">>, <<"DELETE">>], Req, State}.
    {[<<"PUT">>], Req, State}.

content_types_accepted(Req, State) ->
    {[
        {<<"application/json">>, from_usercreate}
    ], Req, State}.

content_types_provided(Req, State) ->
    {[
        {<<"application/json">>, undefined}
    ], Req, State}.

resource_exists(Req, State) ->
   {true, Req, State}.

from_usercreate(Req, State) ->
    io:format("plop2 ~p~n",[Req]),

   % {true, Req, State}.

    Body = <<"{\"validation_link\": \"foo/bar/x3eooorj484f1ammdpk4dd43fl\", \"expiration\": \"2015-01-22T20:14:23Z\"}">>,
    {ok, Reply} = cowboy_req:reply(201, [], Body, Req),
    %{halt, Reply, State}.
    {true, Reply, State}.

terminate(Req, State) ->
    ok.

