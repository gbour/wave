#!/usr/bin/env python
# -*- coding: UTF8 -*-

import time
import socket

from TestSuite       import *
from mqttcli         import MqttClient
from nyamuk.event    import *
from nyamuk.mqtt_pkt import MqttPkt


class Will(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "Last Will & Testament")


    @catch
    @desc("no will")
    def test_01(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 0)

        client  = MqttClient("rabbit", connect=4)
        # close socket without disconnection
        client.socket_close()

        if monitor.recv() != None:
            return False

        monitor.disconnect()
        return True

    @catch
    @desc("will: close socket w/o DISCONNECT")
    def test_02(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 0)

        client  = MqttClient("rabbit")
        will    = {'topic': '/node/disconnect', 'message': client.clientid()}
        client.connect(version=4, will=will)
        # close socket without disconnection
        client.socket_close()

        evt = monitor.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != will['topic'] or \
                evt.msg.payload != will['message']:
            return False

        monitor.disconnect()
        return True

    @catch
    @desc("will: on KeepAlive timeout")
    def test_03(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 0)

        client  = MqttClient("rabbit", keepalive=2)
        will    = {'topic': '/node/disconnect', 'message': client.clientid()}
        client.connect(version=4, will=will)

        time.sleep(1)
        client.send_pingreq()
        if monitor.recv() != None:
            return False

        time.sleep(4)
        evt = monitor.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != will['topic'] or \
                evt.msg.payload != will['message']:
            return False

        monitor.disconnect()
        return True

    @catch
    @desc("will: on protocol error")
    def test_04(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 0)

        client  = MqttClient("rabbit") # no keepalive
        will    = {'topic': '/node/disconnect', 'message': client.clientid()}
        client.connect(version=4, will=will)

        # protocol errlr flags shoud be 0
        client.forge(NC.CMD_PINGREQ, 4, [], send=True)
        if client.conn_is_alive():
            return False

        evt = monitor.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != will['topic'] or \
                evt.msg.payload != will['message']:
            return False

        monitor.disconnect()
        return True
