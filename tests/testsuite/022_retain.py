# -*- coding: UTF8 -*-

import time
import socket

from lib import env
from lib.env import debug
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt


class Retain(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "Retained messages")

    @catch
    @desc("[MQTT-3.3.1-5,MQTT-3.3.1-7] retain published message (qos 0)")
    def test_001(self):
        c = MqttClient("conformity", connect=4)

        c.publish("/foo/bar/0", "plop", qos=0, retain=True)
        c.disconnect()

        # checking message as been store in db
        store = env.db.hgetall('retain:/foo/bar/0')
        if not (store.get('data') == 'plop' and store.get('qos') == '0'):
            debug(store)
            return False

        return True

    @catch
    @desc("[MQTT-3.3.1-5] retain published message (qos 1)")
    def test_002(self):
        c = MqttClient("conformity", connect=4)
        c.publish("/foo/bar/1", "plop", qos=1, retain=True)
        c.disconnect()

        # checking message as been store in db
        store = env.db.hgetall('retain:/foo/bar/1')
        if store.get('data') != 'plop' or store.get('qos') != '1':
            debug(store)
            return False

        return True

    @catch
    @desc("[MQTT-3.3.1-5] retain published message (qos 2)")
    def test_003(self):
        c = MqttClient("conformity", connect=4)
        c.publish("/foo/bar/2", "plop", qos=2, retain=True)
        c.disconnect()

        # checking message as been store in db
        store = env.db.hgetall('retain:/foo/bar/2')
        if store.get('data') != 'plop' or store.get('qos') != '2':
            debug(store)
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
            debug(store)
            return False

        # deleting message
        c.publish("/retain/delete", '', retain=True)
        retain = env.db.keys('retain:/retain/delete')
        if retain != []:
            debug("retain= {0}".format(retain))
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
            debug(env.db.keys('retain:/retain/no/*'))
            return False

        # not stored
        c.publish('/retain/no/1', 'whaa', retain=False)
        if env.db.keys('retain:/retain/no/*') != ['retain:/retain/no/2']:
            debug(env.db.keys('retain:/retain/no/*'))
            return False

        # no replace or remove
        c.publish('/retain/no/2', 'whaa', retain=False)
        store = env.db.hgetall("retain:/retain/no/2")
        if store != {'data': 'waze', 'qos': '0'}:
            debug(store)
            return False

        c.disconnect()
        return True

    @catch
    @desc("[MQTT-3.3.1-9,MQTT-3.3.1-10] PUBLISH w/ retain is deliverd as normal msg (qos 0)")
    def test_012(self):
        pub = MqttClient("conformity", connect=4)
        sub = MqttClient("sub", connect=4)
        sub.subscribe("/retain/+", qos=0)

        pub.publish("/retain/delivered", 'waze', retain=True)
        msg = sub.recv()
        if not isinstance(msg, EventPublish) or \
                msg.msg.topic != '/retain/delivered' or \
                msg.msg.payload != 'waze' or\
                msg.msg.retain:
            debug(msg)
            return False

        # same with empty payload
        pub.publish("/retain/empty", '', retain=True)
        msg = sub.recv()
        if not isinstance(msg, EventPublish) or \
                msg.msg.topic != '/retain/empty' or \
                msg.msg.payload != None or\
                msg.msg.retain:
            debug(msg)
            return False

        pub.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-3.3.1-9,MQTT-3.3.1-10] PUBLISH w/ retain is delivered as normal msg (qos 1,2)")
    def test_013(self):
        pub = MqttClient("conformity", connect=4)
        sub = MqttClient("sub", connect=4)
        sub.subscribe("/test/022/013/+", qos=2)

        pub.publish("/test/022/013/t1", 'hurry', retain=True, qos=1)
        msg = sub.recv()
        if not isinstance(msg, EventPublish) or \
                msg.msg.topic != '/test/022/013/t1' or \
                msg.msg.payload != 'hurry' or\
                msg.msg.qos != 1 or\
                msg.msg.retain:
            debug(msg)
            return False

        # same with empty payload
        pub.publish("/test/022/013/t2", 'up', retain=True, qos=2)
        pub.pubrel(pub.get_last_mid())

        msg = sub.recv()
        if not isinstance(msg, EventPublish) or \
                msg.msg.topic != '/test/022/013/t2' or \
                msg.msg.payload != "up" or\
                msg.msg.qos != 2 or\
                msg.msg.retain:
            debug(msg)
            return False

        return True

    @catch
    @desc("[MQTT-3.3.1-6,MQTT-3.3.1-8] publication of retained message - topic exact match")
    def test_020(self):
        retain = MqttClient("retain", connect=4)
        sub    = MqttClient("subscriber", connect=4)

        topic = "/woot/wo/ot"; msg = "expression of simplistic ecstasy"
        retain.publish(topic, msg, retain=True)

        # exact match topic
        sub.subscribe("/woot/wo/ot", qos=0, read_response=False)
        while True:
            evt = sub.recv()
            if isinstance(evt, EventSuback):
                acked = True; continue

            # receiving retained message
            if isinstance(evt, EventPublish) and\
                    evt.msg.topic   == topic and\
                    evt.msg.payload == msg   and\
                    evt.msg.retain:
                pubevt = evt; continue

            break

        if not acked:
            debug("not acked")
            return False
        if pubevt is None:
            debug("message not received")
            return False

        return True

    @catch
    @desc("[MQTT-3.3.1-6,MQTT-3.3.1-8] publication of retained message - topic match w/ '+' wildcard")
    def test_021(self):
        retain = MqttClient("retain", connect=4)
        sub    = MqttClient("subscriber", connect=4)

        topic = "/woot/wo/ot"; msg = "expression of simplistic ecstasy"
        retain.publish(topic, msg, retain=True)

        # wildcard match topic
        sub.subscribe("/woot/+/ot", qos=0, read_response=False)

        acked = False; pubevt = None
        while True:
            evt = sub.recv()
            if isinstance(evt, EventSuback):
                acked = True; continue

            # receiving retained message
            if isinstance(evt, EventPublish) and\
                    evt.msg.topic   == topic and\
                    evt.msg.payload == msg   and\
                    evt.msg.retain:
                pubevt = evt; continue

            break

        if not acked:
            debug("not acked")
            return False
        if pubevt is None:
            debug("message not received")
            return False

        # MUST NOT match
        topic = "/scri/b/b/le"; msg = "hundrerd dollar bill"
        retain.publish(topic, msg, retain=True)

        sub.subscribe("/scri/*/le", qos=0)
        evt = sub.recv()
        if evt is not None:
            debug(evt)
            return False

        return True

    @catch
    @desc("[MTT-3.3.1-6,MQTT-3.3.1-8] publication of retained message - topic match w/ '#' wildcard")
    def test_022(self):
        retain = MqttClient("retain", connect=4)
        sub    = MqttClient("subscriber", connect=4)

        topic = "/woot/wo/ot"; msg = "expression of simplistic ecstasy"
        retain.publish(topic, msg, retain=True)

        # wildcard match topic
        sub.subscribe("/woot/#", qos=0, read_response=False)
        acked = False; pubevt = None
        while True:
            evt = sub.recv()
            if isinstance(evt, EventSuback):
                acked = True; continue

            # receiving retained message
            if isinstance(evt, EventPublish) and\
                    evt.msg.topic   == topic and\
                    evt.msg.payload == msg   and\
                    evt.msg.retain:
                pubevt = evt; continue

            break

        if not acked:
            debug("not acked")
            return False
        if pubevt is None:
            debug("message not received")
            return False

        retain.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-3.3.1-6] retain: multiple messages delivered")
    def test_023(self):
        retain = MqttClient("retain", connect=4)
        sub    = MqttClient("subscr", connect=4)

        # matching topics
        rs = {
            # match
            "dead/bea/t k/id/s": {
                'topic' : "dead/bea/t k/id/s",
                'payload': "children that just aren't worth supporting",
                'retain' : True},
            # match
            "dead/abe/t k/id/s": {
                'topic'  : "dead/abe/t k/id/s",
                'payload': "just children that aren't supporting worth",
                'retain' : True},
            }
        for args in rs.values():
            retain.publish(**args)

            # no match
        nors = {'topic': "dead/be/a/t k/ids", 'payload': "children that just aren't worth supporting",
                'retain': True}
        retain.publish(**nors)

        #NOTE: we must receive BOTH rs message, but NOT nors one
        #NOTE: PUBLISH messages MAY arrived BEFORE PUBACK
        sub.subscribe("dead/+/t k/#", qos=0, read_response=False)
        count = 0
        while True:
            evt = sub.recv()
            if evt is None:
                break
            if isinstance(evt, EventSuback):
                continue

            if not isinstance(evt, EventPublish) or\
                    not evt.msg.retain or\
                    evt.msg.topic not in rs:
                debug(evt)
                return False

            count += 1

        if count != len(rs):
            debug("not received enough messages")
            return False

        retain.disconnect(); sub.disconnect()
        return True

    @catch
    @desc("[MQTT-3.3.1-6] retain: qos 1 delivery")
    def test_030(self):
        retain = MqttClient("retain", connect=4)
        sub    = MqttClient("subscr", connect=4)

        msg = {'topic': "baby/ma/ma", 'payload': "The mother of your child(ren)", 'retain': True,
                'qos': 1}
        retain.publish(**msg)

        sub.subscribe("baby/ma/+", qos=1, read_response=False)

        pubevt = None
        while True:
            evt = sub.recv()
            if isinstance(evt, EventSuback): continue
            if isinstance(evt, EventPublish) and\
                    evt.msg.qos == 1 and\
                    evt.msg.retain and\
                    evt.msg.topic == msg['topic'] and\
                    evt.msg.payload == msg['payload']:
                pubevt = evt; continue

            break

        if pubevt is None:
            debug("message not received")
            return False
        sub.puback(mid=pubevt.msg.mid)

        retain.disconnect(); sub.disconnect()
        return True

    #TODO: qos 2 delivery
    #TODO: qos degradation (msg qos < subscriber qos)

