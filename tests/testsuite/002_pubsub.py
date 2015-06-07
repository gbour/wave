#!/usr/bin/env python
# -*- coding: UTF8 -*-

import types

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

class PubSub(TestSuite):
    tests = (
        ('a/b/c', 'a/b/c'),
        ('a/b/c', 'a/b/d'  , False),
        ('a/+/c', 'a/b/c'),
        ('a/b/#', 'a/b/c'),
        ('a/b/#', 'a/b'),
        ('a/b/#', 'a/b/c/d'),
        ('a/b/#', 'a'      , False),
    )

    def __init__(self):
        TestSuite.__init__(self, "publish/subscribe")

        i = 1
        for test in PubSub.tests:
            (subtopic, pubtopic) = test[0:2]
            match = test[2] if len(test) >= 3 else True


            def _funcbuilder(subtopic, pubtopic, match):
                def _test(self):
                    print("pubtopic={0}, subtopic={1}".format(pubtopic,subtopic))
                    ret = self.pubsub(pubtopic, subtopic)
                    return ret if match else not ret
                return _test

            setattr(self,
                "test_auto_{0:02}".format(i),
                types.MethodType(
                    catch(
                        desc("{0} {1} {2}".format(subtopic, "MATCH" if match else "DON'T MATCH", pubtopic))(
                            _funcbuilder(subtopic, pubtopic, match)
                    )), 
                    self
                )
            )
            i += 1
                

    def newclient(self, name="req"):
        c = MqttClient(name)
        c.do("connect")

        return c

    def pubsub(self, pubtopic, subtopic):
        msg = 'foobar'

        sub = self.newclient('sub')
        suback_evt = sub.subscribe(subtopic, 0)
        if not isinstance(suback_evt, EventSuback) or \
            suback_evt.mid != sub.get_last_mid() or \
            suback_evt.granted_qos[0] != 0:
                return False

        pub = self.newclient('pub')
        pub.publish(pubtopic, msg)
        pub.disconnect()

        e = sub.recv()
        unsuback_evt = sub.unsubscribe(subtopic)
        if not isinstance(unsuback_evt, EventUnsuback) or \
            unsuback_evt.mid != sub.get_last_mid():
                return False

        sub.disconnect()
        #print e, e.msg.topic, e.msg.payload
        if not isinstance(e, EventPublish) or \
           e.msg.topic   != pubtopic or \
           e.msg.payload != msg:
            return False

        return True

