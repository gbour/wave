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
    @desc("SUBSCRIBE/SUBACK")
    def test_001(self):
        sub = self.newclient("sub")
        suback_evt = sub.subscribe('foo/bar', 1)
        if not isinstance(suback_evt, EventSuback) or \
            suback_evt.mid != sub.get_last_mid() or \
            suback_evt.granted_qos[0] != 1:
                return False

        return True

    @catch
    @desc("downgraded delivery qos (subscr qos = 1)")
    def test_002(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 1)

        pub = self.newclient('pub')
        # published with qos 0
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
    @desc("downgraded delivery qos (pub qos = 1)")
    def test_022(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 0)

        pub = self.newclient('pub')
        # published with qos 0
        pub.publish('a/b', "foobar", qos=1)
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
    def test_003(self):
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
        # PUBACK mid == PUBLISH mid
        # validating [MQTT-2.3.1-6]
        if not isinstance(puback_evt, EventPuback) or \
                puback_evt.mid != pub.get_last_mid():
            return False

        sub.unsubscribe('a/b')
        sub.disconnect()
        pub.disconnect()
        return True

    @catch
    @desc("destroyed socket (no subscriber, waiting PUBACK)")
    def test_004(self):
        pub = self.newclient('pub')
        pub.publish('a/b', "foobar2", qos=1)

        pub.destroy(); del pub # socket destroyed
        return True

    @catch
    @desc("destroyed socket (1 subscriber, waiting PUBACK)")
    def test_005(self):
        sub = self.newclient('sub')
        sub.subscribe('a/b', 1)

        pub = self.newclient('pub')
        pub.publish('a/b', "foobar2", qos=1)
        # destoying socket
        pub.destroy(); del pub 

        e = sub.recv()
        if not isinstance(e, EventPublish) or \
           e.msg.payload != "foobar2" or \
           e.msg.qos     != 1:
            return False

        sub.disconnect()
        return True

    @catch
    @desc("unexpected qos 2 PUBREC/PUBREL/PUBCOMP msgs while transaction is qos 1")
    def test_006(self):
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

        # send PUBREL (! ERROR: not a QOS 2 message)
        sub.pubrec(e.msg.mid)

        puback_evt = pub.recv()
        if not puback_evt is None:
            return False

        # unexpected PUBREL
        sub.pubrel(e.msg.mid)
        puback_evt = pub.recv()
        if not puback_evt is None:
            return False

        # unexpected PUBCOMP
        sub.pubcomp(e.msg.mid)
        puback_evt = pub.recv()
        if not puback_evt is None:
            return False

        sub.unsubscribe('a/b')
        
        sub.disconnect()
        pub.disconnect()
        return True

    @catch
    @desc("msgid increment")
    def test_30(self):
        sub = MqttClient('sub')
        sub.connect(version=4)
        sub.subscribe("foo/bar", 1)

        pub = MqttClient('pub')
        pub.connect(version=4)
        pub.publish("foo/bar", "1st msg", qos=1)

        e1 = sub.recv()

        pub.publish("foo/bar", "2d msg", qos=1)
        e2 = sub.recv()
        if e2.msg.mid != e1.msg.mid + 1:
            return False

        return True

    #TODO: delivery timeout (no acknowledgement) => message retransmitted
