# -*- coding: UTF8 -*-

import types

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from lib.env import gen_msg, debug

class Qos1(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "qos 2 delivery")


    @catch
    @desc("SUBSCRIBE/SUBACK")
    def test_001(self):
        sub = MqttClient("sub", connect=4)
        suback_evt = sub.subscribe('foo/bar', 2)
        if not isinstance(suback_evt, EventSuback) or \
                suback_evt.mid != sub.get_last_mid() or \
                suback_evt.granted_qos[0] != 2:
            debug(suback_evt)
            return False

        return True

    @catch
    @desc("downgraded delivery to qos 0")
    def test_002(self):
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', 2)

        pub = MqttClient('pub', connect=4)
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=0)
        pub.disconnect()

        e = sub.recv()
        sub.unsubscribe('a/b')
        sub.disconnect()

        if not isinstance(e, EventPublish) or \
                e.msg.payload != msg or \
                e.msg.qos     != 0:
            debug(e)
            return False

        return True

    @catch
    @desc("downgraded delivery to qos 1")
    def test_003(self):
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', qos=2)

        pub = MqttClient('pub', connect=4)
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=1)

        e = sub.recv()
        if not isinstance(e, EventPublish) or \
                e.msg.payload != msg or \
                e.msg.qos     != 1:
            debug('received event (supposely publish): {0}'.format(e))
            return False

        # send PUBACK
        sub.puback(e.msg.mid)

        e2 = pub.recv()
        if not isinstance(e2, EventPuback) or \
                e2.mid != pub.get_last_mid():
            debug('received event (supposely puback): {0}'.format(e2))
            return False

        sub.unsubscribe('a/b')
        sub.disconnect(); pub.disconnect()

        return True

    @catch
    @desc("qos 2 delivery")
    def test_004(self):
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', 2)

        pub = MqttClient('pub', connect=4)
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=2, read_response=False)

        msgid = pub.get_last_mid()

        # PUBREC
        e = pub.recv()
        # validating [MQTT-2.3.1-6]
        if not isinstance(e, EventPubrec) or e.mid != msgid:
            debug('failing event (PUBREC waited): {0}'.format(e))
            return False

        pub.pubrel(msgid, read_response=False)

        # subscriber ready to receive msg
        e = sub.recv()
        if not isinstance(e, EventPublish) or e.msg.qos != 2 or e.msg.payload != msg:
            debug('failing event (PUBLISH waited): {0}'.format(e))
            return False

        # subscriber: send PUBREC after having received PUBLISH message
        sub.pubrec(e.msg.mid, read_response=False)
        e2 = sub.recv()
        # validating [MQTT-2.3.1-6]
        if not isinstance(e2, EventPubrel) or e2.mid != e.msg.mid:
            debug('failing event (PUBREL waited): {0}'.format(e))
            return False

        sub.pubcomp(e.msg.mid)

        #
        pubcomp_evt = pub.recv()
        # validating [MQTT-2.3.1-6]
        if not isinstance(pubcomp_evt, EventPubcomp) or pubcomp_evt.mid != msgid:
            debug('failing event (PUBCOMP waited): {0}'.format(e))
            return False


        sub.unsubscribe('a/b')
        sub.disconnect(); pub.disconnect()

        return True

    @catch
    @desc("invalid qos 1 acknowledgement while transaction is qos 2")
    def test_010(self):
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', 2)

        pub = MqttClient('pub', connect=4)
        msg = gen_msg()
        pub.publish('a/b', payload=msg, qos=2, read_response=False)

        pub.pubrec(pub.get_last_mid())

        # PUBREC
        pub.recv()

        pub.pubrec(pub.get_last_mid())
        pub.puback(pub.get_last_mid())
        pub.pubcomp(pub.get_last_mid())


        # finally send correct PUBREL message
        pub.pubrel(pub.get_last_mid())

        # PUBLISH received by subscriber
        evt = sub.recv()

        sub.pubrel(sub.get_last_mid())
        sub.puback(sub.get_last_mid())
        sub.pubcomp(sub.get_last_mid())

        return True

    #TODO: delivery timeout (no acknowledgement) => message retransmitted

