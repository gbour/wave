#!/usr/bin/env python
# -*- coding: utf8 -*-

import time

from lib import env
from TestSuite import *
from mqttcli import MqttClient

from nyamuk.event import *
from twisted.internet import defer
import twotp

"""
    When a message delivery cannot be completed

    1) qos 2 message publisher die/disconnects after PUBLISH: never send back PUBREL
    2) subscriber die/disconnects after receiving PUBLISH 
            qos 1: do not send back PUBACK
            qos 2: do not send back PUBREC or PUBCOMP
"""
class PartialDelivery(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "partial delivery")

    @defer.inlineCallbacks
    def msgworkers_count(self):
        """ returns count of active msgworkers """
        #twotp.supervisor.count_children(atom(wave_msgworkers_sup))
        sup = yield env.remote('supervisor','count_children', twotp.Atom('wave_msgworkers_sup'))
        actives = (filter(lambda (name, count): name == 'active', twotp.to_python(sup)))[0][1]
        #print 'actives', actives

        defer.returnValue(actives)


    @catch
    @desc("fake test: wait msg workers timeout")
    @defer.inlineCallbacks
    def test_000(self):
        time.sleep(6)
        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("publisher (qos 2) : no PUBREL")
    @defer.inlineCallbacks
    def test_001(self):
        sub = MqttClient("sub", connect=4)
        sub.subscribe("foo/bar", qos=0)

        pub = MqttClient("pub", connect=4)
        pub.publish("foo/bar", env.gen_msg(42), qos=2)
        # PUBREL not sent
        pub.destroy(); del pub

        if (yield self.msgworkers_count()) != 1:
            defer.returnValue(False)

        # msg worker is destroyed after 5 secs
        time.sleep(6)
        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("subscriber (qos 1) : no PUBACK")
    @defer.inlineCallbacks
    def test_002(self):
        sub = MqttClient("sub", connect=4)
        sub.subscribe("foo/bar", qos=1)

        pub = MqttClient("pub", connect=4)
        pub.publish("foo/bar", env.gen_msg(42), qos=1)

        evt = sub.recv()
        if not isinstance(evt, EventPublish):
            defer.returnValue(False)

        # PUBACK not send
        sub.destroy(); del sub

        if (yield self.msgworkers_count()) != 1:
            defer.returnValue(False)

        # msg worker is destroyed after 5 secs
        time.sleep(6)
        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        pub.disconnect()
        defer.returnValue(True)

    @catch
    @desc("subscriber (qos 1) : no PUBACK, 2 subscribers")
    @defer.inlineCallbacks
    def test_003(self):
        sub = MqttClient("sub", connect=4)
        sub.subscribe("foo/bar", qos=1)
        sub2 = MqttClient("sub", connect=4)
        sub2.subscribe("foo/+", qos=1)

        pub = MqttClient("pub", connect=4)
        pub.publish("foo/bar", env.gen_msg(42), qos=1)

        evt1 = sub.recv()
        evt2 = sub2.recv()

        sub.destroy(); del sub

        if (yield self.msgworkers_count()) != 1:
            defer.returnValue(False)

        # sub removed, sub2 still alive
        time.sleep(6)
        if (yield self.msgworkers_count()) != 1:
            defer.returnValue(False)

        # sub2 still alive
        time.sleep(6)
        if (yield self.msgworkers_count()) != 1:
            defer.returnValue(False)

        # msg worker is destroyed after 5 secs
        sub2.puback(evt2.msg.mid)
        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        pub.disconnect()
        defer.returnValue(True)

    @catch
    @desc("subscriber (qos 2) : no PUBREC")
    @defer.inlineCallbacks
    def test_004(self):
        sub = MqttClient("sub", connect=4)
        sub.subscribe("foo/bar", qos=2)

        pub = MqttClient("pub", connect=4)
        ack = pub.publish("foo/bar", env.gen_msg(42), qos=2)
        pub.pubrel(ack.mid)

        evt = sub.recv()
        if not isinstance(evt, EventPublish):
            defer.returnValue(False)

        # PUBREC not send
        sub.destroy(); del sub

        if (yield self.msgworkers_count()) != 1:
            defer.returnValue(False)

        # msg worker is destroyed after 5 secs
        time.sleep(6)
        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        pub.disconnect()
        defer.returnValue(True)

    @catch
    @desc("subscriber (qos 2) : no PUBCOMP")
    @defer.inlineCallbacks
    def test_005(self):
        sub = MqttClient("sub", connect=4)
        sub.subscribe("foo/bar", qos=2)

        pub = MqttClient("pub", connect=4)
        ack = pub.publish("foo/bar", env.gen_msg(42), qos=2)
        pub.pubrel(ack.mid)

        evt = sub.recv()
        if not isinstance(evt, EventPublish):
            defer.returnValue(False)
        sub.pubrec(evt.msg.mid)

        # PUBCOMP not send
        sub.destroy(); del sub

        if (yield self.msgworkers_count()) != 1:
            defer.returnValue(False)

        # msg worker is destroyed after 5 secs
        time.sleep(6)
        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        pub.disconnect()
        defer.returnValue(True)

    @catch
    @desc("clean-session off and offline storage")
    @defer.inlineCallbacks
    def test_010(self):
        sub = MqttClient("sub", connect=4, clean_session=0)
        sub.subscribe("foo/+", qos=2)
        sub.disconnect()

        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        pub = MqttClient("pub", connect=4)
        rec = pub.publish("foo/bar", env.gen_msg(42), qos=2)
        ack = pub.pubrel(rec.mid)
        print ack
        if not isinstance(ack, EventPubcomp):
            defer.returnValue(False)

        # msg is published to offline storage, msg worker should exit immediately
        if (yield self.msgworkers_count()) != 0:
            defer.returnValue(False)

        defer.returnValue(True)

