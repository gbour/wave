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

-module(mqtt_msg).
-author("Guillaume Bour <guillaume@bour.cc>").

-export([encode/1, decode/1]).

-include("include/mqtt_msg.hrl").

decode(<<Type:4, Dup:1, Qos:2, Retain:1, Rest/binary>>) ->
	T = type2atom(Type),
    {Len, Rest2} = rlength(Rest),
    <<P:Len/binary, Rest3/binary>> = Rest2,


    Msg = case decode_payload(T, {Len, P}) of
        {ok, Payload} ->
            {ok, #mqtt_msg{
                type=T,
                retain=Retain,
                qos=Qos,
                dup=Dup,

                payload = Payload
            }, Rest3};

        {error, Err} ->
            {error, Err, Rest3}
    end,

    %lager:debug("~p", [Msg]),
    Msg.

decode_payload(_, overflow) ->
    error;

%
% CONNECT
decode_payload('CONNECT', {Len, <<0:8, 6:8, "MQIsdp", Version:8/integer, Flags:8, Ka:16, Rest/binary>>}) ->
    lager:debug("CONNECTv3.1: ~p", [Flags]),
    Len2 = Len-12,

    <<User:1, Pwd:1, Retain:1, Qos:2, Will:1, Clear:1, _:1>> = <<Flags>>,

    {ClientID, Rest2} = decode_string(Rest),

    {Topic, Message, Rest3} = case Will of
        1 ->
            {_T, _R}  = decode_string(Rest2),
            {_M, _R2} = decode_string(_R),
            {_T, _M, _R2};
        _ -> {undefined, undefined, Rest2}
    end,

    {Username , Rest4} = case User of
        1 -> decode_string(Rest3);
        _ -> {undefined, Rest3}
    end,

    {Password, Rest5} = case Pwd of
        1 -> decode_string(Rest4);
        _ -> {undefined, Rest4}
    end,

    lager:debug("~p / ~p / ~p / ~p / ~p", [ClientID, Topic, Message, Username, Password]),

    {ok, [{clientid, ClientID}, {topic, Topic}, {message, Message}, {username, Username}, {password, Password}]};

decode_payload('PUBLISH', {Len, Rest}) ->
    lager:debug("PUBLISH (v3.1) ~p ~p", [Len, Rest]),

    {Topic, Rest2} = decode_string(Rest),
    %lager:debug("rest= ~p", [Rest2]),

    % if qos  = 1|2, read messageid (2 bytes)

    {ok, [{topic, Topic},{data, Rest2}]};

decode_payload('SUBSCRIBE', {Len, <<MsgID:16, Payload/binary>>}) ->
    lager:debug("SUBSCRIBE v3.1 ~p", [MsgID]),

	Topics = get_topics(Payload, []),
	lager:debug("topics= ~p", [Topics]),
	{ok, [{msgid, MsgID},{topics, Topics}]};

decode_payload('PINGREQ', {0, <<>>}) ->
	{ok, undefined};
decode_payload('PINGRESP', {0, <<>>}) ->
    {ok, undefined};

decode_payload('DISCONNECT', {0, <<>>}) ->
    lager:debug("DISCONNECT"),
    % not a real error, we just want to close the connection
    %TODO: return a disconnect object; and do cleanup upward
    %{error, disconnect};
    {ok, undefined};

decode_payload('CONNECT', {Len, <<0:8, 4:8, "MQTT", Level:8/integer, Flags:8, Rest/binary>>}) ->
    lager:debug("CONNECT"),
    {error, disconnect};

decode_payload('CONNACK', {Len, <<_:8, RetCode:8/integer>>}) ->
    lager:debug("CONNACK"),
    {ok, [{retcode, RetCode}]};

decode_payload('PUBACK', {Len, <<MsgID:16>>}) ->
    lager:debug("PUBACK. MsgID= ~p", [MsgID]),
    {ok, [{msgid, MsgID}]};

decode_payload('SUBACK', {Len, <<MsgID:16, Qos/binary>>}) ->
    lager:debug("SUBACK. MsgID= ~p", [MsgID]),
    {ok, [{msgid, MsgID}]};

decode_payload(Cmd, Args) ->
    lager:info("invalid:: ~p: ~p", [Cmd, Args]),

    {error, disconnect}.

get_topics(<<>>, Topics) ->
	Topics;
get_topics(Payload, Topics) ->
	{Name, Rest} = decode_string(Payload),
	<<_:6, Qos:2/integer, Rest2/binary>> = Rest,

	get_topics(Rest2, [{Name,Qos}|Topics]).


decode_string(<<>>) ->
    {<<>>, <<>>};
decode_string(Pkt) ->
    %lager:debug("~p",[Pkt]),
    <<Len:16/integer, Str:Len/binary, Rest2/binary>> = Pkt,
    %lager:debug("~p ~p ~p",[Len,Pkt, Rest2]),

    {Str, Rest2}.


%validate('CONNECT', level, 4) ->
%    ok;
%validate('CONNECT', level, _) ->
%    'connack_0x01';
%validate('CONNECT', <<

rlength(Pkt) ->
    rlength(Pkt, 1, 0).

rlength(_, 5, _) ->
    % remaining length overflow
    overflow;
rlength(<<0:1, Len:7/integer, Rest/binary>>, Mult, Acc) ->
    {Acc + Mult*Len, Rest};
rlength(<<1:1, Len:7/integer, Rest/binary>>, Mult, Acc) ->
    rlength(Rest, Mult+1, Acc + Mult*Len).


encode(#mqtt_msg{retain=Retain, qos=Qos, dup=Dup, type=Type, payload=Payload}) ->
    P = encode_payload(Type, Payload),

    lager:info("~p ~p", [P, is_binary(P)]),
	%<<Retain/integer, Qos, Dup, atom2type(Type)>>.
	<<
        % fixed headers
        (atom2type(Type)):4, Dup:1, Qos:2, Retain:1,
        % remaining length
        (erlang:size(P)):8,
		P/binary
    >>.

encode_payload('CONNECT', Opts) ->
    ClientID = proplists:get_value(clientid, Opts),
    Username = proplists:get_value(username, Opts),
    Password = proplists:get_value(password, Opts),

    <<
      6:16,       % protocol name
      <<"MQIsdp">>/binary,
      3:8,        % version
      % connect flags
      (setflag(Username)):1,
      (setflag(Password)):1,
      0:6,

      10:16,      % keep-alive

      (encode_string(ClientID))/binary,
      (encode_string(Username))/binary,
      (encode_string(Password))/binary
    >>;


encode_payload('PUBLISH', Opts) ->
    Topic = proplists:get_value(topic, Opts),
    MsgID = proplists:get_value(msgid, Opts),
    Content = proplists:get_value(content, Opts),

    <<
        (encode_string(Topic))/binary,
        %MsgID:16,
        % payload
        (bin(Content))/binary
    >>;

encode_payload('SUBSCRIBE', Opts) ->
    Topic = proplists:get_value(topic, Opts),
    lager:info("topic= ~p", [Topic]),

    <<
        1:16, % MsgID - mandatory
        (encode_string(Topic))/binary,
        0:8 % QoS
    >>;

encode_payload('CONNACK', [{retcode, RetCode}]) ->
    <<
      % var headers
      0:8,
      % payload
      RetCode:8
    >>;

encode_payload('PUBACK', Opts) ->
    MsgID = proplists:get_value(msgid, Opts),

    <<
        MsgID:16
    >>;

encode_payload('SUBACK', Opts) ->
	MsgId = proplists:get_value(msgid, Opts),
	Qos   = proplists:get_value(qos, Opts),

	<<
	  MsgId:16,
	  (encode_qos(Qos))/binary
	>>;

encode_payload('PINGREQ', _) ->
    <<>>;
encode_payload('PINGRESP', _) ->
	<<>>.

encode_string(undefined) ->
    <<>>;
encode_string(Str) ->
    <<
      (size(Str)):16,
      Str/binary
    >>.

encode_qos(undefined) ->
	<<>>;
encode_qos([]) ->
	<<>>;
encode_qos([H|T]) ->
	<<0:6, H:2/integer, (encode_qos(T))/binary>>.


atom2type('CONNECT')     ->  1;
atom2type('CONNACK')     ->  2;
atom2type('PUBLISH')     ->  3;
atom2type('PUBACK')      ->  4;
atom2type('PUBREC')      ->  5;
atom2type('PUBREL')      ->  6;
atom2type('PUBCOMP')     ->  7;
atom2type('SUBSCRIBE')   ->  8;
atom2type('SUBACK')      ->  9;
atom2type('UNSUBSCRIBE') -> 10;
atom2type('UNSUBACK')    -> 11;
atom2type('PINGREQ')     -> 12;
atom2type('PINGRESP')    -> 13;
atom2type('DISCONNECT')  -> 14.

type2atom(1)  -> 'CONNECT';
type2atom(2)  -> 'CONNACK';
type2atom(3)  -> 'PUBLISH';
type2atom(4)  -> 'PUBACK';
type2atom(5)  -> 'PUBREC';
type2atom(6)  -> 'PUBREL';
type2atom(7)  -> 'PUBCOMP';
type2atom(8)  -> 'SUBSCRIBE';
type2atom(9)  -> 'SUBACK';
type2atom(10) -> 'UNSUBSCRIBE';
type2atom(11) -> 'UNSUBACK';
type2atom(12) -> 'PINGREQ';
type2atom(13) -> 'PINGRESP';
type2atom(14) -> 'DISCONNECT';
type2atom(_)  -> invalid.

setflag(undefined) -> 0;
setflag(_)         -> 1.

bin(X) when is_binary(X) ->
    X.
