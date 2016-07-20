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

%%
%% fake ranch transport
%%

-module(wave_websocket).
-author("Guillaume Bour <guillaume@bour.cc>").


%%
%%TODO: need to implement missing functions (even if empty)
%%TODO: use a gen_server instead
%%-behaviour(ranch_transport).

-export([start/1, init/2, name/0, peername/1, recv/3, send/2, close/1]).
-ifdef(DEBUG).
    -export([debug_getstate/1]).
-endif.

-record(state, {
    parent      = undefined :: pid(),   % ranch websocket handler
    child       = undefined :: pid(),   % mqtt_ranch_protocol instance

    child_state = undefined :: undefined | await | shutdown,

    % binary buffers
    in_buf      = <<>>      :: binary() % input buffer  (packets received from network)
}).

%%
%% PUBLIC API
%%

-spec start({inet:ip_address(), inet:port_number()}) -> {ok, pid()}.
start(Peer) ->
    %TODO: using proc_lib:start_link()
    Pid = erlang:spawn(?MODULE, init, [self(), Peer]),
    {ok, Pid}.

-spec name() -> ws.
name() ->
    ws.


% return peer ip/port
% NOTE: we currently store it in process dictionary,
%       could also be stored in state and queried with sys:get_state()
%       (implementing {system,{<0.4525.0>,#Ref<0.0.3.17176>},get_state} message handler)
-spec peername(pid()) -> {ok, {inet:ip_address(), inet:port_number()}}.
peername(Socket) ->
    {dictionary, Dict} = erlang:process_info(Socket, dictionary),
    {ok, proplists:get_value(peer, Dict)}.

% read value (from network to session)
-spec recv(pid(), integer(), integer()|infinity) -> {ok, binary()} | {error, closed|eacces|timeout}.
recv(Socket, Length, Timeout) ->
    Socket ! {recv, self(), Length},

    % wait response (blocking until Timeout)
    receive
        Resp -> Resp
    after
        Timeout -> {error, timeout}
    end.

-spec send(pid(), binary()) -> ok | {error, closed|eacces}.
send(Socket, Packet) ->
    Socket ! {send, self(), Packet},
    receive Response -> Response end.

-spec close(pid()) -> ok.
close(Socket) ->
    Socket ! shutdown,
    ok.

-ifdef(DEBUG).
-spec debug_getstate(pid()) -> any().
debug_getstate(Pid) ->
    Pid ! {get_state, self()},

    receive State -> State end.
-endif.


%%
%% PRIVATE API
%%

-spec init(pid(), {inet:ip_address(), inet:port_number()}) -> ok.
init(ParentPid, Peer) ->
    % storing peer infos in process dictionary
    erlang:put(peer, Peer),

    % starting ranch protocol handler for mqtt
    {ok, ChildPid} = mqtt_ranch_protocol:start_link(undefined, self(), wave_websocket, []),

    % we want to know when ranch websocket handler dies
    monitor(process, ParentPid),
    %link(ParentPid),
    %process_flag(trap_exit, true),

    loop(#state{parent=ParentPid, child=ChildPid}).

-spec loop(undefined|#state{}) -> ok.
loop(undefined) ->
    lager:error("end loop"),
    ok;
loop(State=#state{parent=Parent, child=Child, child_state=CState, in_buf=InBuf}) ->
            lager:error("loop"),
    State2 = receive
        % incoming packet from network
        {feed, Pkt} ->
            lager:error("feed"),
            case CState of
                await   -> Child ! {ok, Pkt}, State#state{child_state=undefined};
                _       -> State#state{in_buf= <<InBuf/binary, Pkt/binary>>}
            end;

        {recv, Pid, _Length} ->
            on_pid_match(recv, Pid, State, fun() ->
                case {CState, InBuf} of
                    {shutdown, _   } -> Child ! {error, closed}, State;
                    {_       , <<>>} -> State#state{child_state=await};
                    _                -> Child ! {ok, InBuf}, State#state{in_buf= <<>>}
                end
            end);

        {send, Pid2, Pkt} ->
            on_pid_match(send, Pid2, State, fun() ->
                Parent ! {response, Pkt}, Child ! ok, State
            end);

        % shutdown notice from session (received DISCONNECT)
        shutdown ->
            % notify ranch to stop (close socket)
            Parent ! stop,
            Child  ! {error, closed},
            undefined;

        % notice parent has stopped
        {'DOWN', _, process, Parent, _} ->
        %{'EXIT', Parent, Reason} ->
            case CState of
                await -> Child ! {error, closed}, undefined;
                _     -> State#state{child_state=shutdown}
            end;

        {get_state, Pid} ->
            Pid ! State,
            State;

        _Err ->
            lager:notice("invalid cmd: ~p", [_Err]),
            State
    end,

    loop(State2).


on_pid_match(     _, Child, State=#state{child=Child}, Fun) ->
    Fun();
on_pid_match(Action, Pid  , State, _) ->
    lager:notice("Process ~p not legitimate to ~p ws data through ~p channel ~p", [Pid, Action, self()]),
    Pid ! {error, eacces},
    State.
