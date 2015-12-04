#!/usr/bin/env python
# -*- coding: UTF8 -*-

#
# $SYS events, generated internally
#
#
#

import types

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

class Qos1(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "system events")

    def newclient(self, name="req"):
        c = MqttClient(name)
        c.do("connect")

        return c

    #NOTE: currently all internal events are sent with qos=0
    @catch
    @desc("event: $/mqtt/connect")
    def test_001(self):
        topic = "$/mqtt/CONNECT"
        qos   = [0, 1, 2]
        subs = []

        for i in range(len(qos)):
            subs.append(self.newclient("sub{0}".format(qos[i])))

        for i in range(len(qos)):
            subs[i].subscribe(topic, qos[i])

        pub = self.newclient('pub')

        # qos 0 client
        for i in range(len(qos)):
            print "qos {0}: receiving message".format(qos[i])
            e = subs[i].recv()

            if not isinstance(e, EventPublish):
                print "qos {0}: message received should be EventPublish (is {1})".format(qos[i], e)
                return False

            if e.msg.topic != topic or\
                    e.msg.qos != 0: #qos[i]:
                print "qos {0}: invalid packet received (topic= {1}, qos={2})".format(qos[i], e.msg.topic,\
                                                                                      e.msg.qos)
                return False

            #FUTURE: internal events supporting qos > 0
#            if e.msg.qos == 1:
#                subs[i].puback(e.msg.mid)
#            elif e.msg.qos == 2:
#                e2 = subs[i].pubrec(e.msg.mid)
#                if not isinstance(e2, EventPubrel) or e2.mid != e.msg.mid:
#                    print "qos2 PUBREC response: {0} (should be EventPubrel)".format(e2)
#                    return False
#
#                subs[i].pubcomp(e.msg.mid)

        #TODO: check subs connectivity
        return True
