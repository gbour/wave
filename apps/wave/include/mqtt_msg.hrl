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
    retain  = 0    :: integer(),
    qos     = 0    :: integer(),
    dup     = 0    :: integer(),

    payload = []   :: list({atom(), any()})
}).

-type mqtt_msg()  :: #mqtt_msg{}.
-type mqtt_verb() :: 'CONNECT'|'CONNACK'|'PUBLISH'|'PUBACK'|'PUBREC'|'PUBREL'|'PUBCOMP'|'SUBSCRIBE'|'UNSUBSCRIBE'
                    |'SUBACK'|'UNSUBACK'|'PINGREQ'|'PINGRESP'|'DISCONNECT'.


% erlang:monotinic_time() & erlang:unique_integer() are not available on OTP < 18
%
-ifdef(OLD_SEED_WAY).
    -define(SEED, erlang:now()).
-else.
    -define(SEED, erlang:phash2([node()]), erlang:monotonic_time(), erlang:unique_integer()).
-endif.
