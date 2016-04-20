#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

class Basic(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "basic tests")

    def newclient(self, name="req"):
        c = MqttClient(name)
        c.do("connect")

        return c

    @catch
    @desc("CONNECT")
    def test_01(self):
        c = MqttClient("reg")
        evt = c.do("connect")

        # [MQTT-3.1.4-4]: CONNACK retcode MUST be 0
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
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
    @desc("SUBSCRIBE/UNSUBSCRIBE")
    def test_10(self):
        c = MqttClient("reg")
        c.do("connect")

        evt = c.do("subscribe", "/foo/bar", 0)
        # validating [MQTT-2.3.1-7]
        if not isinstance(evt, EventSuback) or evt.mid != c.get_last_mid():
            return False

        evt = c.unsubscribe("/foo/bar")
        # validating [MQTT-2.3.1-7]
        if not isinstance(evt, EventUnsuback) or evt.mid != c.get_last_mid():
            return False

        c.disconnect()
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
