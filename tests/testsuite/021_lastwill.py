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

    @catch
    @desc("will: qos 1")
    def test_05(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 2)

        client  = MqttClient("rabbit") # no keepalive
        will    = {'topic': '/node/disconnect', 'message': client.clientid(), 'qos': 1}
        client.connect(version=4, will=will)
        client.socket_close()

        evt = monitor.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != will['topic'] or \
                evt.msg.payload != will['message'] or \
                evt.msg.qos != 1:
            return False

        monitor.puback(evt.msg.mid)
        monitor.disconnect()
        return True

    @catch
    @desc("will: qos 2")
    def test_06(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 2)

        client  = MqttClient("rabbit") # no keepalive
        will    = {'topic': '/node/disconnect', 'message': client.clientid(), 'qos': 2}
        client.connect(version=4, will=will)
        client.socket_close()

        evt = monitor.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != will['topic'] or \
                evt.msg.payload != will['message'] or \
                evt.msg.qos != 2:
            return False

        monitor.disconnect()
        return True

    @catch
    @desc("[MQTT-3.1.2-13] if will flag set to 0, will-qos MUST be 0")
    def test_07(self):
        client  = MqttClient("rabbit", raw_connect=True)
        client.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 8),         # will=0, will-qos=1
            ('uint16', 60),        # keepalive
        ], send=True)
        if client.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-14] if will flag set to 1, will-qos MAY be 0,1 or 2 (NOT 3)")
    def test_08(self):
        client  = MqttClient("rabbit", raw_connect=True)
        client.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 28),        # will=1, will-qos=3
            ('uint16', 60),        # keepalive
        ], send=True)
        if client.conn_is_alive():
            return False

        client  = MqttClient("rabbit", raw_connect=True)
        client.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 12),        # will=1, will-qos=1
            ('uint16', 60),        # keepalive
            ('string', client._c.client_id),   # clientid
            ('string', '/foo/bar'),# will topic
            ('uint16', 0),         # will payload len
            ('bytes' , ''),        # will payload
        ], send=True)

        evt = client.recv()
        if not isinstance(evt, EventConnack):
            return False

        client.disconnect()
        return True

    @catch
    @desc("[MQTT-3.1.2-15] if will flag set to 1, will-retain MUST be 0")
    def test_10(self):
        client  = MqttClient("rabbit", raw_connect=True)
        client.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            ('byte'  , 32),        # will=0, will-retain=1
            ('uint16', 60),        # keepalive
        ], send=True)
        if client.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-16] if will-retain flag set to 1, will message published with retain unset")
    def test_11(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 2)

        client  = MqttClient("rabbit") # no keepalive
        will    = {'topic': '/node/disconnect', 'message': client.clientid(), 'retain': False}
        client.connect(version=4, will=will)
        client.socket_close()

        evt = monitor.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != will['topic'] or \
                evt.msg.payload != will['message'] or \
                evt.msg.qos != 0:
            return False

        if evt.msg.retain:
            return False

        monitor.disconnect()
        return True

    #TODO: qos or retain set to 1 while will set to 0 => disconnect
    @catch
    @desc("[MQTT-3.1.2-17] if will-retain flag set, will message published with retain set")
    def test_12(self):
        monitor = MqttClient("monitor", connect=4)
        # NOTE: '/' prefix skips $ messages
        # TODO: remove it when '$' filter will be impl.
        monitor.subscribe("/#", 2)

        client  = MqttClient("rabbit") # no keepalive
        will    = {'topic': '/node/disconnect', 'message': client.clientid(), 'retain': True}
        client.connect(version=4, will=will)
        client.socket_close()

        evt = monitor.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != will['topic'] or \
                evt.msg.payload != will['message'] or \
                evt.msg.qos != 0:
            return False

        if not evt.msg.retain:
            return False

        monitor.disconnect()
        return True

