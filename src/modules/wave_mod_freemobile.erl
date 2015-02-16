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

-module(wave_mod_freemobile).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).


-record(state, {
    username,
    password    
}).

%
-export([trigger/4]).
% gen_server API
-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Conf) ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [Conf], []).

init([Conf]) ->
    lager:info("starting ~p module ~p", [?MODULE, Conf]),
    Username = proplists:get_value(username, Conf),
    Password = proplists:get_value(password, Conf),

    [
        %lager:info("topic= ~p", [Topic]),
        mqtt_topic_registry:subscribe(erlang:list_to_binary(Topic), {?MODULE,trigger,self()})
        
        || Topic <- proplists:get_value(topics, Conf)
    ],
    {ok, #state{username=Username, password=Password}}.

%%
%% PUBLIC API
%%

%
trigger(Pid, Topic, Payload, _Qos) ->
    P = jiffy:decode(Payload, [return_maps]),
    lager:info("trigger ~p", [P]),

    case maps:find(<<"action">>, P) of 
        {ok, Action} ->
            gen_server:cast(Pid, {Action, P});

        _ ->
            lager:info("no action found"),
            pass
    end.



%%
%% PRIVATE API
%%

handle_call(_,_,State) ->
    {reply, ok, State}.


handle_cast({<<"login">>, Msg}, State=#state{username=Username, password=Password}) ->
    User = hget(<<"user">>  , Msg),
    Srv  = hget(<<"server">>, Msg),
    From = hget(<<"from">>  , Msg),
    Date = hget(<<"at">>    , Msg),

    send_sms({Username,Password}, User, Srv, From, Date),
    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.


hget(Key, Dict) ->
    case maps:find(Key, Dict) of
        {ok, Value} -> Value;
        error       -> <<"undefined">>
    end.

send_sms({Username, Password}, User, Srv, From, Date) ->
    lager:info("send_sms: ~p ~p ~p ~p", [User, Srv, From, Date]),

    % [SEC] albator: *jdoe* connected successfully from _1.2.3.4_ at 2014/10/22 11:22:33
    Msg = <<"[SEC] ",Srv/binary,":: *",User/binary, 
        "* successfully connected from _",From/binary,"_ at ",Date/binary>>,

    lager:info("msg= ~p", [Msg]),
    {ok, Conn} = shotgun:open("smsapi.free-mobile.fr", 443, https),
    R = shotgun:get(Conn, "/sendmsg?user="++Username++"&pass="++Password++"&msg="++ 
        http_uri:encode(erlang:binary_to_list(Msg))),
    lager:info("~p", [R]),
    shotgun:close(Conn),

    ok.


