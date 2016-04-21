#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import *
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

    @catch
    @desc("[MQTT-3.1.3-5] 0-length clientid")
    def test_108(self):
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
        pkt.remaining_length = 12 # + 4 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_4)
        pkt.write_byte(0)      # flags
        pkt.write_uint16(10)   # keepalive
        pkt.write_string("")   # client id

        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop()
        evt = c._c.pop_event()

        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.3-5] > 23 characters clientid")
    def test_109(self):
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
        pkt.remaining_length = 12 + 26 # client_id = "ff"
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_4)
        pkt.write_byte(0)      # flags
        pkt.write_uint16(10)   # keepalive
        pkt.write_string("ABCDEFGHIJKLMNOPQRSTUVWXYZ") # client id - 26 chars

        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop()
        evt = c._c.pop_event()
        print evt

        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        return True

    @catch
    @desc("[MQTT-3.1.3-5] clientid invalid characters")
    def test_110(self):
        c = MqttClient("conformity")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            return False

        c._c.sock = sock

        clientid = "é!;~«ä"
        #clientid = clientid.decode('utf8')

        pkt = MqttPkt()
        pkt.command = NC.CMD_CONNECT
        pkt.remaining_length = 12 + len(clientid) # client_id 
        pkt.alloc()

        pkt.write_string("MQTT")
        pkt.write_byte(NC.PROTOCOL_VERSION_4)
        pkt.write_byte(0)      # flags
        pkt.write_uint16(10)   # keepalive
        pkt.write_string(clientid) # client id - 6 chars

        c._c.packet_queue(pkt)
        c._c.packet_write()
        c._c.loop()

        evt = c._c.pop_event()
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        return True

    @catch
    @desc("[MQTT-2.2.2-1,MQTT-2.2.2-2] reserved flags")
    def test_112(self):
        ## PINGREG
        c = MqttClient("conformity", raw_connect=True)
        evt = c.connect(version=4)

        # flags shoud be 0
        c.forge(NC.CMD_PINGREQ, 4, [], send=True)
        if c.conn_is_alive():
            return False

        ## SUBSCRIBE
        c = MqttClient("conformity2", raw_connect=True)
        evt = c.connect(version=4)

        # flags shoud be 2
        c.forge(NC.CMD_SUBSCRIBE, 3, [
            ('uint16', 42),         # identifier
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 0)           # qos
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] missing packet identifier (SUBSCRIBE)")
    def test_113(self):
        c = MqttClient("conformity", raw_connect=True)
        evt = c.connect(version=4)

        c.forge(NC.CMD_SUBSCRIBE, 2, [
            #('uint16', 0),         # identifier not included
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 0)           # qos
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] non-zero packet identifier (SUBSCRIBE)")
    def test_114(self):
        c = MqttClient("conformity", raw_connect=True)
        evt = c.connect(version=4)

        c.forge(NC.CMD_SUBSCRIBE, 2, [
            ('uint16', 0),         # identifier
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 0)           # qos
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] non-zero packet identifier (UNSUBSCRIBE)")
    def test_115(self):
        c = MqttClient("conformity", raw_connect=True)
        evt = c.connect(version=4)

        c.forge(NC.CMD_UNSUBSCRIBE, 2, [
            ('uint16', 0),         # identifier
            ('string', '/foo/bar'), # topic filter
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] non-zero packet identifier (PUBLISH)")
    def test_116(self):
        c = MqttClient("conformity", raw_connect=True)
        evt = c.connect(version=4)

        # qos 1
        c.forge(NC.CMD_PUBLISH, 2, [
            ('string', '/foo/bar'), # topic 
            ('uint16', 0),         # identifier
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBACK pktid not matching PUBLISH pktid")
    def test_200(self):
        pub = MqttClient("conformity-pub", connect=4)
        sub = MqttClient("conformity-sub", connect=4)

        sub.subscribe("foo/bar", qos=1)
        pub.publish("foo/bar", "wootwoot", qos=1)

        # reading PUBLISH
        evt = sub.recv()

        # sending PUBACK with wrong pktid
        sub.forge(NC.CMD_PUBACK, 0, [
            ('uint16', (evt.msg.mid+10)%65535) # wrong pktid
        ], send=True)

        evt = pub.recv()
        # PUBACK from server is never received
        if evt is not None:
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBREC pktid not matching PUBLISH pktid")
    def test_201(self):
        pub = MqttClient("conformity-pub", connect=4)
        sub = MqttClient("conformity-sub", connect=4)

        sub.subscribe("foo/bar", qos=2)
        pub.publish("foo/bar", "wootwoot", qos=2, read_response=False)

        # PUB PUBREC
        evt = pub.recv()
        pub.pubrel(pub.get_last_mid(), read_response=False)

        # reading PUBLISH
        evt = sub.recv()

        # sending PUBREC with wrong pktid
        sub.forge(NC.CMD_PUBREC, 0, [
            ('uint16', (evt.msg.mid+10)%65535) # wrong pktid
        ], send=True)

        evt = pub.recv()
        # PUBCOMP from server is never received
        if evt is not None:
            return False

        evt = sub.recv()
        # PUBREL not received
        if evt is not None:
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBREL pktid not matching PUBLISH pktid")
    def test_202(self):
        pub = MqttClient("conformity-pub", connect=4)
        sub = MqttClient("conformity-sub", connect=4)

        sub.subscribe("foo/bar", qos=2)
        pub.publish("foo/bar", "wootwoot", qos=2, read_response=False)

        # PUB PUBREC
        evt = pub.recv()
        # sending PUBREL with wrong pktid
        pub.forge(NC.CMD_PUBREL, 2, [
            ('uint16', (evt.mid+10)%65535) # wrong pktid
        ], send=True)

        # subscriber: PUBLISH never received
        evt = sub.recv()
        if evt is not None:
            return False

        evt = pub.recv()
        # publisher: PUBCOMP never received
        if evt is not None:
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBCOMP pktid not matching PUBLISH pktid")
    def test_203(self):
        pub = MqttClient("conformity-pub", connect=4)
        sub = MqttClient("conformity-sub", connect=4)

        sub.subscribe("foo/bar", qos=2)
        pub.publish("foo/bar", "wootwoot", qos=2, read_response=False)

        # PUB PUBREC
        evt = pub.recv()
        pub.pubrel(pub.get_last_mid(), read_response=False)

        # subscr: receiving PUBLISH
        evt = sub.recv()
        sub.pubrec(evt.msg.mid, read_response=False)

        # subscr: receiving PUBREL
        evt = sub.recv()

        # sending PUBCOMP with wrong pktid
        sub.forge(NC.CMD_PUBCOMP, 0, [
            ('uint16', (evt.mid+10)%65535) # wrong pktid
        ], send=True)


        evt = pub.recv()
        # publisher: PUBCOMP never received
        if evt is not None:
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-3.3.1-4] invalid PUBLISH qos value (3)")
    def test_211(self):
        c = MqttClient("conformity", connect=4)

        c.forge(NC.CMD_PUBLISH, 6, [
            ('string', '/foo/bar'), # topic
            ('uint16', 0),          # identifier
        ], send=True)
        if c.conn_is_alive():
            return False

        return True


    @skip
    @catch
    @desc("[MQTT-3.3.2-1] no topic name in PUBLISH message")
    def test_212(self):
        c = MqttClient("conformity", connect=4)

        # qos 1
        c.forge(NC.CMD_PUBLISH, 2, [], send=True)
#            ('uint16', 0),          # identifier
#        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-3.3.2-2] wildcard characters (+ and #) are forbidden in PUBLISH topic")
    def test_213(self):
        c = MqttClient("conformity", connect=4)
        c.publish("foo/+/bar", "", qos=0)
        if c.conn_is_alive():
            return False

        c = MqttClient("conformity", connect=4)
        c.publish("foo/#/bar", "", qos=0)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-3.8.3-1] SUBSCRIBE MUST have at least one topic filter/qos")
    def test_214(self):
        c = MqttClient("conformity", connect=4)

        c.forge(NC.CMD_SUBSCRIBE, 2, [
            ('uint16', 10),         # identifier
            # NOT TOPIC FILTER/QOS
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-3.8.3-4] SUBSCRIBE qos is 0,1 or 2")
    def test_215(self):
        c = MqttClient("conformity", connect=4)
        c.forge(NC.CMD_SUBSCRIBE, 2, [
            ('uint16', 42),         # identifier
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 3)           # qos
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-3.8.4-4, MQTT-3.8.4-5] SUBSCRIBE with multiple (>1) topicfilters, granted qoses returned in PUBACK resp")
    def test_216(self):
        pub = MqttClient("conformity-pub", connect=4)
        sub = MqttClient("conformity-sub", connect=4)

        ack = sub.subscribe_multi([
            ("foo/bar", 2),
            ("bar/baz", 0),
            ("paper/+/scissor", 1)
        ])

        if not isinstance(ack, EventSuback) or ack.mid != sub.get_last_mid():
            return False

        # checking granted qos
        if len(ack.granted_qos) != 3 or \
                ack.granted_qos[0] != 2 or \
                ack.granted_qos[1] != 0 or \
                ack.granted_qos[2] != 1:
            return False

        return True

    @catch
    @desc("[MQTT-3.10.3-2] UNSUBSCRIBE MUST have at least one topic filter/qos")
    def test_220(self):
        c = MqttClient("conformity", connect=4)

        c.forge(NC.CMD_UNSUBSCRIBE, 2, [
            ('uint16', 10),         # identifier
            # NOT TOPIC FILTER/QOS
        ], send=True)
        if c.conn_is_alive():
            return False

        return True

    @catch
    @desc("[MQTT-3.10.4-5] UNSUBACK returned even without matching subscription")
    def test_221(self):
        c = MqttClient("conformity", connect=4)
        ack = c.unsubscribe("foo/bar")
        if not isinstance(ack, EventUnsuback):
            return False

        return True

