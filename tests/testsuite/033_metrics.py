# -*- coding: utf8 -*-

import time
import redis
import socket
from   pprint import pprint

from lib import env
from lib.env import debug
from lib.erl import application as app, exometer
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

from twisted.internet import defer


def sys_value(client, topic, casttype):
    while True:
        evt = client.recv()
        if isinstance(evt, EventPublish) and evt.msg.topic == topic:
            return casttype(evt.msg.payload)

class Metrics(TestSuite):
    """
        NOTE: EXPECTING update interval to be 1 sec or lower
    """
    def __init__(self):
        TestSuite.__init__(self, "Metrics")

    @defer.inlineCallbacks
    def setup_suite(self):
        super(Metrics, self).setup_suite()
        yield exometer.interval(delay=1000)
        yield app.set_metrics(enabled=True)

    @defer.inlineCallbacks
    def cleanup_suite(self):
        super(Metrics, self).cleanup_suite()
        yield exometer.interval(delay=3600000)
        yield app.set_metrics(enabled=False)


    @catch
    @desc("statsd exometer reporter is enabled")
    @defer.inlineCallbacks
    def test_001(self):
        """
            > exometer_report:list_reporters().
            [{exometer_report_statsd,<0.143.0>}]
        """
        reporters = yield exometer.reporters()
        if 'exometer_report_statsd' not in reporters:
            debug(reporters); defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("subscribed metrics")
    @defer.inlineCallbacks
    def test_002(self):
        """
            > exometer_report:list_subscriptions('exometer_report_statsd')
        """
        metrics = {
            'erlang.memory': ('ets','processes','total'),
            'erlang.system_info': ('port_count', 'process_count', 'thread_pool_size'),
            'erlang.io'         : ('input', 'output'),
            'erlang.statistics' : ('run_queue',),
            'wave.sessions'     : ('active', 'offline'),
            'wave.connections.tcp' : ('count','one'),
            'wave.connections.ssl' : ('count','one'),
            'wave.connections.ws'  : ('count','one'),
            'wave.packets.received': ('count','one'),
            'wave.packets.sent'    : ('count','one'),
            'wave.messages.in.0'   : ('count','one'),
            'wave.messages.in.1'   : ('count','one'),
            'wave.messages.in.2'   : ('count','one'),
            'wave.messages.out.0'  : ('count','one'),
            'wave.messages.out.1'  : ('count','one'),
            'wave.messages.out.2'  : ('count','one'),

            'wave.messages'        : ('retained', 'stored'),
            'wave.subscriptions'   : ('ms_since_reset', 'value'),
            'wave.messages.inflight': ('ms_since_reset', 'value'),
            'wave'                  : ('uptime',),
        }

        subscriptions = yield exometer.subscriptions('exometer_report_statsd')
        #print subscriptions
        for name, datapoints in subscriptions.iteritems():
            if name in metrics:
                if list(metrics[name]) != sorted(datapoints):
                    debug("not matching: {0}, {1}".format(name, datapoints))
                    defer.returnValue(False)

                del metrics[name]
            else:
                debug("extra metric: {0}, {1}".format(name, datapoints))

        if len(metrics) > 0:
            debug("missing metrics: {0}".format(metrics))
            defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("metrics: wave.sessions")
    @defer.inlineCallbacks
    def test_010(self):
        """
            > exometer:get_value([wave,sessions]).
            {ok,[{active,0},{offline,0}]}
        """
        v_start = yield exometer.value('wave.sessions')

        c = MqttClient("metrics:{seq}", connect=4, clean_session=0)
        v = yield exometer.value('wave.sessions')
        if v['active'] != v_start['active']+1 or v['offline'] != v_start['offline']:
            debug("{0}, {1}".format(v, v_start))
            defer.returnValue(False)

        c.disconnect()
        time.sleep(.5)
        v = yield exometer.value('wave.sessions')
        if v['active'] != v_start['active'] or v['offline'] != v_start['offline']+1:
            debug("{0}, {1}".format(v, v_start))
            defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("metrics: wave.messages.in")
    @defer.inlineCallbacks
    def test_011(self):
        """
        """
        @defer.inlineCallbacks
        def _(qos):
            v_start = yield exometer.value('wave.messages.in.'+str(qos))

            c = MqttClient("metrics:{seq}", connect=4)
            c.publish("foo/bar", "", qos=qos)
            c.disconnect()

            v_end = yield exometer.value('wave.messages.in.'+str(qos))
            if v_end['count'] - v_start['count'] != 1:
                debug("{0}, {1}".format(v_end, v_start))
                defer.returnValue(False)

            defer.returnValue(True)

        for qos in xrange(0,3):
            if not (yield _(qos)):
                defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("metrics: wave.subscriptions")
    @defer.inlineCallbacks
    def test_012(self):
        """
        """
        v = yield exometer.value('wave.subscriptions')
        ref_val = v['value']

        c = MqttClient("metrics:{seq}", connect=4)
        c.subscribe('foo/bar', qos=0)

        v = yield exometer.value('wave.subscriptions')
        if v['value'] != ref_val+1:
            debug("{0}, {1}".format(v, ref_val))
            defer.returnValue(False)

        c.unsubscribe('foo/bar')
        v = yield exometer.value('wave.subscriptions')
        if v['value'] != ref_val:
            debug("{0}, {1}".format(v, ref_val))
            defer.returnValue(False)

        c.disconnect()
        defer.returnValue(True)

    @catch
    @desc("$SYS hierarchy: listing metrics")
    def test_020(self):
        metrics = [
            '$SYS/broker/uptime',
            '$SYS/broker/version',
            '$SYS/broker/clients/total',
            '$SYS/broker/clients/connected',
            '$SYS/broker/clients/disconnected',
            '$SYS/broker/messages/sent',
            '$SYS/broker/messages/received',
            '$SYS/broker/messages/inflight',
            '$SYS/broker/messages/stored',
            '$SYS/broker/publish/messages/sent',
            '$SYS/broker/publish/messages/sent/qos 0',
            '$SYS/broker/publish/messages/sent/qos 1',
            '$SYS/broker/publish/messages/sent/qos 2',
            '$SYS/broker/publish/messages/received',
            '$SYS/broker/publish/messages/received/qos 0',
            '$SYS/broker/publish/messages/received/qos 1',
            '$SYS/broker/publish/messages/received/qos 2',
            '$SYS/broker/retained messages/count',
            '$SYS/broker/subscriptions/count',
        ]

        c = MqttClient("metrics:{seq}", connect=4)
        c.subscribe('$SYS/#', qos=0)

        while True:
            evt = c.recv()
            if evt is not None and isinstance(evt, EventPublish):
                break

        stats = {evt.msg.topic: evt.msg.payload}
        while True:
            evt = c.recv()
            if evt is None: break
            if isinstance(evt, EventPingResp): continue

            stats[evt.msg.topic] = evt.msg.payload

        #pprint(stats)
        for topic in metrics:
            if topic not in stats:
                debug("{0} metric not in $SYS".format(topic))
                return False

            del stats[topic]

        if len(stats) > 0:
            debug("extra $SYS metrics: {0}".format(stats))

        c.disconnect()
        return True

    @catch
    @desc("$SYS hierarchy: PUBLISH received counter")
    def test_021(self):
        c = MqttClient("metrics:{seq}", connect=4)
        d = MqttClient("duck:{seq}", connect=3)
        c.subscribe('$SYS/#', qos=0)

        pubs_start = sys_value(c, "$SYS/broker/publish/messages/received", int)
        d.publish("foo/bar", "")
        pubs_end = sys_value(c, "$SYS/broker/publish/messages/received", int)

        if pubs_end != pubs_start+1:
            debug("{0}, {1}".format(pubs_start, pubs_end))
            return False

        c.disconnect()
        return True
