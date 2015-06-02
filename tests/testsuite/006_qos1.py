#!/usr/bin/env python
# -*- coding: UTF8 -*-

import types

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

class Qos1(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "qos 1 delivery")

    def newclient(self, name="req"):
        c = MqttClient(name)
        c.do("connect")

        return c

    @catch
    @desc("downgraded delivery qos")
    def test_001(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 1)

        pub = self.newclient('pub')
        pub.publish('a/b', "foobar")
        pub.disconnect()

        e = sub.recv()
        sub.unsubscribe('a/b')
        sub.disconnect()

        if not isinstance(e, EventPublish) or \
           e.msg.payload != "foobar" or \
           e.msg.qos     != 0:
            return False

        return True

    @catch
    @desc("QOS 1 published message - acknowledged")
    def test_002(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 1)

        pub = self.newclient('pub')
        pub.publish('a/b', "foobar2", qos=1)
        pub.recv()

        e = sub.recv()

        if not isinstance(e, EventPublish) or \
           e.msg.payload != "foobar2" or \
           e.msg.qos     != 1:
            return False

        # send PUBACK
        sub.puback(e.msg.mid)

        puback_evt = pub.recv()
        if not isinstance(puback_evt, EventPuback) or puback_evt.mid != e.msg.mid:
            return False

        sub.unsubscribe('a/b')
        sub.disconnect()
        pub.disconnect()
        return True

    #TODO: delivery timeout (no acknowledgement) => message retransmitted
