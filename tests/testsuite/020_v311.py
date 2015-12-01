#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

import socket


class V311(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "MQTT version 3.1.1")

    def newclient(self, name="req", *args, **kwargs):
        c = MqttClient(name)
        c.connect(version = 4)

        return c

    @catch
    @desc("CONNECT")
    def test_01(self):
        c = MqttClient("reg")
        evt = c.connect(version=4)

        if not isinstance(evt, EventConnack) or \
            evt.ret_code:
            return False

        return True

    #TODO: we must hook disconnect method such as we send DISCONNECT message but don't close the socket
    #      then we check server has closed the socket
    @catch
    @desc("DISCONNECT")
    def test_02(self):
        c = self.newclient()
        #evt = c._c.disconnect()
        c.disconnect()

        return True

    @catch
    @desc("SUBSCRIBE")
    def test_10(self):
        c = MqttClient("reg")
        c.do("connect")

        evt = c.do("subscribe", "/foo/bar", 0)
        c.disconnect()
        if not isinstance(evt, EventSuback):
            return False

        return True

    @catch
    @desc("PUBLISH (qos=0). no response")
    def test_11(self):
        c = self.newclient()
        e = c.publish("/foo/bar", "plop")
        # QOS = 0 : no response indented
        if e is not None:
            c.disconnect()
            return False

        c.disconnect()
        return True

    @catch
    @desc("PING REQ/RESP")
    def test_20(self):
        c = self.newclient()
        e = c.send_pingreq()
        c.disconnect()

        return isinstance(e, EventPingResp)



    #
    # ==== conformity tests ====
    #

    @catch
    @desc("[MQTT-3.1.0-1] 1st pkt MUST be connect")
    def test_100(self):
        c = MqttClient('conformity')

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock
        e = c.subscribe("foo/bar", 0)
        if e is not None:
            return False

        # socket MUST be disconnected
        try:
            e = c.publish("foo", "bar")
            sock.getpeername()
        except socket.error as e:
            #print e
            return True

        return False

