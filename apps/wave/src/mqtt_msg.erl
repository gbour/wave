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

-include("mqtt_msg.hrl").

%
% messages length:
%
% exactly 3 bytes (type + flags + rle, rle = 0):
%  - PINREQ
%  - PINRESP
%  - DISCONNECT
%
% exactly 5 bytes (type + flags + rle = 2 + varheader):
%  - CONNACK
%  - PUBACK
%  - PUBREC
%  - PUBREL
%  - PUBCOMP
%  - UNSUBACK
%
% more than 3 bytes (type + flags + rle + varheader + payload):
%  - CONNECT     (min 13 bytes)
%  - PUBLISH     (min 3)
%  - SUBSCRIBE   (min 3)
%  - SUBACK      (min 3)
%  - UNSUBSCRIBE (min 3)
%
decode(<<Type:4, Flags:4, Rest/binary>>) ->
    decode(type2atom(Type), <<Flags:4>>, decode_rlength(Rest, erlang:byte_size(Rest), minlen(Type))).

% invalid MQTT type
decode({invalid, T}, _, _) ->
    {error, {type, T}};
% invalid Remaining Length header or not enough buffer to decode RLen
decode(_, _, {error, overflow}) ->
    {error, overflow};
% buffer is too short to decode remaining-length header
decode(_Type, _, {error, size, Size}) ->
    lager:warning("~p: not enough data to decode rlen. missing ~p bytes", [_Type, Size]),
    {error, size, Size};
% Buffer is too short (do not contains the whole MQTT message)
decode(_, _, {ESize, RSize, _}) when ESize > RSize ->
    {error, size, ESize-RSize};

decode(Type, <<Dup:1, Qos:2, Retain:1>>, {RLen, _, Rest}) ->
    <<BPayload:RLen/binary, Rest2/binary>> = Rest,

    Msg = case decode_payload(Type, Qos, {RLen, BPayload}) of
        {ok, Payload} ->
            {ok, #mqtt_msg{
                type=Type,
                retain=Retain,
                qos=Qos,
                dup=Dup,

                payload = Payload
            }, Rest2};

        {error, Err} ->
            {error, Err, Rest2}
    end,

    %lager:debug("~p", [Msg]),
    Msg.


%%
%% @doc «CONNECT» message
%% support both MQTT 3.1 and 3.1.1 versions
%%
decode_payload('CONNECT', _Qos, {Len, <<
        PLen:16,
        Protocol:PLen/binary,
        Version:8/integer,
        Flags:7,
        0:1,                  % enforcing reserved flags field is set to 0
        Ka:16,
        Rest/binary>>}) when
            (Protocol =:= <<"MQIsdp">> andalso Version =:= 3) orelse
            (Protocol =:= <<"MQTT">>   andalso Version =:= 4) ->

    lager:debug("CONNECT: ~p/~p, ~p/~p", [Protocol, Version, Flags, erlang:is_integer(Flags)]),

    % CONNECT flags
    <<User:1, Pwd:1, WillRetain:1, WillQos:2, WillFlag:1, Clean:1>> = <<Flags:7/integer>>,
    lager:debug("~p/~p/~p/~p/~p/~p", [User,Pwd,WillRetain,WillQos,WillFlag,Clean]),

    % decoding Client-ID
    {ClientID, Rest2} = decode_string(Rest),

    % decoding will topic & message
    {WillTopic, WillMsg, Rest3} = case WillFlag of
        1 ->
            {_WillTopic, _R}  = decode_string(Rest2),
            {_WillMsg  , _R2} = decode_string(_R),
            {_WillTopic, _WillMsg, _R2};
        _ -> {undefined, undefined, Rest2}
    end,

    % decoding username
    {Username , Rest4} = case User of
        1 -> decode_string(Rest3);
        _ -> {undefined, Rest3}
    end,

    % decoding password
    {Password, Rest5} = case Pwd of
        1 -> decode_string(Rest4);
        _ -> {undefined, Rest4}
    end,

    lager:debug("~p / ~p / ~p / ~p / ~p, keepalive=~p", [ClientID, WillTopic, WillMsg, Username, Password, Ka]),
    {ok, [
        {clientid , ClientID},
        {topic    , WillTopic},
        {message  , WillMsg},
        {username , Username},
        {password , Password},
        {keepalive, Ka},
        {clean    , Clean},
        {version  , Version}
    ]};


decode_payload('PUBLISH', Qos, {Len, Rest}) ->
    %lager:debug("PUBLISH (qos=~p) ~p ~p", [Qos, Len, Rest]),

    {Topic, Rest2} = decode_string(Rest),
    Ret = if
        Qos =:= 0 ->
            [{topic,Topic}, {data, Rest2}];
        true      ->
            <<MsgID:16, Rest3/binary>> = Rest2,
            [{topic,Topic}, {msgid,MsgID}, {data, Rest3}]
    end,
    %{Topic, <<MsgID:16, Rest2/binary>>} = decode_string(Rest),
    %lager:debug("ret= ~p", [Ret]),

    {ok, Ret};

decode_payload('SUBSCRIBE', Qos, {Len, <<MsgID:16, Payload/binary>>}) ->
    lager:debug("SUBSCRIBE v3.1 ~p", [MsgID]),

	Topics = get_topics(Payload, [], true),
	lager:debug("topics= ~p", [Topics]),
	{ok, [{msgid, MsgID},{topics, Topics}]};

decode_payload('UNSUBSCRIBE', Qos, {Len, <<MsgID:16, Payload/binary>>}) ->
    lager:debug("UNSUBSCRIBE: ~p", [Payload]),

    Topics = get_topics(Payload, [], false),
    {ok, [{msgid, MsgID}, {topics, Topics}]};

decode_payload('PINGREQ', _, {0, <<>>}) ->
    {ok, []};
decode_payload('PINGRESP', _, {0, <<>>}) ->
    {ok, []};

decode_payload('DISCONNECT', _, {0, <<>>}) ->
    lager:debug("DISCONNECT"),
    % not a real error, we just want to close the connection
    %TODO: return a disconnect object; and do cleanup upward
    %{error, disconnect};
    {ok, []};

decode_payload('CONNACK', _, {Len, <<_:8, RetCode:8/integer>>}) ->
    lager:debug("CONNACK"),
    {ok, [{retcode, RetCode}]};

decode_payload('PUBACK', _Qos, {Len=2, <<MsgID:16>>}) ->
    lager:debug("PUBACK. MsgID= ~p", [MsgID]),
    {ok, [{msgid, MsgID}]};

decode_payload('PUBREC', _Qos, {Len, <<MsgID:16>>}) ->
    lager:debug("PUBREC. MsgID= ~p", [MsgID]),
    {ok, [{msgid, MsgID}]};

decode_payload('PUBREL', _Qos=1, {Len, <<MsgID:16>>}) ->
    lager:debug("PUBREL. MsgID= ~p", [MsgID]),
    {ok, [{msgid, MsgID}]};

decode_payload('PUBCOMP', _Qos, {Len, <<MsgID:16>>}) ->
    lager:debug("PUBREL. MsgID= ~p", [MsgID]),
    {ok, [{msgid, MsgID}]};

decode_payload('SUBACK', _, {Len, <<MsgID:16, Qos/binary>>}) ->
    lager:debug("SUBACK. MsgID= ~p", [MsgID]),
    {ok, [{msgid, MsgID}]};

decode_payload(Cmd, Qos, Args) ->
    lager:info("invalid command ~p (qos=~p, payload=~p)", [Cmd, Qos, Args]),

    {error, disconnect}.

get_topics(<<>>, Topics, _) ->
	Topics;
% with QOS field (SUBSCRIBE)
get_topics(Payload, Topics, true) ->
	{Name, Rest} = decode_string(Payload),
	<<_:6, Qos:2/integer, Rest2/binary>> = Rest,

	get_topics(Rest2, [{Name,Qos}|Topics], true);
% without QOS field (UNSUBSCRIBE)
get_topics(Payload, Topics, _) ->
	{Name, Rest} = decode_string(Payload),
	get_topics(Rest, [Name|Topics], false).

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

decode_rlength(Pkt, PktSize, MinLen) when PktSize < MinLen ->
    {error, size, MinLen-PktSize};
decode_rlength(Pkt, _, _) ->
    p_decode_rlength(Pkt, 1, 0).

p_decode_rlength(_, 5, _) ->
    % remaining length overflow
    {error, overflow};
p_decode_rlength(<<0:1, Len:7/integer, Rest/binary>>, Mult, Acc) ->
    {Acc + Mult*Len, erlang:byte_size(Rest), Rest};
p_decode_rlength(<<1:1, Len:7/integer, Rest/binary>>, Mult, Acc) ->
    p_decode_rlength(Rest, Mult*128, Acc + Mult*Len).


encode_rlength(Payload) ->
    encode_rlength(erlang:byte_size(Payload), <<"">>).

% shortcut for 1 byte only rlength (< 128)
encode_rlength(Size, <<"">>) when Size < 128 ->
    <<Size:8>>;
encode_rlength(0, RLen)     ->
    RLen;
encode_rlength(Size, RLen) ->
    RLen2 = Size bsr 7, % division by 128
    Digit = (Size rem 128) + ( if
        RLen2 > 0 -> 128;
        true      -> 0
    end ),

    encode_rlength(RLen2, <<RLen/binary, Digit:8>>).


encode(#mqtt_msg{retain=Retain, qos=Qos, dup=Dup, type=Type, payload=Payload}) ->
    P = encode_payload(Type, Qos, Payload),

    lager:info("~p ~p", [P, is_binary(P)]),

	<<
        % fixed headers
        (atom2type(Type)):4, Dup:1, Qos:2, Retain:1,
        % remaining length
        (encode_rlength(P))/binary,
        % variable headers + payload
        P/binary
    >>.

encode_payload('CONNECT', _Qos, Opts) ->
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


encode_payload('PUBLISH', Qos=0, Opts) ->
    Topic = proplists:get_value(topic, Opts),
    Content = proplists:get_value(content, Opts),

    <<
        (encode_string(Topic))/binary,
        % payload
        (bin(Content))/binary
    >>;

encode_payload('PUBLISH', Qos, Opts) ->
    Topic = proplists:get_value(topic, Opts),
    MsgID = proplists:get_value(msgid, Opts),
    Content = proplists:get_value(content, Opts),

    <<
        (encode_string(Topic))/binary,
        MsgID:16,
        % payload
        (bin(Content))/binary
    >>;

encode_payload('SUBSCRIBE', _Qos, Opts) ->
    Topic = proplists:get_value(topic, Opts),
    lager:info("topic= ~p", [Topic]),

    <<
        1:16, % MsgID - mandatory
        (encode_string(Topic))/binary,
        0:8 % QoS
    >>;

encode_payload('CONNACK', _Qos, [{retcode, RetCode}]) ->
    <<
      % var headers
      0:8,
      % payload
      RetCode:8
    >>;

encode_payload('PUBACK', _Qos, Opts) ->
    MsgID = proplists:get_value(msgid, Opts),

    <<
        MsgID:16
    >>;

encode_payload('PUBREC', _Qos, Opts) ->
    MsgID = proplists:get_value(msgid, Opts),

    <<
        MsgID:16
    >>;

encode_payload('PUBREL', _Qos, Opts) ->
    MsgID = proplists:get_value(msgid, Opts),

    <<
        MsgID:16
    >>;

encode_payload('PUBCOMP', _Qos, Opts) ->
    MsgID = proplists:get_value(msgid, Opts),

    <<
        MsgID:16
    >>;

encode_payload('SUBACK', _Qos, Opts) ->
	MsgId = proplists:get_value(msgid, Opts),
	Qos   = proplists:get_value(qos, Opts),

	<<
	  MsgId:16,
	  (encode_qos(Qos))/binary
	>>;

encode_payload('UNSUBACK', _Qos, [{msgid, MsgID}]) ->
	<<MsgID:16>>;

encode_payload('PINGREQ', _Qos, _) ->
    <<>>;
encode_payload('PINGRESP', _Qos, _) ->
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
type2atom(T)  -> {invalid, T}.

minlen(1)  -> 3;
minlen(2)  -> 3;
minlen(3)  -> 3;
minlen(4)  -> 3;
minlen(5)  -> 3;
minlen(6)  -> 3;
minlen(7)  -> 3;
minlen(8)  -> 3;
minlen(9)  -> 3;
minlen(10) -> 3;
minlen(11) -> 3;
minlen(12) -> 1;
minlen(13) -> 1;
minlen(14) -> 1;
minlen(_)  -> -1.


setflag(undefined) -> 0;
setflag(_)         -> 1.

bin(X) when is_binary(X) ->
    X.
