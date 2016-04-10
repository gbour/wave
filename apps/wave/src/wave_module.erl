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

-module(wave_module).
-author("Guillaume Bour <guillaume@bour.cc>").

%% @doc initialize and start module
%%      it may start a gen_server() or just register MQTT hook(s)
%%
%% returns:
%%   . ok             : everything goes well
%%   . {error, Error} : something wrong happens
%%
-callback start(Options::proplists:proplist(any())) -> ok|{error, atom()}.

%% @doc stop module
%%      it MUST stop gen_server() if any, and unregister hook(s)
%%
%% returns:
%%   . ok
%%   . {error, Error}
%%
-callback stop() -> ok|{error, atom()}.

