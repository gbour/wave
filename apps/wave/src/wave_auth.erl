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

-module(wave_auth).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).

-export([check/4]).
% gen_server API
-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Args) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

init(Args) ->
    ets:new(?MODULE, [set, named_table, private]),
    erlang:send_after(500, self(), {reload, proplists:get_value(file, Args)}),
    {ok, undefined}.

%%
%% PUBLIC API
%%

-spec check(true|false|undefined, DeviceID::binary(), Creds::{binary(), binary()},
            Setts::list({binary(), binary()})) -> {error, wrong_id|bad_credentials} | {ok, noauth|match}.
check(false, _,{undefined, _}, _) ->
    lager:debug("no auth required"),
    {ok, noauth};

% no username set
check( true, _, {undefined, _}, _) ->
    {error, bad_creds};
%NOTE: this situation should never happen (see [MQTT-3.1.2-22])
check(    _, _, {_, undefined}, _) ->
    {error, bad_creds};

check(    _, DeviceID, {User, Pwd}, Settings) ->
    lager:debug("auth check ~p (~p)", [DeviceID, User]),
    gen_server:call(?MODULE, {auth, DeviceID, User, Pwd}).

%%
%% PRIVATE API
%%

handle_call({auth, DeviceID, User, Password}, _, State) ->
    Match = case ets:lookup(?MODULE, User) of
        [{User, Hash}] ->
            lager:debug("user ~p found", [User]),
            case erlpass:match(Password, Hash) of
                true -> {ok, match};
                _    -> {error, bad_creds}
            end;

        _ -> 
            % make it harder to guess if Username exists or not
            % (as erlpass:match() takes around 600ms to execute)
            erlpass:match(<<"foo">>,<<"$2a$12$6zOUIP0NEwBupO7ATO.Hv..ZQq5WGmyZ0rCYGUoznFrYpFZkr8ppy">>),
            {error, bad_creds}
    end,
        
    {reply, Match, State};

handle_call(E,_,State) ->
    lager:error("call ~p", [E]),
    {reply, ok, State}.


handle_cast(E, State) ->
    lager:error("cast ~p", [E]),
    {noreply, State}.

handle_info({reload, File}, State) ->
    ets:delete_all_objects(?MODULE),

    % TODO: handle errors
    {ok, F} = file:open(File, [read,binary]),
    Count = fill_ets(F, file:read_line(F), 0),
    file:close(F),

    lager:debug("password file reloaded (~p lines found)", [Count]),
    {noreply, State};

handle_info(E, State) ->
    lager:error("info ~p", [E]),
    {noreply, State}.


terminate(_,_) ->
    ok.


code_change(_, State, _) ->
    {ok, State}.

%%
%% PRIVATE FUNS
%%

fill_ets(_, eof, Count) ->
    Count;
fill_ets(F, {ok, Line}, Count) ->
    S = size(Line)-1, % Line includes trailing \n
    <<Line2:S/binary, $\n>> = Line,

    [User, Pwd] = binary:split(Line2, <<$:>>),
    ets:insert(?MODULE, {User, Pwd}),

    fill_ets(F, file:read_line(F), Count+1).

