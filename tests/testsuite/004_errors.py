#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

class Errors(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "error cases")

    def newclient(self, name="req", autoconnect=False):
        c = MqttClient(name)
        if autoconnect:
            c.do("connect")

        return c

    @catch
    @desc("CONNACK=0x02 :: clientid already connected")
    def test_01(self):
        c = MqttClient("twice01", rand=False)
        evt = c.do("connect")
        # OK
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        c2  = MqttClient("twice01", rand=False)
        evt = c2.do("connect")
        # identifier rejected
        if not isinstance(evt, EventConnack) or evt.ret_code != 2:
            return False

    
        # disconnecting client #1, client #2 connection now works
        c.disconnect()

        evt = c2.do("connect")
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        return True

