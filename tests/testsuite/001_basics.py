# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

class Basic(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "basic tests")


    @catch
    @desc("CONNECT")
    def test_001(self):
        c = MqttClient("reg:{seq}")
        evt = c.connect()

        # [MQTT-3.1.4-4]: CONNACK retcode MUST be 0
        # [MQTT-3.2.2-3]: CONNACK session_present IS 0
        if not isinstance(evt, EventConnack) or \
                evt.ret_code != 0 or \
                evt.session_present != 0:
            return False

        return True

    #TODO: we must hook disconnect method such as we send DISCONNECT message but don't close the socket
    #      then we check server has closed the socket
    @catch
    @desc("DISCONNECT")
    def test_002(self):
        c = MqttClient("reg:{seq}", connect=4)
        #evt = c._c.disconnect()
        c.disconnect()

        return True

    @catch
    @desc("SUBSCRIBE/UNSUBSCRIBE")
    def test_010(self):
        c = MqttClient("reg:{seq}", connect=4)

        evt = c.subscribe("/foo/bar", qos=0)
        # validating [MQTT-2.3.1-7]
        if not isinstance(evt, EventSuback) or evt.mid != c.get_last_mid():
            return False

        evt = c.unsubscribe("/foo/bar")
        # validating [MQTT-2.3.1-7]
        if not isinstance(evt, EventUnsuback) or evt.mid != c.get_last_mid():
            return False

        c.disconnect()
        return True

    @catch
    @desc("PUBLISH (qos=0). no response")
    def test_011(self):
        c = MqttClient("reg:{seq}", connect=4)
        e = c.publish("/foo/bar", "plop")
        # QOS = 0 : no response indented
        c.disconnect()

        return (e is None)

    @catch
    @desc("PING REQ/RESP")
    def test_020(self):
        c = MqttClient("reg:{seq}", connect=4)
        e = c.send_pingreq()
        c.disconnect()

        return isinstance(e, EventPingResp)

