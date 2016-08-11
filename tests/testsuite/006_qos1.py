# -*- coding: UTF8 -*-

import types

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from lib.env import gen_msg, debug
from nyamuk.event import *

class Qos1(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "qos 1 delivery")


    @catch
    @desc("SUBSCRIBE/SUBACK")
    def test_001(self):
        sub = MqttClient("sub:{seq}", connect=4)
        suback_evt = sub.subscribe('foo/bar', qos=1)
        if not isinstance(suback_evt, EventSuback) or \
                suback_evt.mid != sub.get_last_mid() or \
                suback_evt.granted_qos[0] != 1:
            debug('failing event: {0}'.format(suback_evt))
            return False

        return True

    @catch
    @desc("downgraded delivery qos (subscr qos = 1)")
    def test_002(self):
        sub = MqttClient("sub:{seq}", connect=4)
        sub.subscribe('a/b', qos=1)

        pub = MqttClient("pub:{seq}", connect=4)
        # published with qos 0
        msg = gen_msg()
        pub.publish('a/b', payload=msg)
        pub.disconnect()

        e = sub.recv()
        sub.unsubscribe('a/b')
        sub.disconnect()

        if not isinstance(e, EventPublish) or \
                e.msg.payload != msg or \
                e.msg.qos     != 0:
            debug('failing event: {0}'.format(e))
            return False

        return True

    @catch
    @desc("downgraded delivery qos (pub qos = 1)")
    def test_022(self):
        sub = MqttClient("sub:{seq}", connect=4)
        sub.subscribe('a/b', qos=0)

        pub = MqttClient("pub:{seq}", connect=4)
        # published with qos 0
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=1)
        pub.disconnect()

        e = sub.recv()
        sub.unsubscribe('a/b')
        sub.disconnect()

        if not isinstance(e, EventPublish) or \
                e.msg.payload != msg or \
                e.msg.qos     != 0:
            debug('failing event: {0}'.format(e))
            return False

        return True

    @catch
    @desc("QOS 1 published message - acknowledged")
    def test_003(self):
        sub = MqttClient("sub:{seq}", connect=4)
        sub.subscribe('a/b', qos=1)

        pub = MqttClient("pub:{seq}", connect=4)
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=1)
        pub.recv()

        e = sub.recv()
        if not isinstance(e, EventPublish) or \
                e.msg.payload != msg or \
                e.msg.qos     != 1:
            debug('failing event: {0}'.format(e))
            return False

        # send PUBACK
        sub.puback(e.msg.mid)

        puback_evt = pub.recv()
        # PUBACK mid == PUBLISH mid
        # validating [MQTT-2.3.1-6]
        if not isinstance(puback_evt, EventPuback) or \
                puback_evt.mid != pub.get_last_mid():
            debug('failing event: {0}'.format(puback_evt))
            return False

        sub.unsubscribe('a/b')
        sub.disconnect(); pub.disconnect()
        return True

    @catch
    @desc("destroyed socket (no subscriber, waiting PUBACK)")
    def test_004(self):
        pub = MqttClient("pub:{seq}", connect=4)
        pub.publish('a/b', payload=gen_msg(), qos=1)

        pub.destroy(); del pub # socket destroyed
        return True

    @catch
    @desc("destroyed socket (1 subscriber, waiting PUBACK)")
    def test_005(self):
        sub = MqttClient("sub:{seq}", connect=4)
        sub.subscribe('a/b', qos=1)

        pub = MqttClient("pub:{seq}", connect=4)
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=1)
        # destoying socket
        pub.destroy(); del pub

        e = sub.recv()
        if not isinstance(e, EventPublish) or \
                e.msg.payload != msg or \
                e.msg.qos     != 1:
            debug('failing event: {0}'.format(e))
            return False

        sub.disconnect()
        return True

    @catch
    @desc("unexpected qos 2 PUBREC/PUBREL/PUBCOMP msgs while transaction is qos 1")
    def test_006(self):
        sub = MqttClient("sub:{seq}", connect=4)
        sub.subscribe('a/b', qos=1)

        pub = MqttClient("pub:{seq}", connect=4)
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=1)
        pub.recv()

        e = sub.recv()
        if not isinstance(e, EventPublish) or \
                e.msg.payload != msg or \
                e.msg.qos     != 1:
            debug('failing event: {0}'.format(e))
            return False

        # send PUBREL (! ERROR: not a QOS 2 message)
        sub.pubrec(e.msg.mid)

        puback_evt = pub.recv()
        if not puback_evt is None:
            debug('failing event: {0}'.format(puback_evt))
            return False

        # unexpected PUBREL
        sub.pubrel(e.msg.mid)
        puback_evt = pub.recv()
        if not puback_evt is None:
            debug('failing event: {0}'.format(puback_evt))
            return False

        # unexpected PUBCOMP
        sub.pubcomp(e.msg.mid)
        puback_evt = pub.recv()
        if not puback_evt is None:
            debug('failing event: {0}'.format(puback_evt))
            return False

        sub.unsubscribe('a/b')

        sub.disconnect()
        pub.disconnect()
        return True

    @catch
    @desc("msgid increment")
    def test_030(self):
        sub = MqttClient("sub:{seq}", connect=4)
        sub.subscribe("foo/bar", qos=1)

        pub = MqttClient("pub:{seq}", connect=4)
        msg = gen_msg()
        pub.publish("foo/bar", payload=msg, qos=1)

        e1 = sub.recv()

        msg2 = gen_msg()
        pub.publish("foo/bar", payload=msg2, qos=1)
        e2 = sub.recv()
        if e2.msg.mid != e1.msg.mid + 1:
            debug('failing event: {0}'.format(e2))
            return False

        return True

    @catch
    @desc("pairing ack with right publish (using msgid)")
    def test_031(self):
        sub = MqttClient("sub:{seq}", connect=4)
        ack = sub.subscribe_multi([('foo/+', 1), ('foo/#', 1)])
        debug("subscribe_multi response: {0}".format(ack))

        pub = MqttClient("pub:{seq}", connect=4)
        pub.publish("foo/bar", gen_msg(42), qos=1)

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != 'foo/bar' or\
                evt.msg.qos   != 1:
            debug('failing event: {0}'.format(evt))
            return False
        sub.puback(evt.msg.mid, read_response=False)

        evt = pub.recv()
        if evt is not None:
            debug('failing event: {0}'.format(evt))
            return False

        # receive 2d publish
        evt = sub.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != 'foo/bar' or\
                evt.msg.qos   != 1:
            debug('failing event: {0}'.format(evt))
            return False
        sub.puback(evt.msg.mid)

        evt = pub.recv()
        if not isinstance(evt, EventPuback):
            debug('failing event: {0}'.format(evt))
            return False

        return True

    #TODO: delivery timeout (no acknowledgement) => message retransmitted

