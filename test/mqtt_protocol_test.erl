-module(mqtt_protocol_test).
-include_lib("eunit/include/eunit.hrl").
%-include_lib("deps/emqttcli/emqttcli_types.hrl").

start() ->
	%application:start(wave),
	%wave_app:start(),
	emqttcli:start(),
	%application:start(emqttcli),

	emqttcli:open_network_channel(tcp, <<"foo">>, "127.0.0.1", 1883, [
		binary, 
		{packet, raw},
		{active, false}, 
		{nodelay, true}, 
		{keepalive, true}
	]).

	%mqttc_app:start(a,b).

stop(_) ->
	pass.
timeout_after_connect(Client) ->
%	emqttcli:connect(Client, <<>>, <<>>, true, 999999),
	timer:sleep(6000),
%	Msg = emqttcli:recv_msg(Client),
%	Msg.
	%mqttc:connect(<<"127.0.0.1">>, 1883, <<"mqttc">>, []),
	%timer:sleep(6000)
	ok.



plop(Client) ->
	?_assertEqual(timeout_after_connect(Client), undefined).

plop_test_() ->
	{"plop", {setup,
		fun start/0,
		fun stop/1,
		fun plop/1
	}}.

