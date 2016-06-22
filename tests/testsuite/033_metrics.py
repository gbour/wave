#!/usr/bin/env python
# -*- coding: utf8 -*-

import time
import redis
import socket
from   pprint import pprint

from lib import env
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

from twisted.internet import defer
import twotp
from twotp import Atom

@defer.inlineCallbacks
def exo_value(key):
    def _encode(x):
        try:
            x = int(x)
        except:
            x = Atom(x)

        return x

    key = [_encode(x) for x in key.split('.')]

    sessions = yield env.remote('exometer','get_value', key)
    defer.returnValue(dict(twotp.to_python(sessions)[1]))

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


    @catch
    @desc("statsd exometer reporter is enabled")
    @defer.inlineCallbacks
    def test_001(self):
        """
            > exometer_report:list_reporters().
            [{exometer_report_statsd,<0.143.0>}]
        """
        reporters = yield env.remote('exometer_report', 'list_reporters')
        try:
            if twotp.to_python(reporters[0][0]) != 'exometer_report_statsd':
                defer.returnValue(False)
        except Exception:
            defer.returnValue(False)

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

        subscriptions = yield env.remote('exometer_report', 'list_subscriptions',
                                         twotp.Atom('exometer_report_statsd'))
        #pprint(twotp.to_python(subscriptions))
        for (name, datapoints, delay, args) in twotp.to_python(subscriptions):
            name = '.'.join([str(x) for x in name])

            #print name, list(metrics.get(name, [])) == sorted(datapoints)
            if name in metrics:
                if list(metrics[name]) != sorted(datapoints):
                    print '  . not matching:', name, datapoints
                    defer.returnValue(False)

                del metrics[name]
            else:
                print "  . extra metric:", name, datapoints

        if len(metrics) > 0:
            print "  . missing metrics:", metrics
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
        v_start = yield exo_value('wave.sessions')

        c = MqttClient("metrics", connect=4, clean_session=0)
        v = yield exo_value('wave.sessions')
        if v['active'] != v_start['active']+1 or v['offline'] != v_start['offline']:
            print '  . 1:', v
            defer.returnValue(False)

        c.disconnect()
        time.sleep(.5)
        v = yield exo_value('wave.sessions')
        if v['active'] != v_start['active'] or v['offline'] != v_start['offline']+1:
            print '  . 2:', v
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
            v_start = yield exo_value('wave.messages.in.'+str(qos))

            c = MqttClient("metrics", connect=4)
            c.publish("foo/bar", "", qos=qos)
            c.disconnect()

            v_end = yield exo_value('wave.messages.in.'+str(qos))
            if v_end['count'] - v_start['count'] != 1:
                print '  . qos=',qos,'start:', v_start, ', end:', v_end
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
        v = yield exo_value('wave.subscriptions')
        if v['value'] != 0:
            print '  . 1:', v
            defer.returnValue(False)

        c = MqttClient("metrics", connect=4)
        c.subscribe('foo/bar', qos=0)

        v = yield exo_value('wave.subscriptions')
        if v['value'] != 1:
            print '  . 2:', v
            defer.returnValue(False)

        c.unsubscribe('foo/bar')
        v = yield exo_value('wave.subscriptions')
        if v['value'] != 0:
            print '  . 3:', v
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

        c = MqttClient("metrics", connect=4)
        c.subscribe('$SYS/#', qos=0)

        while True:
            evt = c.recv()
            if evt is not None: break

        stats = {evt.msg.topic: evt.msg.payload}
        while True:
            evt = c.recv()
            if evt is None: break

            stats[evt.msg.topic] = evt.msg.payload

        #pprint(stats)
        for topic in metrics:
            if topic not in stats:
                print '  {0} metric not in $SYS'.format(topic)
                return False

            del stats[topic]

        if len(stats) > 0:
            print 'extra $SYS metrics:', stats

        c.disconnect()
        return True

    @catch
    @desc("$SYS hierarchy: PUBLISH received counter")
    def test_021(self):
        c = MqttClient("metrics", connect=4)
        d = MqttClient("duck", connect=3)
        c.subscribe('$SYS/#', qos=0)

        pubs_start = sys_value(c, "$SYS/broker/publish/messages/received", int)
        d.publish("foo/bar", "")
        pubs_end = sys_value(c, "$SYS/broker/publish/messages/received", int)

        if pubs_end != pubs_start+1:
            return False

        c.disconnect()
        return True
