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

        if not isinstance(evt, EventConnack):
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
