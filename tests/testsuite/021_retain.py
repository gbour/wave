#!/usr/bin/env python
# -*- coding: UTF8 -*-

from lib import env
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

import time
import socket


class Retain(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "Retained messages")

    @catch
    @desc("[MQTT-3.3.1-7] retain published message (qos 0)")
    def test_001(self):
        c = MqttClient("conformity", connect=4)

        c.publish("/foo/bar/0", "plop", qos=0, retain=True)
        c.disconnect()

        # checking message as been store in db
        store = env.db.hgetall('retain:/foo/bar/0')
        if not (store.get('data') == 'plop' and store.get('qos') == '0'):
            return False

        return True

    @catch
    @desc("retain published message (qos 1)")
    def test_002(self):
        c = MqttClient("conformity", connect=4)
        c.publish("/foo/bar/1", "plop", qos=1, retain=True)
        c.disconnect()

        # checking message as been store in db
        store = env.db.hgetall('retain:/foo/bar/1')
        if store.get('data') != 'plop' or store.get('qos') != '1':
            return False

        return True

    @catch
    @desc("retain published message (qos 2)")
    def test_003(self):
        c = MqttClient("conformity", connect=4)
        c.publish("/foo/bar/2", "plop", qos=2, retain=True)
        c.disconnect()

        # checking message as been store in db
        store = env.db.hgetall('retain:/foo/bar/2')
        if store.get('data') != 'plop' or store.get('qos') != '2':
            return False

        return True

    #TODO: test binary data

    @catch
    @desc("[MQTT-3.3.1-10,MQTT-3.3.1-11] retain: delete retained message")
    def test_010(self):
        c = MqttClient("conformity", connect=4)
        c.publish("/retain/delete", 'waze', qos=0, retain=True)

        store = env.db.hgetall("retain:/retain/delete")
        if store != {'data': 'waze', 'qos': '0'}: 
            return False

        # deleting message
        c.publish("/retain/delete", '', retain=True)
        if env.db.keys('retain:/retain/delete') != []:
            return False

        c.disconnect()
        return True

    @catch
    @desc("[MQTT-3.3.1-12] if retain flag unset, msg MUST NOT be stored nor replace nor remove existing msg")
    def test_011(self):
        c = MqttClient("conformity", connect=4)

        # initial state
        c.publish("/retain/no/2", 'waze', retain=True)
        if env.db.keys('retain:/retain/no/*') != ['retain:/retain/no/2']:
            return False

        # not stored
        c.publish('/retain/no/1', 'whaa', retain=False)
        if env.db.keys('retain:/retain/no/*') != ['retain:/retain/no/2']:
            return False

        # no replace or remove
        c.publish('/retain/no/2', 'whaa', retain=False)
        store = env.db.hgetall("retain:/retain/no/2")
        if store != {'data': 'waze', 'qos': '0'}: 
            return False

        c.disconnect()
        return True

    @catch
    @desc("[MQTT-3.3.1-10] message w/ retain flag must be processed as normal message & delivered 2 subscribers")
    def test_012(self):
        pub = MqttClient("conformity", connect=4)
        sub = MqttClient("sub", connect=4)
        sub.subscribe("/retain/+", qos=0)

        pub.publish("/retain/delivered", 'waze', retain=True)
        msg = sub.recv()
        if not isinstance(msg, EventPublish) or \
                msg.msg.topic != '/retain/delivered' or \
                msg.msg.payload != 'waze':
            return False

        # same with empty payload
        pub.publish("/retain/empty", '', retain=True)
        msg = sub.recv()
        if not isinstance(msg, EventPublish) or \
                msg.msg.topic != '/retain/empty' or \
                msg.msg.payload != None:
            return False

        return True
