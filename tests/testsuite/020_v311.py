#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

import time
import socket


class V311(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "MQTT version 3.1.1")

    def newclient(self, name="req", *args, **kwargs):
        c = MqttClient(name)
        c.connect(version = 4)

        return c

    @catch
    @desc("CONNECT")
    def test_01(self):
        c = MqttClient("reg")
        evt = c.connect(version=4)

        if not isinstance(evt, EventConnack) or \
            evt.ret_code:
            return False

        return True

    #TODO: we must hook disconnect method such as we send DISCONNECT message but don't close the socket
    #      then we check server has closed the socket
    @catch
    @desc("DISCONNECT")
    def test_02(self):
        c = self.newclient()
        #evt = c._c.disconnect()
        c.disconnect()

        return True

    @catch
    @desc("SUBSCRIBE")
    def test_10(self):
        c = MqttClient("reg")
        c.do("connect")

        evt = c.do("subscribe", "/foo/bar", 0)
        c.disconnect()
        if not isinstance(evt, EventSuback):
            return False

        return True

    @catch
    @desc("PUBLISH (qos=0). no response")
    def test_11(self):
        c = self.newclient()
        e = c.publish("/foo/bar", "plop")
        # QOS = 0 : no response indented
        if e is not None:
            c.disconnect()
            return False

        c.disconnect()
        return True

    @catch
    @desc("PING REQ/RESP")
    def test_20(self):
        c = self.newclient()
        e = c.send_pingreq()
        c.disconnect()

        return isinstance(e, EventPingResp)



    #
    # ==== conformity tests ====
    #

    @catch
    @desc("[MQTT-3.1.0-1] 1st pkt MUST be connect")
    def test_100(self):
        c = MqttClient('conformity')

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock
        e = c.subscribe("foo/bar", 0)
        if e is not None:
            return False

        # socket MUST be disconnected
        try:
            e = c.publish("foo", "bar")
            sock.getpeername()
        except socket.error as e:
            #print e
            return True

        return False

    @catch
    @desc("[MQTT-3.1.0-2] pkt following a successful connect MUST NOT be connect")
    def test_101(self):
        c = MqttClient("conformity")
        evt = c.connect(version=4)

        if not isinstance(evt, EventConnack) or \
            evt.ret_code:
            return False

        # 2d connect pkt
        pkt = MqttPkt()
        pkt.connect_build(c._c, keepalive=60, clean_session=1, version=4)
        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop()

        try:
            c.publish("foo","bar")
            c._c.sock.getpeername()
        except socket.error as e:
            return True

        return False

    @catch
    @desc("[MQTT-3.1.2-1] protocol name validation")
    def test_102(self):
        c = MqttClient("conformity")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock

        pkt = MqttPkt()
        pkt.command = NC.CMD_CONNECT
        pkt.remaining_length = 12 + 4 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MqTt")
        pkt.write_byte(NC.PROTOCOL_VERSION_4) # = 4
        pkt.write_string("ff")

        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop()

        try:
            c.send_pingreq()
            c._c.sock.getpeername()
        except socket.error as e:
            return True

        return False

    @catch
    @desc("[MQTT-3.1.2-2] protocol version validation")
    def test_103(self):
        c = MqttClient("conformity")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock

        pkt = MqttPkt()
        pkt.command = NC.CMD_CONNECT
        pkt.remaining_length = 12 + 4 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_3)
        pkt.write_byte(0)      # flags
        pkt.write_uint16(60)   # keepalive
        pkt.write_string("ff") # client id

        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop() # should return CONN_REFUSED
        evt = c._c.pop_event()

        if not isinstance(evt, EventConnack) or evt.ret_code != 1:
            return False

        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-3] CONNECT reserve flag MUST be set to zero")
    def test_104(self):
        c = MqttClient("conformity")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock

        pkt = MqttPkt()
        pkt.command = NC.CMD_CONNECT
        pkt.remaining_length = 12 + 4 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_3)
        pkt.write_byte(1)      # flags - reserve set to 1
        pkt.write_uint16(60)   # keepalive
        pkt.write_string("ff") # client id

        c._c.packet_queue(pkt)
        c._c.packet_write()

        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-22] if username flag is not set, password flag must not be set")
    def test_105(self):
        c = MqttClient("conformity")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock

        pkt = MqttPkt()
        pkt.command = NC.CMD_CONNECT
        pkt.remaining_length = 12 + 4 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_4)
        pkt.write_byte(1 << 6) # set password flag
        pkt.write_uint16(60)   # keepalive
        pkt.write_string("ff") # client id

        c._c.packet_queue(pkt)
        c._c.packet_write()

        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-24] client is disconnected after expired KeepAlive (test 1)")
    def test_106(self):
        c = MqttClient("conformity")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock

        pkt = MqttPkt()
        pkt.command = NC.CMD_CONNECT
        pkt.remaining_length = 12 + 4 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_4)
        pkt.write_byte(0)      # flags
        pkt.write_uint16(10)   # keepalive
        pkt.write_string("ff") # client id

        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop()
        evt = c._c.pop_event()

        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        time.sleep(15.5)
        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-24] client is disconnected after expired KeepAlive (test 2)")
    def test_107(self):
        c = MqttClient("conformity")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock

        pkt = MqttPkt()
        pkt.command = NC.CMD_CONNECT
        pkt.remaining_length = 12 + 4 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_4)
        pkt.write_byte(0)      # flags
        pkt.write_uint16(10)   # keepalive
        pkt.write_string("ff") # client id

        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop()
        evt = c._c.pop_event()

        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        time.sleep(2)
        evt = c.publish("foo", "bar", 1)
        if not isinstance(evt, EventPuback):
            return False

        time.sleep(15.5)
        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            return False

        return True
