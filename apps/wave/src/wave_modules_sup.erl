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

-module(wave_modules_sup).
-author("Guillaume Bour <guillaume@bour.cc>").
-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Args, Type), {I, {I, start_link, [Args]}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, {{one_for_one, 5, 10}, load_modules()}}.

% return list of Child Specifications
-spec load_modules() -> list(term()).
load_modules() ->
    {ok, Mods} = application:get_env(wave, modules),

    Enabled = proplists:get_value(enabled, Mods),
    Opts    = proplists:get_value(settings, Mods, []),

    module_init(Enabled, Opts, []).

-spec module_init(list(atom), any(), list(term())) -> list(term()).
module_init([], _, ChildSpecs) ->
    ChildSpecs;
module_init([Modname|Rest], Opts, ChildSpecs) ->
    lager:info("starting module: ~p", [Modname]),
    Mod  = (wave_utils:atom("wave_mod_" ++ wave_utils:str(Modname))),
    Args = proplists:get_value(Modname, Opts, []),   

    % webservice entries
%    case erlang:function_exported(M, ws, 0) of
%        true  -> M:ws();
%        false -> ok
%    end,

    module_init(Rest, Opts, [?CHILD(Mod, Args, worker) | ChildSpecs]).
