# -*- coding: UTF8 -*-

import time
import socket

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt
from lib.env import gen_msg, debug


class Unicode(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "unicode")

    #
    # ==== utf8 tests ====
    #

    @catch
    @desc("(un)subscribe with utf8 topic filter")
    def test_100(self):
        c = MqttClient('unicode', connect=4)
        topic = u"utf8/Какво е Unicode ?"

        evt = c.subscribe(topic, qos=0)
        if not isinstance(evt, EventSuback) or \
                evt.mid != c.get_last_mid():
            debug(evt)
            return False

        c.unsubscribe(topic)
        c.disconnect()
        return True

    @catch
    @desc("register with invalid-utf8 topic filters")
    def test_101(self):
        for topic in (
                u"utf8: \u0000 đ",
                u"utf8: \u001b đ",
                u"utf8: \u0081 đ",
                u"utf8: \u0093 đ",
                u"utf8: \ud800 đ",
                u"utf8: \ud8a4 đ",
                u"utf8: \ud8ff đ"):

            c = MqttClient('unicode', connect=4)

            evt = c.subscribe(topic, qos=0)
            if not evt is None:
                debug(evt)
                return False

            # check connection is closed
            if c.conn_is_alive():
                debug("connection still alive")
                return False

        return True

    @catch
    @desc("pubsub with utf8 topic filter/topic/content")
    def test_110(self):
        sub = MqttClient('unisub', connect=4)
        pub = MqttClient('unipub', connect=4)

        evt = sub.subscribe(u"ᛋᚳᛖᚪᛚ/+/ᚦᛖᚪᚻ", qos=0)
        if not isinstance(evt, EventSuback) or \
                evt.mid != sub.get_last_mid():
            debug(evt)
            return False

        topic   = u"ᛋᚳᛖᚪᛚ/䑓/ᚦᛖᚪᚻ"
        content = u"На берегу пустынных волн"

        evt = pub.publish(topic, payload=content, qos=0)

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != topic:
            debug(evt)
            return false

        content2 = evt.msg.payload.decode('utf8')
        if content2 != content:
            debugt("payload differs: {0} != {1}".format(content, content2))
            return False

        sub.disconnect(); pub.disconnect()
        return True

