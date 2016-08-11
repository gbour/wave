# -*- coding: UTF8 -*-

import types

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from lib.env import gen_msg, debug

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
                    debug("pubtopic={0}, subtopic={1}".format(pubtopic,subtopic))
                    ret = self._pubsub(pubtopic, subtopic, match)
                    return ret if match else not ret
                return _test

            setattr(self,
                "test_{0:03}".format(i),
                types.MethodType(
                    catch(
                        desc("{0} {1} {2}".format(subtopic, "MATCH" if match else "DON'T MATCH", pubtopic))(
                            _funcbuilder(subtopic, pubtopic, match)
                    )),
                    self
                )
            )
            i += 1


    def _pubsub(self, pubtopic, subtopic, match):
        msg = gen_msg()

        sub = MqttClient("sub:{seq}", connect=4)
        suback_evt = sub.subscribe(subtopic, 0)
        if not isinstance(suback_evt, EventSuback) or \
                suback_evt.mid != sub.get_last_mid() or \
                suback_evt.granted_qos[0] != 0:
            if match: debug("failed to subscribe: {0}".format(suback_evt))
            return False

        pub = MqttClient("pub:{seq}", connect=4)
        pub.publish(pubtopic, msg)
        pub.disconnect()

        e = sub.recv()
        unsuback_evt = sub.unsubscribe(subtopic)
        if not isinstance(unsuback_evt, EventUnsuback) or \
                unsuback_evt.mid != sub.get_last_mid():
            if match: debug("failed to unsubscribe: {0}".format(unsuback_evt))
            return False

        sub.disconnect()
        #print e, e.msg.topic, e.msg.payload
        if not isinstance(e, EventPublish) or \
                e.msg.topic   != pubtopic or \
                e.msg.payload != msg:
            if match: debug("invalid received msg: {0}".format(e))
            return False

        return True

