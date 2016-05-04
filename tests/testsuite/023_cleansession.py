#!/usr/bin/env python
# -*- coding: utf8 -*-

import time
import redis
import socket

from lib import env
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

class CleanSession(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "Clean Session")

    @catch
    @desc("[MQTT-3.1.3.7,MQTT-3.1.3-8,MQTT-3.2.2-4] 0-length clientid forbidden when clean-session flag is 0")
    def test_001(self):
        c = MqttClient("cs", raw_connect=True)

        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 0),         # cleansession 0
            ('uint16', 60),        # keepalive
            ('string', ''),        # 0-length client-if
        ], send=True)

        ack = c.recv()
        if not isinstance(ack, EventConnack) or\
                ack.ret_code != 2 or\
                ack.session_present != 0:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.3-7] 0-length clientid allowed wen clean-session flag is 1")
    def test_002(self):
        c = MqttClient("cs", raw_connect=True)

        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 2),         # cleansession 1
            ('uint16', 60),        # keepalive
            ('string', ''),        # 0-length client-if
        ], send=True)

        ack = c.recv()
        if not isinstance(ack, EventConnack) or\
                ack.ret_code != 0 or\
                ack.session_present != 0:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.3-7] 2 clients (cleansession 1, 0-length clientid) allowed to connect")
    def test_003(self):
        c = MqttClient("cs", raw_connect=True)
        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 2),         # cleansession 1
            ('uint16', 60),        # keepalive
            ('string', ''),        # 0-length client-if
        ], send=True)

        ack = c.recv()
        if not isinstance(ack, EventConnack) or\
                ack.ret_code != 0 or\
                ack.session_present != 0:
            return False

        c2 = MqttClient("cs", raw_connect=True)
        c2.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 2),         # cleansession 1
            ('uint16', 60),        # keepalive
            ('string', ''),        # 0-length client-if
        ], send=True)

        ack = c2.recv()
        if not isinstance(ack, EventConnack) or\
                ack.ret_code != 0 or\
                ack.session_present != 0:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-4] when clean-session unset, subscriptions MUST be saved when client disconnected")
    def test_010(self):
        c = MqttClient("cs", connect=4, clean_session=0)
        c.subscribe("/cs/qos-0", qos=0)
        c.subscribe("/cs/qos-1", qos=1)
        c.subscribe("/cs/qos-2", qos=2)

        c.disconnect()

        # sleep ensure redis data has been written
        time.sleep(.5)
        topics = env.db.lrange("topics:" + c.clientid(), 0, -1)
        topics = dict(map(lambda x: topics[x:x+2], xrange(0, len(topics), 2)))

        if len(topics) != 3:
            return False
        if int(topics.get('/cs/qos-0', -1)) != 0:
            return False
        if int(topics.get('/cs/qos-1', -1)) != 1:
            return False
        if int(topics.get('/cs/qos-2', -1)) != 2:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-6,MQTT-3.1.4-3] when clean-session unset, saved subscriptions are restored (1/2)")
    def test_011(self):
        c = MqttClient("cs", connect=4, clean_session=0)
        c.subscribe("/cs/qos-0", qos=0)
        c.subscribe("/cs/qos-1", qos=1)
        c.subscribe("/cs/qos-2", qos=2)

        c.disconnect()

        # reconnect w/ same clientid
        time.sleep(.5)
        c2 = MqttClient(client_id=c.client_id, connect=4, clean_session=0)

        topics = env.db.lrange("topics:" + c.clientid(), 0, -1)
        if len(topics) != 0:
            return False

        # checking CONNACK session-present
        if c2.connack().session_present != 1:
            return False

        #TODO: list c2 subscriptions (needs specific API ?)
        return True

    @catch
    @desc("[MQTT-3.1.2-6,MQTT-3.1.4-3] when clean-session unset, saved subscriptions are restored (2/2)")
    def test_012(self):
        pub = MqttClient("publisher", connect=4)

        c = MqttClient("cs", connect=4, clean_session=0)
        if c.connack().session_present != 0:
            return False
        c.subscribe("/cs/qos-0", qos=0)
        c.disconnect()

        # reconnect w/ same clientid
        time.sleep(.5)
        c2 = MqttClient(client_id=c.client_id, connect=4, clean_session=0)
        if c2.connack().session_present != 1:
            return False

        pub.publish("/cs/qos-0", "", qos=1)
        evt = c2.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != '/cs/qos-0' or\
                evt.msg.qos != 0:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-6,MQTT-3.1.4-3,MQTT-3.2.2-1] if clean-session set, previous subscriptions MUST be discarded")
    def test_013(self):
        pub = MqttClient("publisher", connect=4)

        c = MqttClient("cs", connect=4, clean_session=0)
        if c.connack().session_present != 0:
            return False
        c.subscribe("/cs/qos-0", qos=0)
        c.disconnect()

        # reconnect w/ same clientid, cleansession = 1
        time.sleep(.5)
        c2 = MqttClient(client_id=c.client_id, connect=4, clean_session=1)
        if c2.connack().session_present != 0:
            return False

        pub.publish("/cs/qos-0", "", qos=1)
        evt = c2.recv()
        if evt is not None:
            return False

        return True

    @catch
    @desc("[MQTT-3.2.2-2,MQTT-3.2.2-3] CONNACK session_present set EVEN if client had no subscriptions")
    def test_014(self):
        c = MqttClient("cs", connect=4, clean_session=0)
        if c.connack().session_present != 0:
            return False
        c.disconnect()

        # reconnect w/ same clientid, cleansession = 0
        time.sleep(.5)
        c2 = MqttClient(client_id=c.client_id, connect=4, clean_session=0)
        if c2.connack().session_present != 1:
            return False

        c2.disconnect()
        return True

    
