#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

import time
import socket


class Unicode(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "unicode")

    def newclient(self, name="req", *args, **kwargs):
        c = MqttClient(name)
        c.connect(version = 4)

        return c

    #
    # ==== utf8 tests ====
    #

    @catch
    @desc("register with utf8 topic filter")
    def test_100(self):
        c = self.newclient('unicode')

        evt = c.subscribe(u"utf8/Какво е Unicode ?".encode('utf8'), 0)
        if not isinstance(evt, EventSuback) or \
                evt.mid != c.get_last_mid():
            return False

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

            c = self.newclient('unicode')

            evt = c.subscribe(topic, 0)
            if not evt is None:
                return False

            # check connection is closed
            if c.conn_is_alive():
                return False

        return True

    @catch
    @desc("pubsub with utf8 topic filter/topic/content")
    def test_110(self):
        sub = self.newclient('unisub')
        pub = self.newclient('unipub')

        evt = sub.subscribe(u"ᛋᚳᛖᚪᛚ/+/ᚦᛖᚪᚻ", 0)
        if not isinstance(evt, EventSuback) or \
                evt.mid != sub.get_last_mid():
            return False

        topic   = u"ᛋᚳᛖᚪᛚ/䑓/ᚦᛖᚪᚻ"
        content = u"На берегу пустынных волн"

        evt = pub.publish(topic, content, qos=0)

        evt = sub.recv()
        print evt, evt.msg.topic, evt.msg.payload, type(evt.msg.topic), type(topic)
        print content, ",", evt.msg.payload, type(content), type(evt.msg.payload)
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != topic or\
                evt.msg.payload != content:
            return False
    
        sub.disconnect()
        pub.disconnect()
        return True

