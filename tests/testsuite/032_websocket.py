# -*- coding: utf8 -*-

import ssl
import time
import pprint
import websocket

from nyamuk import *
from twisted.internet import defer

from lib import env
from lib.env import debug
from lib.erl import sessions, process
from TestSuite import *
from mqttcli import MqttClient

from twotp            import to_python


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

        cli = MqttClient("ws:{seq}", port=1884, websocket=True)
        status = cli.connect(version=4)
        nyamuk_ws.SUBPROTOCOLS[4] = subproto

        if status != NC.ERR_SUCCESS:
            debug(status)
            return True

        return False

    @catch
    @desc("[MQTT-6.0.0-3,MQTT-6.0.0-4] Server accepts 'mqtt' websocket subprotocol")
    def test_002(self):
        try:
            c = MqttClient("ws:{seq}", port=1884, websocket=True, connect=4)
        except Exception, e:
            debug(e)
            return False

        c.disconnect()
        return True

    @catch
    @desc("[MQTT-6.0.0-3,MQTT-6.0.0-4] Server accepts 'mqttv3.1' websocket subprotocol")
    def test_003(self):
        try:
            c = MqttClient("ws:{seq}", port=1884, websocket=True, connect=3)
        except Exception, e:
            debug(e)
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
            debug("ws connected")
            return False

        ws.close()
        return True

    @catch
    @desc("WSS (SSL) connection test")
    def test_010(self):
        cli = MqttClient("ws:{seq}", port=8884, websocket=True, ssl=True, ssl_opts={'ssl_version': SSL_VERSION})
        evt = cli.connect(version=4)
        if not isinstance(evt, EventConnack):
            debug(evt)
            return False

        cli.disconnect()
        return True

    @catch
    @desc("discussion btw websocket and standard ssl clients")
    def test_020(self):
        ws  = MqttClient("ws:{seq}", port=1884, websocket=True, connect=4)
        tcp = MqttClient("tcp:{seq}", connect=4)

        tcp.subscribe("foo/bar", qos=0)
        ws.publish("foo/bar", "baz", qos=0)

        evt =  tcp.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != "foo/bar" or\
                evt.msg.payload != "baz":
            debug(evt)
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
        workers = yield sessions.workers()
        for pid in workers:
            debug("(pre:cleanup) killing {0} session worker".format(to_python(pid)))
            yield process.kill(pid)


        ws = MqttClient("ws:{seq}", port=1884, websocket=True, connect=4, keepalive=1)

        workers = yield sessions.workers()
        #pprint.pprint(workers)
        if len(workers) != 1:
            debug("more than 1 mqtt_sessions workers running")
            defer.returnValue(False)
        procs = {'session': workers[0]}

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
        state = yield sessions.state(procs['session'])
        procs['websocket'] = state.transport[-1]

        # get wave_websocket state
        state = yield sessions.ws_state(procs['websocket'])
        procs['ranch'] = state.parent
        procs['proto'] = state.child
        #print 'procs', procs

        @defer.inlineCallbacks
        def check_running(_procs):
            ret = [name for name, pid in _procs.iteritems() if (yield process.alive(pid))]
            defer.returnValue(ret)

        rprocs = yield check_running(procs)
        #print 'rprocs',rprocs
        if len(rprocs) != len(procs):
            debug("not all processes are alive before disconnect: {0}".format(rprocs))
            defer.returnValue(False)

        ## callback to kill all session related processes
        clb(ws)

        rprocs = yield check_running(procs)
        if len(rprocs) != 0:
            debug("{0} proc(s) still running after disconnect".format(rprocs))
            defer.returnValue(False)

        defer.returnValue(True)

