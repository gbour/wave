#!/usr/bin/env python
# -*- coding: UTF8 -*-

import types

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

class Qos1(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "qos 2 delivery")

    def newclient(self, name="req"):
        c = MqttClient(name)
        c.do("connect")

        return c

    @catch
    @desc("downgraded delivery to qos 0")
    def test_001(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 2)

        pub = self.newclient('pub')
        pub.publish('a/b', "foobar", qos=0)
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
    @desc("downgraded delivery to qos 1")
    def test_002(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 2)

        pub = self.newclient('pub')
        pub.publish('a/b', "foobar2", qos=1)

        e = sub.recv()

        if not isinstance(e, EventPublish) or \
           e.msg.payload != "foobar2" or \
           e.msg.qos     != 1:
            return False

        # send PUBACK
        sub.puback(e.msg.mid)

        e2 = pub.recv()
        if not isinstance(e2, EventPuback) or e2.mid != e.msg.mid:
            return False

        sub.unsubscribe('a/b')
        sub.disconnect()
        pub.disconnect()

        return True

    @catch
    @desc("qos 2 delivery")
    def test_003(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 2)

        pub = self.newclient('pub')
        pub.publish('a/b', "foobar2", qos=2, read_response=False)

        msgid = pub.get_last_mid()

        # PUBREC
        e = pub.recv()
        if not isinstance(e, EventPubrec) or e.mid != msgid:
            return False

        pub.pubrel(msgid, read_response=False)

        # subscriber ready to receive msg
        e = sub.recv()
        if not isinstance(e, EventPublish) or e.msg.qos != 2 or e.msg.payload != "foobar2":
            return False

        sub.pubrec(e.msg.mid, read_response=False)
        e2 = sub.recv()
        if not isinstance(e2, EventPubrel) or e2.mid != e.msg.mid:
            return False

        sub.pubcomp(e.msg.mid)

        #
        pubcomp_evt = pub.recv()
        if not isinstance(pubcomp_evt, EventPubcomp) or pubcomp_evt.mid != msgid:
            return False


        sub.unsubscribe('a/b')
        sub.disconnect()
        pub.disconnect()

        return True

    #TODO: delivery timeout (no acknowledgement) => message retransmitted
