#!/usr/bin/env python
# -*- coding: utf8 -*-

import ssl
import time
import pprint
import websocket

from lib import env
from TestSuite import *
from mqttcli import MqttClient
from nyamuk import *

from twisted.internet import defer
from twotp import Atom, to_python, Tuple, Map
from twotp.term import Pid

# TLS > v1 not available on python2.7 except for Debian
# TLSv1 and lower are disabled in OTP >= 18
SSL_VERSION = ssl.PROTOCOL_TLSv1_2 if hasattr(ssl, 'PROTOCOL_TLSv1_2') else ssl.PROTOCOL_TLSv1

class WebSocket(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "WebSocket")

    @catch
    @desc("Invalid subprotocol cause 406 response and immediate disconnection")
    def test_001(self):
        from nyamuk import nyamuk_ws
        subproto= nyamuk_ws.SUBPROTOCOLS[4]; nyamuk_ws.SUBPROTOCOLS[4] = 'foobar'

        cli = MqttClient("ws", port=1884, websocket=True)
        status = cli.connect(version=4)
        nyamuk_ws.SUBPROTOCOLS[4] = subproto

        if status != NC.ERR_SUCCESS:
            return True

        return False
        
    @catch
    @desc("[MQTT-6.0.0-3,MQTT-6.0.0-4] Server accepts 'mqtt' websocket subprotocol")
    def test_002(self):
        try:
            c = MqttClient("ws", port=1884, websocket=True, connect=4)
        except Exception:
            return False

        c.disconnect()
        return True

    @catch
    @desc("[MQTT-6.0.0-3,MQTT-6.0.0-4] Server accepts 'mqttv3.1' websocket subprotocol")
    def test_003(self):
        try:
            c = MqttClient("ws", port=1884, websocket=True, connect=3)
        except Exception:
            return False

        c.disconnect()
        return True

    @catch
    @desc("[MQTT-6.0.0-1] MQTT control packets MQT be sent in binary data frames, or connection is closed")
    def test_004(self):
        ws = websocket.WebSocket()
        ws.connect('ws://localhost:1884', subprotocols=['mqtt'])

        # send text data
        ws.send('foobar')
        ws.recv()
        if ws.connected:
            return False

        ws.close()
        return True

    @catch
    @desc("WSS (SSL) connection test")
    def test_010(self):
        cli = MqttClient("ws", port=8884, websocket=True, ssl=True, ssl_opts={'ssl_version': SSL_VERSION})
        evt = cli.connect(version=4)
        print evt
        if not isinstance(evt, EventConnack):
            return False

        cli.disconnect()
        return True

    @catch
    @desc("discussion btw websocket and standard ssl clients")
    def test_020(self):
        ws  = MqttClient("ws", port=1884, websocket=True, connect=4)
        tcp = MqttClient("tcp", connect=4)

        tcp.subscribe("foo/bar", qos=0)
        ws.publish("foo/bar", "baz", qos=0)

        evt =  tcp.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != "foo/bar" or\
                evt.msg.payload != "baz":
            return False

        ws.disconnect(); tcp.disconnect()
        return True


    @catch
    @desc("all processes destroyed on: MQTT DISCONNECT")
    @defer.inlineCallbacks
    def test_030(self):
        # disconnect client without closing socket
        def _clb(mqtt_client):
            mqtt_client.send_disconnect()

        ret = yield self._test_processes_destruction(_clb)
        defer.returnValue(ret)


    @catch
    @desc("all processes destroyed on: socket close (without MQTT DISCONNECT)")
    @defer.inlineCallbacks
    def test_031(self):
        # socket close
        def _clb(mqtt_client):
            mqtt_client._c.socket_close()

        ret = yield self._test_processes_destruction(_clb)
        defer.returnValue(ret)


    @catch
    @desc("all processes destroyed on: socket close + TIMEOUT (without MQTT DISCONNECT)")
    @defer.inlineCallbacks
    def test_032(self):
        # socket close
        def _clb(mqtt_client):
            mqtt_client._c.socket_close()
            # mqtt_session and wave_websocket procs are destroyed after timeout only
            time.sleep(2)

        ret = yield self._test_processes_destruction(_clb)
        defer.returnValue(ret)


    @catch
    @desc("all processes destroyed on: MQTT TIMEOUT")
    @defer.inlineCallbacks
    def test_033(self):
        # timeout
        def _clb(mqtt_client):
            time.sleep(2)

        ret = yield self._test_processes_destruction(_clb)
        defer.returnValue(ret)


    @defer.inlineCallbacks
    def _test_processes_destruction(self, clb):
        """
                how does it work:
                - from wave_sessions_sup, we retrieve mqtt_session pid for connected mqtt client
                - from mqtt_session state, we get associated wave_websocket pid
                - from wave_websocket session, we get associated ranch handler and mqtt_ranch_protocol pid's

                - we check that 4 servers are stopped after clb executed (ie MQTT DISCONNECTION)
        """
        workers = yield env.remote('supervisor','which_children', Atom('wave_sessions_sup'))
        #workers = ["<0.{0}.{1}>".format(pid.nodeId, pid.serial) for (a, pid, b, c) in workers]
        for (a, pid, b, c) in workers:
            env.debug("(pre:cleanup) killing {0} session worker".format(to_python(pid)))
            yield env.remote('erlang', 'exit', pid, Atom('kill'))


        ws = MqttClient("ws", port=1884, websocket=True, connect=4, keepalive=1)

        workers = yield env.remote('supervisor','which_children', Atom('wave_sessions_sup'))
        #workers = ["<0.{0}.{1}>".format(pid.nodeId, pid.serial) for (a, pid, b, c) in workers]
        workers = [pid for (a, pid, b, c) in workers]
        #pprint.pprint(workers)
        if len(workers) != 1:
            env.debug("more than 1 mqtt_sessions workers running")
            defer.returnValue(False)
        processes = {'session': workers[0]}

        #yield env.remote('wave_websocket','test', Map({Atom('a'): Atom('b'), 'foo': 'bar', 1: 2}))
        #yield env.remote('wave_websocket','test', Map({}))

        #(wave@127.0.0.1)26> sys:get_state(Pid).
        #{connected,{session,<<"test_nyamuk">>,[],
        #                    {mqtt_ranch_protocol,wave_websocket,<0.18575.3>},
        #                    #{addr => {addr,ws,"127.0.0.1",50822},
        #                      clean => 1,
        #                      state => connecting,
        #                      ts => 1468345324,
        #                      username => undefined},
        #                    undefined,15000,[],59738,undefined}}

        # get mqtt_session state
        state = yield env.remote('sys','get_state', processes.get('session'))
	#pprint.pprint(to_python(state))
        processes['websocket'] = state[1][3][2]

        # get wave_websocket state
        state = yield env.remote('wave_websocket', 'debug_getstate', processes['websocket'])
        #pprint.pprint(to_python(state))
        processes['ranch'] = state[1]
        processes['proto'] = state[2]

        #pprint.pprint(processes)
        @defer.inlineCallbacks
        def check_running(procs):
            ret = [k for k, v in procs.iteritems() if
                   to_python((yield env.remote('erlang','is_process_alive', v))) == 'true']
            defer.returnValue(ret)
        #print (yield check_running(processes))
        rprocs = yield check_running(processes)
        if len(rprocs) != len(processes):
            env.debug("not all processes are alive before disconnect: {0}".format(rprocs))
            defer.returnValue(False)


        clb(ws)

        rprocs = yield check_running(processes)
        #print rprocsi
        if len(rprocs) != 0:
            env.debug("{0} proc(s) still running after disconnect".format(rprocs))
            defer.returnValue(False)

        defer.returnValue(True)

