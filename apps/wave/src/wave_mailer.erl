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

-module(wave_mailer).
-author("Guillaume Bour <guillaume@bour.cc>").


-export([start_link/0, init/0]).
-export([send/3]).

start_link() ->
    spawn_link(?MODULE, init, []).

init() ->
    lager:debug("init"),
    loop().
%
% stack up mail
send(To, Title, Content) ->
    wave_db:push(mailQ, term_to_binary({To, Title, Content})).


loop() ->
    lager:debug("loop"),
    receive
        Msg -> 
            lager:debug("received ~p", [Msg])
    after 5000 ->
            timeout
    end,

    case wave_db:pop(mailQ) of
        {ok, undefined} -> undefined;
        {ok, Payload}   -> 
            expedite(binary_to_term(Payload)),

            self() ! run
    end,

    loop().


expedite({To, Title, Content}) ->
    lager:debug("sending mail to ~p: ~p / ~p", [To, Title, Content]),

    Cmd = <<"/usr/bin/mailx -s '", Title/binary, "' ", To/binary>>,
    Port = erlang:open_port({spawn, Cmd}, [exit_status]),
    erlang:port_command(Port, Content),
    erlang:port_close(Port).

