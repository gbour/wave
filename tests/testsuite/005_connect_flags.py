# -*- coding: UTF8 -*-

#TODO:
#   - test unattended disconnections (broken socket)
#   - test qos 1 & 2 messages
#   - test subscribe return

import random

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from lib.env import gen_msg, debug

class ConnectFlags(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "CONNECT flags")


    def pubsub(self, (pub, ctrl, dummy), clbs={}):
        msg = gen_msg(10)
        ## no response expected
        pub.do("publish", "/test/qos/0", msg)

        ## checking we received message for both control-sample & dummy clients
        evt = ctrl.recv()
        if evt.msg.payload != msg:
            return False

        evt = dummy.recv()
        #print evt, checkfn(evt, msg)

        def nop(*args, **kwargs):
            return True
        return clbs.get('checkrecv', nop)(evt, msg)


    @catch
    @desc("CONNECT flag - clean session :: set")
    def test_001(self):
        pub = MqttClient("publisher:{seq}")
        evt = pub.connect()
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            debug(evt)
            return False

        ctrl = MqttClient("control-sample:{seq}")
        evt = ctrl.connect()
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            debug(evt)
            return False

        evt = ctrl.subscribe("/test/qos/0", qos=0)
        if not isinstance(evt, EventSuback):
            debug(evt)
            return False


        ###
        dummyid = "dummy:{0}".format(random.randint(0,9999))
        dummy = MqttClient(dummyid)
        evt = dummy.connect(clean_session=1)
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            debug(evt)
            return False
        evt = dummy.subscribe("/test/qos/0", qos=0)
        if not isinstance(evt, EventSuback):
            debug(evt)
            return False
        #print evt.mid


        # 1. sent qos0, 1, 2 messages; check reception
        if not self.pubsub((pub, ctrl, dummy), clbs={
                    'checkrecv': lambda evt, msg: evt is not None and evt.msg.payload == msg
                }):
            return False

        # 2. disconnecting (properly) dummmy; then reconnects
        dummy.disconnect(); del(dummy)

        ## publish message
        msg = gen_msg(10)
        pub.publish("/test/qos/0", payload=msg)


        ## reconnects, without explicitly subscribing topic
        dummy = MqttClient(dummyid)
        evt = dummy.connect(clean_session=1)
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False


        ## checking message is not received by dummy
        evt = ctrl.recv()
        if evt.msg.payload != msg:
            return False

        evt = dummy.recv()
        if evt != None:
            return False

        ## dummy resubscribe, check we receive messages
        evt = dummy.subscribe("/test/qos/0", qos=0)
        if not isinstance(evt, EventSuback):
            return False

        ## send test message
        if not self.pubsub((pub, ctrl, dummy), clbs={
                    'checkrecv': lambda evt, msg: evt is not None and evt.msg.payload == msg
                }):
            debug('pubsub failed')
            return False


        # cleanup
        pub.disconnect()
        ctrl.disconnect()
        dummy.disconnect()

        return True

    @catch
    @desc("CONNECT flag - clean session :: unset")
    def test_002(self):
        pub = MqttClient("publisher:{seq}")
        evt = pub.connect()
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        ctrl = MqttClient("control-sample:{seq}")
        evt = ctrl.connect()
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False

        evt = ctrl.subscribe("/test/qos/0", qos=0)
        if not isinstance(evt, EventSuback):
            return False


        ###
        dummyid = "dummy:{0}".format(random.randint(0,9999))
        dummy = MqttClient(dummyid)
        evt = dummy.connect(clean_session=0)
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False
        evt = dummy.subscribe("/test/qos/0", qos=0)
        if not isinstance(evt, EventSuback):
            return False
        #print evt.mid


        # 1. sent qos0, 1, 2 messages; check reception
        if not self.pubsub((pub, ctrl, dummy), clbs={
                    'checkrecv': lambda evt, msg: evt is not None and evt.msg.payload == msg
                }):
            return False

        # 2. disconnecting (properly) dummmy; then reconnects
        dummy.disconnect(); del(dummy)

        ## publish message
        msg = gen_msg(10)
        pub.publish("/test/qos/0", payload=msg)


        ## reconnects, without explicitly subscribing topic
        dummy = MqttClient(dummyid)
        evt = dummy.connect(clean_session=0)
        if not isinstance(evt, EventConnack) or evt.ret_code != 0:
            return False


        ## checking message is not received by dummy
        evt = ctrl.recv()
        if evt.msg.payload != msg:
            return False

        evt = dummy.recv()
        if evt != None:
            return False

        ## dummy resubscribe, check we receive messages
        #evt = dummy.do("subscribe", "/test/qos/0", 0)
        #if not isinstance(evt, EventSuback):
        #    return False

        ## send test message
        if not self.pubsub((pub, ctrl, dummy), clbs={
                    'checkrecv': lambda evt, msg: evt is not None and evt.msg.payload == msg
                }):
            return False

        # cleanup
        pub.disconnect()
        ctrl.disconnect()
        dummy.unsubscribe("/test/qos/0")
        dummy.disconnect()

        return True

