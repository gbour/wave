#!/usr/bin/env python
# -*- coding: utf8 -*-

import ssl
import time
import websocket

from lib import env
from TestSuite import *
from mqttcli import MqttClient
from nyamuk import *

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
        
