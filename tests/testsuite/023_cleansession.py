#!/usr/bin/env python
# -*- coding: utf8 -*-

from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

import time
import socket

class CleanSession(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "Clean Session")

    @catch
    @desc("[MQTT-3.1.3.7] 0-length clientid forbidden when clean-session flag is 0")
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
                ack.ret_code != 2:
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
                ack.ret_code != 0:
            return False

        return True
