# -*- coding: UTF8 -*-

import time
import socket

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from lib.env import gen_msg, debug

class Errors(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "error cases")


    def test_010(self):
        pub = MqttClient('pub', connect=4)
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        puback_evt = pub.publish('a/b', payload='', qos=1)
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
        pub = MqttClient('pub', connect=4)
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        #       120 + 5 + 2 = 127
        msg = gen_msg(120)
        #print "msg=", msg, len(msg)

        puback_evt = pub.publish('a/b', msg, qos=1)
        if not isinstance(puback_evt, EventPuback) or \
                puback_evt.mid != pub.get_last_mid():
            return False

        publish_evt = sub.recv()
        if not isinstance(publish_evt, EventPublish) or \
                publish_evt.msg.payloadlen != len(msg) or \
                publish_evt.msg.payload != msg:
            return False

        return True

    @catch
    @desc("PUBLISH remaining length header : 2 bytes long")
    def test_012(self):
        pub = MqttClient('pub', connect=4)
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        #       150 + 5 + 2 = 157 >= 128
        msg = gen_msg(150)
        #print "msg=", msg, len(msg)

        puback_evt = pub.publish('a/b', msg, qos=1)
        if not isinstance(puback_evt, EventPuback) or \
                puback_evt.mid != pub.get_last_mid():
            return False

        publish_evt = sub.recv()
        if not isinstance(publish_evt, EventPublish) or \
                publish_evt.msg.payloadlen != len(msg) or \
                publish_evt.msg.payload != msg:
            return False

        return True

    @catch
    @desc("PUBLISH remaining length header : 3 bytes long")
    def test_013(self):
        pub = MqttClient('pub', connect=4)
        sub = MqttClient('sub', connect=4)
        sub.subscribe('a/b', 0)

        # NOTE: remaining length value is message length + 5 bytes (topic encoded) + 2 bytes (msgid)
        msg = gen_msg(17000)
        #print "msg=", msg, len(msg)

        puback_evt = pub.publish('a/b', msg, qos=1)
        if not isinstance(puback_evt, EventPuback) or \
                puback_evt.mid != pub.get_last_mid():
            return False

        publish_evt = sub.recv()
        if not isinstance(publish_evt, EventPublish) or \
                publish_evt.msg.payloadlen != len(msg) or \
                publish_evt.msg.payload != msg:
            return False

        return True

    @catch
    @desc("empty socket lead to socket closed after timeout")
    def test_020(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 1883))
        s.setblocking(0)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)

        time.sleep(6) # connect timeout is 5 secs
        # close socket triggers a broken pipe (errno 32)
        try:
            s.send("foobar")
            s.recv(0)
            s.send("foobar")
        except Exception as (errno, msg):
            #print "exc", errno, msg
            return (errno == 32)

        return False

