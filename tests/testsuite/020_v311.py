# -*- coding: UTF8 -*-

import time
import socket

from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt
from lib.env import debug


class V311(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "MQTT version 3.1.1")


    @catch
    @desc("CONNECT")
    def test_001(self):
        c = MqttClient("v311:{seq}")
        evt = c.connect(version=4)

        if not isinstance(evt, EventConnack) or \
                evt.ret_code:
            debug(evt)
            return False

        return True

    #TODO: we must hook disconnect method such as we send DISCONNECT message but don't close the socket
    #      then we check server has closed the socket
    @catch
    @desc("DISCONNECT")
    def test_002(self):
        c = MqttClient("v311:{seq}", connect=4)
        #evt = c._c.disconnect()
        c.disconnect()

        return True

    @catch
    @desc("SUBSCRIBE")
    def test_010(self):
        c = MqttClient("v311:{seq}", connect=4)

        evt = c.subscribe("/foo/bar", qos=0)
        c.disconnect()
        if not isinstance(evt, EventSuback):
            debug(evt)
            return False

        return True

    @catch
    @desc("PUBLISH (qos=0). no response")
    def test_011(self):
        c = MqttClient("v311:{seq}", connect=4)
        e = c.publish("/foo/bar", payload="plop")
        # QOS = 0 : no response indented
        if e is not None:
            debug(e)
            c.disconnect()
            return False

        c.disconnect()
        return True

    @catch
    @desc("PING REQ/RESP")
    def test_020(self):
        c = MqttClient("v311:{seq}", connect=4)
        e = c.send_pingreq()
        c.disconnect()

        return isinstance(e, EventPingResp)



    #
    # ==== conformity tests ====
    #

    @catch
    @desc("[MQTT-3.1.0-1] 1st pkt MUST be connect")
    def test_100(self):
        c = MqttClient("conformity:{seq}")

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        e = c.subscribe("foo/bar", qos=0)
        if e is not None:
            debug(e)
            return False

        # socket MUST be disconnected
        try:
            e = c.publish("foo", "bar")
            sock.getpeername()
        except socket.error as e:
            return True

        debug("connection still alive")
        return False

    @catch
    @desc("[MQTT-3.1.0-2] pkt following a successful connect MUST NOT be connect")
    def test_101(self):
        c = MqttClient("conformity:{seq}")
        evt = c.connect(version=4)

        if not isinstance(evt, EventConnack) or \
                evt.ret_code:
            debug(e)
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

        debug("connection still alive")
        return False

    @catch
    @desc("[MQTT-3.1.2-1] protocol name validation")
    def test_102(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MqTt'),
            ('byte'  , NC.PROTOCOL_VERSION_4),
            ('string', 'ff') # client id
        ], send=True)

        try:
            c.send_pingreq()
            c._c.sock.getpeername()
        except socket.error as e:
            return True

        debug("connection still alive")
        return False

    @catch
    @desc("[MQTT-3.1.2-2] protocol version validation")
    def test_103(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , NC.PROTOCOL_VERSION_3),
            ('byte'  , 0),   # flags
            ('uint16', 60),  # keepalive
            ('string', 'ff') # client id
        ], send=True) # should return CONN_REFUSED

        evt = c._c.pop_event()
        if not isinstance(evt, EventConnack) or evt.ret_code != 1:
            debug(evt)
            return False

        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            debug("invalid error code: {0}".format(ret))
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-3] CONNECT reserve flag MUST be set to zero")
    def test_104(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        ret = c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , NC.PROTOCOL_VERSION_3),
            ('byte'  , 1),   # flags - reserve set to 1
            ('uint16', 60),  # keepalive
            ('string', 'ff') # client id
        ], send=True)

        if ret != NC.ERR_CONN_LOST:
            debug("invalid error code: {0}".format(ret))
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-22] if username flag is not set, password flag must not be set")
    def test_105(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        ret = c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , NC.PROTOCOL_VERSION_4),
            ('byte'  , 1 << 6), # set password flag
            ('uint16', 60),     # keepalive
            ('string', 'ff')    # client id
        ], send=True)

        if ret != NC.ERR_CONN_LOST:
            debug("invalid error code: {0}".format(ret))
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-24] client is disconnected after expired KeepAlive (test 1)")
    def test_106(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , NC.PROTOCOL_VERSION_4),
            ('byte'  , 0),    # flags
            ('uint16', 2),    # keepalive
            ('string', 'ff')  # client id
        ], send=True)

        evt = c._c.pop_event()
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            debug(evt); return False

        time.sleep(3.5)
        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            debug("invalid error code: {0}".format(ret))
            return False

        return True

    @catch
    @desc("[MQTT-3.1.2-24] client is disconnected after expired KeepAlive (test 2)")
    def test_107(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , NC.PROTOCOL_VERSION_4),
            ('byte'  , 0),    # flags
            ('uint16', 2),   # keepalive
            ('string', 'ff')  # client id
        ], send=True)

        evt = c._c.pop_event()
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            debug(evt); return False

        time.sleep(1)
        evt = c.publish("foo", "bar", qos=1)
        if not isinstance(evt, EventPuback):
            debug(evt); return False

        time.sleep(3.5)
        ret = c._c.loop()
        if ret != NC.ERR_CONN_LOST:
            debug("invalid error code: {0}".format(ret))
            return False

        return True

    @catch
    @desc("[MQTT-3.1.3-7] 0-length clientid (w/ cleansession = 0)")
    def test_108(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
            return False

        c._c.sock = sock
        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , NC.PROTOCOL_VERSION_4),
            ('byte'  , 0),    # flags
            ('uint16', 10),   # keepalive
            ('string', '')    # client id
        ], send=True)

        evt = c._c.pop_event()
        if not isinstance(evt, EventConnack) or evt.ret_code != 2:
            debug(evt); return False

        return True

    @skip
    @catch
    @desc("[MQTT-3.1.3-5] > 23 characters clientid")
    def test_109(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
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

        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @skip
    @catch
    @desc("[MQTT-3.1.3-5] clientid invalid characters")
    def test_110(self):
        c = MqttClient("conformity:{seq}")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            sock.connect(('127.0.0.1', 1883))
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setblocking(0)
        except Exception as e:
            debug(e)
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

        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-2.2.2-1,MQTT-2.2.2-2] reserved flags")
    def test_112(self):
        ## PINGREG
        c = MqttClient("conformity:{seq}", raw_connect=True)
        evt = c.connect(version=4)

        # flags shoud be 0
        c.forge(NC.CMD_PINGREQ, 4, [], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        ## SUBSCRIBE
        c = MqttClient("conformity2:{seq}", raw_connect=True)
        evt = c.connect(version=4)

        # flags shoud be 2
        c.forge(NC.CMD_SUBSCRIBE, 3, [
            ('uint16', 42),         # identifier
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 0)           # qos
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] missing packet identifier (SUBSCRIBE)")
    def test_113(self):
        c = MqttClient("conformity:{seq}", raw_connect=True)
        evt = c.connect(version=4)

        c.forge(NC.CMD_SUBSCRIBE, 2, [
            #('uint16', 0),         # identifier not included
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 0)           # qos
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] non-zero packet identifier (SUBSCRIBE)")
    def test_114(self):
        c = MqttClient("conformity:{seq}", raw_connect=True)
        evt = c.connect(version=4)

        c.forge(NC.CMD_SUBSCRIBE, 2, [
            ('uint16', 0),         # identifier
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 0)           # qos
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] non-zero packet identifier (UNSUBSCRIBE)")
    def test_115(self):
        c = MqttClient("conformity:{seq}", raw_connect=True)
        evt = c.connect(version=4)

        c.forge(NC.CMD_UNSUBSCRIBE, 2, [
            ('uint16', 0),         # identifier
            ('string', '/foo/bar'), # topic filter
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-1] non-zero packet identifier (PUBLISH)")
    def test_116(self):
        c = MqttClient("conformity:{seq}", raw_connect=True)
        evt = c.connect(version=4)

        # qos 1
        c.forge(NC.CMD_PUBLISH, 2, [
            ('string', '/foo/bar'), # topic
            ('uint16', 0),         # identifier
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBACK pktid not matching PUBLISH pktid")
    def test_200(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

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
            debug(evt)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBREC pktid not matching PUBLISH pktid")
    def test_201(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

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
            debug(evt)
            return False

        evt = sub.recv()
        # PUBREL not received
        if evt is not None:
            debug(evt)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBREL pktid not matching PUBLISH pktid")
    def test_202(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

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
            debug(evt)
            return False

        evt = pub.recv()
        # publisher: PUBCOMP never received
        if evt is not None:
            debug(evt)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-2.3.1-6] PUBCOMP pktid not matching PUBLISH pktid")
    def test_203(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

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
            debug(evt)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    # this test is disabled currently, as the feature is not implemented yet in wave
    @skip
    @catch
    @desc("[MQTT-3.1.2-18] if CONNECT password flag is not set, no username must be present")
    def test_210(self):
        c = MqttClient("conformity:{seq}", raw_connect=True)

        c.forge(NC.CMD_CONNECT, 0, [
            ('string', 'MQTT'),
            ('byte'  , 4),         # protocol level
            #('byte'  , 128),       # connect flags:  username flag set
            ('byte'  , 0),       # no flags, no ClientId
            ('uint16', 60),        # keepalive
        ], send=True)

        return False


    @catch
    @desc("[MQTT-3.3.1-4] invalid PUBLISH qos value (3)")
    def test_211(self):
        c = MqttClient("conformity:{seq}", connect=4)

        c.forge(NC.CMD_PUBLISH, 6, [
            ('string', '/foo/bar'), # topic
            ('uint16', 0),          # identifier
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True


    @skip
    @catch
    @desc("[MQTT-3.3.2-1] no topic name in PUBLISH message")
    def test_212(self):
        c = MqttClient("conformity:{seq}", connect=4)

        # qos 1
        c.forge(NC.CMD_PUBLISH, 2, [], send=True)
#            ('uint16', 0),          # identifier
#        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-3.3.2-2] wildcard characters (+ and #) are forbidden in PUBLISH topic")
    def test_213(self):
        c = MqttClient("conformity:{seq}", connect=4)
        c.publish("foo/+/bar", "", qos=0)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        c = MqttClient("conformity:{seq}", connect=4)
        c.publish("foo/#/bar", "", qos=0)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-3.8.3-1] SUBSCRIBE MUST have at least one topic filter/qos")
    def test_214(self):
        c = MqttClient("conformity:{seq}", connect=4)

        c.forge(NC.CMD_SUBSCRIBE, 2, [
            ('uint16', 10),         # identifier
            # NOT TOPIC FILTER/QOS
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-3.8.3-4] SUBSCRIBE qos is 0,1 or 2")
    def test_215(self):
        c = MqttClient("conformity:{seq}", connect=4)
        c.forge(NC.CMD_SUBSCRIBE, 2, [
            ('uint16', 42),         # identifier
            ('string', '/foo/bar'), # topic filter
            ('byte'  , 3)           # qos
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-3.8.4-4, MQTT-3.8.4-5] SUBSCRIBE with multiple (>1) topicfilters, granted qoses returned in PUBACK resp")
    def test_216(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

        ack = sub.subscribe_multi([
            ("foo/bar", 2),
            ("bar/baz", 0),
            ("paper/+/scissor", 1)
        ])

        if not isinstance(ack, EventSuback) or ack.mid != sub.get_last_mid():
            debug(ack)
            return False

        # checking granted qos
        if len(ack.granted_qos) != 3 or \
                ack.granted_qos[0] != 2 or \
                ack.granted_qos[1] != 0 or \
                ack.granted_qos[2] != 1:
            debug(ack)
            return False

        return True

    @catch
    @desc("[MQTT-3.10.3-2] UNSUBSCRIBE MUST have at least one topic filter/qos")
    def test_220(self):
        c = MqttClient("conformity:{seq}", connect=4)

        c.forge(NC.CMD_UNSUBSCRIBE, 2, [
            ('uint16', 10),         # identifier
            # NOT TOPIC FILTER/QOS
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-3.10.4-5] UNSUBACK returned even without matching subscription")
    def test_221(self):
        c = MqttClient("conformity:{seq}", connect=4)
        ack = c.unsubscribe("foo/bar")
        if not isinstance(ack, EventUnsuback):
            debug(ack)
            return False

        return True

    @catch
    @desc("[MQTT-3.10.4-6] UNSUBSCRIBE with multiple (>1) topicfilters")
    def test_222(self):
        sub = MqttClient("conformity-sub:{seq}", connect=4)
        ack = sub.unsubscribe_multi(["foo/bar", "bar/baz", "paper/+/scissor"])

        if not isinstance(ack, EventUnsuback) or ack.mid != sub.get_last_mid():
            debug(ack)
            return False

        sub.disconnect()
        return True

    @catch
    @desc("[MQTT-3.14.4-2] Server close connection after Client DISCONNECT")
    def test_223(self):
        c = MqttClient("conformity-sub:{seq}", connect=4)
        c.disconnect()

        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT-3.10.4-2] broker MUST stop forwarding messages when topic filter is unsubscribed")
    def test_230(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

        sub.subscribe("foo/bar", qos=0)
        pub.publish("foo/bar", "grrr", qos=0)

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or evt.msg.payload != "grrr":
            debug(evt)
            return False

        sub.unsubscribe("foo/bar")
        pub.publish("foo/bar", "grrr bis", qos=0)

        evt = sub.recv()
        if evt is not None:
            debug(evt)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-3.10.4-4] broker MUST complete qos 1 messages AFTER topic filter has been unsubscribed")
    def test_231(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

        sub.subscribe("foo/bar", qos=1)
        pub.publish("foo/bar", "grrr", qos=1)

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or evt.msg.payload != "grrr":
            debug(evt)
            return False

        ack = sub.unsubscribe("foo/bar")
        if not isinstance(ack, EventUnsuback):
            debug(ack)
            return False

        sub.puback(evt.msg.mid)
        ack2 = pub.recv()
        if not isinstance(ack2, EventPuback):
            debug(ack2)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-3.10.4-4] broker MUST complete qos 2 messages AFTER topic filter has been unsubscribed")
    def test_232(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)
        sub = MqttClient("conformity-sub:{seq}", connect=4)

        sub.subscribe("foo/bar", qos=2)
        pub.publish("foo/bar", "grrr", qos=2)                # receive PUBREC as response
        pub.pubrel(pub.get_last_mid(), read_response=False) # triggers message delivery

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or evt.msg.payload != "grrr":
            debug(evt)
            return False

        ack = sub.unsubscribe("foo/bar")
        if not isinstance(ack, EventUnsuback):
            debug(ack)
            return False

        rel = sub.pubrec(evt.msg.mid)
        if not isinstance(rel, EventPubrel):
            debug(rel)
            return False

        sub.pubcomp(evt.msg.mid)
        comp = pub.recv()
        if not isinstance(comp, EventPubcomp):
            debug(comp)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-4.6.0-3] PUBREC is send in order of received PUBLISH")
    def test_240(self):
        pub = MqttClient("conformity-pub:{seq}", connect=4)

        pub.publish("foo/bar", "", qos=2, read_response=False); mid1 = pub.get_last_mid()
        pub.publish("bar/baz", "", qos=2, read_response=False); mid2 = pub.get_last_mid()

        evt = pub.recv()
        if not isinstance(evt, EventPubrec) or evt.mid != mid1:
            debug(evt)
            return False

        evt = pub.recv()
        if not isinstance(evt, EventPubrec) or evt.mid != mid2:
            debug(evt)
            return False

        pub.disconnect()
        return True

    @catch
    @desc("[MQTT-4.7.1-2] '#' wildcard MUST be last topic filter character")
    def test_250(self):
        tfs = [
            ("#"     , True),
            ("/#"    , True),
            ("/foo/#", True),
            ("#/foo" , False),
            ("/#/foo", False),
            ("/foo#" , False),
            ("/#foo" , False)
        ]

        for (tf, isvalid) in tfs:
            sub = MqttClient("conformity:{seq}", connect=4)
            sub.subscribe(tf, qos=0, read_response=False)
            ack = sub.recv()

            if (isvalid and not isinstance(ack, EventSuback)) or \
                    (not isvalid and (ack is not None or sub.conn_is_alive())):
                debug("{0}: {1} ({2})".format(tf, ack, sub.conn_is_alive()))
                return False

            sub.disconnect()

        return True

    @catch
    @desc("[MQTT-4.7.1-2] '+' wildcard MAY be at any topic filter level (MUST occupy all level then)")
    def test_251(self):
        tfs = [
            ("+"         , True),
            ("/+"        , True),
            ("+/"        , True),
            ("+/foo"     , True),
            ("/foo/+"    , True),
            ("/foo/+/"   , True),
            ("/foo/+/bar", True),
            ("+/foo/bar" , True),
            ("foo+"      , False),
            ("foo+/bar"  , False),
            ("+foo/bar"  , False),
            ("foo/+bar"  , False),
            # ~
            ("++"        , False),
            ("foo/++/bar", False),
        ]

        for (tf, isvalid) in tfs:
            sub = MqttClient("conformity:{seq}", connect=4)
            sub.subscribe(tf, qos=0, read_response=False)
            ack = sub.recv()

            if (isvalid and not isinstance(ack, EventSuback)) or \
                    (not isvalid and (ack is not None or sub.conn_is_alive())):
                debug("{0}: {1} ({2})".format(tf, ack, sub.conn_is_alive()))
                return False

            sub.disconnect()

        return True

    @catch
    @desc("[MQTT-4.7.2-1] topic started with '$' MUST NOT match # wildcard")
    def test_252(self):
        sub = MqttClient("conformity:{seq}", connect=4)
        sub.subscribe("#", qos=0)

        pub = MqttClient("pub:{seq}", connect=4)
        pub.publish("foo/bar", "test1")

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != 'foo/bar' or\
                evt.msg.payload != 'test1':
            debug(evt)
            return False

        pub.publish("$SYS/foo/bar", "test2")
        evt = sub.recv()
        if evt is not None:
            debug(evt)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-4.7.2-1] topic started with '$' MUST NOT match topic filter starting with +")
    def test_253(self):
        sub = MqttClient("conformity:{seq}", connect=4)
        sub.subscribe("+/bar", qos=0)

        pub = MqttClient("pub:{seq}", connect=4)
        pub.publish("foo/bar", "test1")

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != 'foo/bar' or\
                evt.msg.payload != 'test1':
            debug(evt)
            return False

        pub.publish("$SYS/bar", "test2")
        evt = sub.recv()
        if evt is not None:
            debug(evt)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-4.7.2-1] topic started with '$' match filters explicitely started with '$'")
    @defer.inlineCallbacks
    def test_254(self):
        yield app.set_metrics(enabled=True)
        sub = MqttClient("conformity:{seq}", connect=4)
        sub.subscribe("$SYS/broker/uptime", qos=0)

        # $SYS stats are published each 10 seconds by default
        time.sleep(12)

        retval = True
        evt = sub.recv()
        if not isinstance(evt, EventPublish) or\
                evt.msg.topic != '$SYS/broker/uptime':
            debug(evt)
            retval=False

        sub.disconnect()
        yield app.set_metrics(enabled=False)
        defer.returnValue(retval)

    @catch
    @desc("[MQTT-4.7.3-1] topics and topic filters MUST be 1-character long at least")
    def test_255(self):
        c = MqttClient("conformity:{seq}", connect=4)
        c.subscribe("", qos=0)

        if c.conn_is_alive():
            debug("connection still alive")
            return False

        c = MqttClient("conformity:{seq}", connect=4)
        c.unsubscribe("")

        if c.conn_is_alive():
            debug("connection still alive")
            return False

        c = MqttClient("conformity:{seq}", connect=4)
        c.publish("", "", qos=0)

        if c.conn_is_alive():
            debug("connection stil alive")
            return False

        return True

    @catch
    @desc("[MQTT-3.3.1-2] PUBLISH: DUP flag MUST be 0 if QOS = 0")
    def test_260(self):
        c = MqttClient("conformity:{seq}", connect=4)

        c.forge(NC.CMD_PUBLISH, 8, [
            ('string', '/foo/bar'), # topic
            ('uint16', 10),         # identifier
        ], send=True)
        if c.conn_is_alive():
            debug("connection still alive")
            return False

        return True

    @catch
    @desc("[MQTT_4.3.2-2] QOS 1, DUP flag: after PUBACK, PUBLISH with same packet id is a new publication")
    def test_261(self):
        pub = MqttClient("conformity:{seq}", connect=4)
        sub = MqttClient("test:{seq}", connect=4)
        sub.subscribe("/foo/bar", qos=0)

        pub.forge(NC.CMD_PUBLISH, 2, [
            ('string', '/foo/bar'), # topic
            ('uint16', 42),         # identifier
        ], send=True)

        ack = pub.recv()
        if not isinstance(ack, EventPuback):
            debug(ack)
            return False

        # ensure message has been delivered
        evt = sub.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != '/foo/bar':
            debug(evt)
            return False

        # sending again same packet (same id) with dup=1
        pub.forge(NC.CMD_PUBLISH, 10, [
            ('string', '/foo/bar'), # topic
            ('uint16', 42),         # identifier
        ], send=True)

        ack = pub.recv()
        if not isinstance(ack, EventPuback):
            debug(ack)
            return False

        # ensure message has been delivered
        evt = sub.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != '/foo/bar':
            debug(evt)
            return False

        return True

    @catch
    @desc("[MQTT-4.3.2-2] QOS 1, DUP flag: while PUBACK not delivered, a PUBLISH with same packed it is ignored")
    def test_262(self):
        pub = MqttClient("conformity:{seq}", connect=4)
        sub = MqttClient("test:{seq}", connect=4)
        sub.subscribe("/foo/bar", qos=1)

        pub.forge(NC.CMD_PUBLISH, 2, [
            ('string', '/foo/bar'), # topic
            ('uint16', 42),         # identifier
        ], send=True)

        ack = pub.recv()
        if ack is not None:
            debug(ack)
            return False

        evt = sub.recv()
        if not isinstance(evt, EventPublish) or evt.msg.topic != '/foo/bar':
            debug(evt)
            return False

        ## reemit message with dup=1 (same msgid)
        ## message must be discarded as previous on is still inflight
        pub.forge(NC.CMD_PUBLISH, 2, [
            ('string', '/foo/bar'), # topic
            ('uint16', 42),         # identifier
        ], send=True)

        ack = pub.recv()
        if ack is not None:
            debug(ack)
            return False

        evt = sub.recv()
        if evt is not None:
            debug(evt)
            return False

        return True

    @catch
    @desc("PUBLISH to '$...' topic is forbidden")
    def test_270(self):
        pub = MqttClient("luser:{seq}", connect=4)
        pub.publish("$foo/bar", "test1")

        if pub.conn_is_alive():
            debug("connection still alive")
            return False

        return True

