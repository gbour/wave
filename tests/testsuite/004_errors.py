#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

import random

class Errors(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "error cases")

    def newclient(self, name="req", autoconnect=False):
        c = MqttClient(name)
        if autoconnect:
            c.do("connect")

        return c

    @catch
    @desc("CONNACK=0x02 :: clientid already connected")
    def test_001(self):
        c = MqttClient("twice01", rand=False)
        evt = c.do("connect")
        # OK
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        c2  = MqttClient("twice01", rand=False)
        evt = c2.do("connect")
        # identifier rejected
        if not isinstance(evt, EventConnack) or evt.ret_code != 2:
            return False

    
        # disconnecting client #1, client #2 connection now works
        c.disconnect()

        evt = c2.do("connect")
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        return True

    @catch
    @desc("PUBLISH remaining length header : 0 bytes message length")
    def test_010(self):
        pub = self.newclient('pub', autoconnect=True)
        sub = self.newclient('sub', autoconnect=True)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        msg = ''

        puback_evt = pub.publish('a/b', msg, qos=1)
        if not isinstance(puback_evt, EventPuback) or \
            puback_evt.mid != pub.get_last_mid():
                return False

        publish_evt = sub.recv()
        if not isinstance(publish_evt, EventPublish) or \
            publish_evt.msg.payloadlen != 0 or \
            publish_evt.msg.payload is not None:
                return False

        return True

    @catch
    @desc("PUBLISH remaining length header : 1 byte long")
    def test_011(self):
        pub = self.newclient('pub', autoconnect=True)
        sub = self.newclient('sub', autoconnect=True)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        #       120 + 5 + 2 = 127
        msglen = 120
        msg = ''.join([chr(48+random.randint(0,42)) for x in xrange(msglen)])
        #print "msg=", msg, len(msg)

        puback_evt = pub.publish('a/b', msg, qos=1)
        if not isinstance(puback_evt, EventPuback) or \
            puback_evt.mid != pub.get_last_mid():
                return False

        publish_evt = sub.recv()
        if not isinstance(publish_evt, EventPublish) or \
            publish_evt.msg.payloadlen != msglen or \
            publish_evt.msg.payload != msg:
                return False

        return True

    @catch
    @desc("PUBLISH remaining length header : 2 bytes long")
    def test_012(self):
        pub = self.newclient('pub', autoconnect=True)
        sub = self.newclient('sub', autoconnect=True)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        #       150 + 5 + 2 = 157 >= 128
        msglen = 150
        msg = ''.join([chr(48+random.randint(0,42)) for x in xrange(msglen)])
        #print "msg=", msg, len(msg)

        puback_evt = pub.publish('a/b', msg, qos=1)
        if not isinstance(puback_evt, EventPuback) or \
            puback_evt.mid != pub.get_last_mid():
                return False

        publish_evt = sub.recv()
        if not isinstance(publish_evt, EventPublish) or \
            publish_evt.msg.payloadlen != msglen or \
            publish_evt.msg.payload != msg:
                return False

        return True

    @catch
    @desc("PUBLISH remaining length header : 3 bytes long")
    def test_013(self):
        pub = self.newclient('pub', autoconnect=True)
        sub = self.newclient('sub', autoconnect=True)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        msglen = 17000
        msg = ''.join([chr(48+random.randint(0,42)) for x in xrange(msglen)])
        #print "msg=", msg, len(msg)

        puback_evt = pub.publish('a/b', msg, qos=1)
        if not isinstance(puback_evt, EventPuback) or \
            puback_evt.mid != pub.get_last_mid():
                return False

        publish_evt = sub.recv()
        if not isinstance(publish_evt, EventPublish) or \
            publish_evt.msg.payloadlen != msglen or \
            publish_evt.msg.payload != msg:
                return False

        return True

