
-module(wave).
-export([serve/0]).

serve() ->
	{ok, S} = gen_tcp:listen(4949,
													 [binary,{active,false},{packet,raw},{reuseaddr,true}]),
	{ok, S2} = gen_tcp:accept(S),
	recv(S2),

	gen_tcp:close(S2),
	ok.

recv(S) ->
	case gen_tcp:recv(S, 0) of
		{ok, D} -> 
				io:format("data= ~p~n", [D]),
				mqtt(S, D),
				recv(S);

		{error, Err} ->
				io:format("error: ~p~n", [Err]),
				ok
	end.

%mqtt(<<Ret:1,Qos:2,Dup:1,Type:4,Rest/binary>>) ->
mqtt(S, <<Type:4,Dup:1,Qos:2,Ret:1,Rest/binary>>) ->
	io:format("msg type= ~p (~p,~p,~p)~n", [Type, Ret,Qos,Dup]),
	msg(S, Type, Rest).

% CONNECT
msg(S, 1, Rest) ->
	% resp= CONNACK
	gen_tcp:send(S,<<32,2,0,0>>),
	ok;

% PINGREQ
msg(S, 12, Rest) ->
	% resp= PINGRESP
	gen_tcp:send(S,<<208,0>>),
	ok;

msg(S,_,_) ->
	nop.

