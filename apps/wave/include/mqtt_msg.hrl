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


-record(mqtt_msg, {
    type           :: mqtt_verb(),
    dup     = 0    :: integer(),
    qos     = 0    :: integer(),
    retain  = 0    :: integer(),

    payload = []   :: list({atom(), any()})
}).

-type mqtt_msg()  :: #mqtt_msg{}.
-type mqtt_verb() :: 'CONNECT'|'CONNACK'|'PUBLISH'|'PUBACK'|'PUBREC'|'PUBREL'|'PUBCOMP'|'SUBSCRIBE'|'UNSUBSCRIBE'
                    |'SUBACK'|'UNSUBACK'|'PINGREQ'|'PINGRESP'|'DISCONNECT'.

-type mqtt_qos()    :: 0|1|2.
-type mqtt_retain() :: 0|1.

-type mqtt_topic()      :: unicode:unicode_binary().
-type mqtt_clientid()   :: unicode:unicode_binary().

%%
%% OTP compatibility macros
%%

-define(SEED, erlang:phash2([node()]), erlang:monotonic_time(), erlang:unique_integer()).
-define(GENFSM_STOP(Ref, Reason, Timeout), gen_fsm:stop(Ref, Reason, Timeout)).
-define(TIME, erlang:system_time(seconds)).

-ifdef(OTP_RELEASE_17).
    % erlang:monotinic_time() & erlang:unique_integer() are not available on OTP < 18
    %
    -undef(SEED).
    -define(SEED, erlang:now()).

    % gen_fsm:stop() implemented since 18.0
    %
    -undef(GENFSM_STOP).
    -define(GENFSM_STOP(Ref, Reason, Timeout), gen_fsm:send_all_state_event(Ref, {disconnect, Reason})).

    %
    %
    -undef(TIME).
    -define(TIME, (fun() -> {Mega,Sec,_} = os:timestamp(), (Mega*1000000 + Sec) end)()).
-endif.
