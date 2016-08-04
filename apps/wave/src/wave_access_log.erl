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

-module(wave_access_log).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(gen_server).


-record(state, {
    enabled = false,
    logfile,
    fh
}).


%
-export([log/1]).
% gen_server API
-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Args) ->
    %NOTE: currently we set ONE global registry service for the current erlang server
    gen_server:start_link({local,?MODULE}, ?MODULE, Args, []).

%TODO: if log not enable, we should not start gene_server
%      so log cast will fail silently (avoid data copy)
%      (see wave_sup how to not restart srv in this case)
init(Args) ->
    Enabled = proplists:get_value(enabled, Args),
    LogFile = proplists:get_value(logfile, Args),

    {ok, Fh} = case Enabled of
        true -> file:open(LogFile, [write,append]);
        _    -> {ok, undefined}
    end,

    {ok, #state{enabled = Enabled, logfile = LogFile, fh = Fh}}.

%%
%% PUBLIC API
%%

log(Fields) ->
    gen_server:cast(?MODULE, {log, Fields}).

%%
%% PRIVATE API
%%

handle_call(_,_,State) ->
    {reply, ok, State}.

handle_cast({log, _}, State=#state{enabled=false}) ->
    {noreply, State};
handle_cast({log, Fields=#{verb := Verb, status_code := Code, ua := Ua}}, State=#state{fh=Fh}) ->
    Date = qdate:to_string("d/M/Y:H:i:s O", "Europe/Paris", calendar:universal_time()),
    Uri  = maps:get(uri , Fields, ""),
    Ip   = maps:get(ip  , Fields, "-"),
    Size = maps:get(size, Fields, "-"),

    io:format(Fh, "~s - - [~s] \"~s ~s\" ~B ~s \"-\" \"~s\"~n",
              [Ip, Date, Verb, Uri, Code, wave_utils:str(Size), Ua]),

    {noreply, State};

handle_cast(_, State) ->
    {noreply, State}.


handle_info(_, State) ->
    {noreply, State}.


terminate(_, #state{fh=Fh}) ->
    file:close(Fh),
    ok.


code_change(_, State, _) ->
    {ok, State}.

%%
%% PRIVATE FUNS
%%
