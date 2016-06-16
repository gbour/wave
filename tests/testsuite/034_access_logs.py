#!/usr/bin/env python
# -*- coding: UTF8 -*-

from lib import env
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

import os
import time
import socket
from pprint import pprint

import apache_log_parser

APACHE_COMBINED="%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\""
parser = apache_log_parser.make_parser(APACHE_COMBINED)

def _match(f, conds):
    time.sleep(.5)
    try:
        line = parser(f.readline())
        #pprint(line)
        for k, v in conds.iteritems():
            if line[k] != v:
                print '  {0} not matching {1} (is {2})'.format(k, v, line[k])
                return False

    except Exception, e:
        print e
        return False

    return True


class AccessLog(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "AccessLog")

    @catch
    @desc("CONNECT, DISCONNECT")
    def test_001(self):
        f = open('../log/wave.access.log', 'r')
        f.seek(0, os.SEEK_END)

        # here we start
        c = MqttClient("conformity", connect=4)
        c.disconnect()

        if not _match(f, 
                {'request_method': 'CONNECT', 'status': '200', 'request_header_user_agent': c.client_id}):
            return False

        if not _match(f, 
                {'request_method': 'DISCONNECT', 'status': '200', 'request_header_user_agent': c.client_id}):
            return False


        return True

    @catch
    @desc("SUBSCRIBE, UNSUBSCRIBE")
    def test_002(self):
        f = open('../log/wave.access.log', 'r')
        f.seek(0, os.SEEK_END)

        # here we start
        c = MqttClient("conformity", connect=4)
        c.subscribe("foo/bar", qos=1)
        c.unsubscribe("foo/bar")
        c.disconnect()

        f.readline() # skip CONNECT
        if not _match(f, {'request_method': 'SUBSCRIBE', 'request_url': 'foo/bar', 
                          'status': '200', 'request_header_user_agent': c.client_id}):
            return False
        if not _match(f, {'request_method': 'UNSUBSCRIBE', 'request_url': 'foo/bar', 
                          'status': '200', 'request_header_user_agent': c.client_id}):
            return False

        return True

    @catch
    @desc("PUBLISH")
    def test_003(self):
        f = open('../log/wave.access.log', 'r')
        f.seek(0, os.SEEK_END)

        # here we start
        c = MqttClient("conformity", connect=4)
        c.publish("foo/bar", "baz", qos=1)
        c.disconnect()

        f.readline() # skip CONNECT
        if not _match(f, {'request_method': 'PUBLISH', 'request_url': 'foo/bar', 'response_bytes_clf': '3',
                          'status': '200', 'request_header_user_agent': c.client_id}):
            return False

        return True

