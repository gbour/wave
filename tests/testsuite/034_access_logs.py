#!/usr/bin/env python
# -*- coding: UTF8 -*-

from lib import env
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

import os
import time
import tempfile
from pprint import pprint

import apache_log_parser
from twisted.internet import defer
from twotp import Atom, to_python, Tuple

APACHE_COMBINED="%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\""
parser = apache_log_parser.make_parser(APACHE_COMBINED)

def _match(f, conds):
    time.sleep(.5)
    try:
        rawline = f.readline()
        line = parser(rawline)
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

        ## configuring acls
        (fd, self.acl_file) = tempfile.mkstemp(prefix='wave-acl-'); os.close(fd)
        print "acl file:", self.acl_file

        with open(self.acl_file, 'w') as f:
            f.write("""
# testsuite acl file
anonymous\tallow\tr\tfoo/baz
anonymous\tallow\tw\tfoo/bat
""")

    @defer.inlineCallbacks
    def _set_acl(self, **values):
        types = {'enabled': Atom, 'file': str}
        dft = {
            'enabled': 'false',
            'file'    : '/tmp/wave.acl'
        }

        dft.update(values)
        ret = yield env.remote('application', 'set_env', Atom('wave'), Atom('acl'),
                          [Tuple([Atom(k), types[k](v)]) for k,v in dft.iteritems()])
        #print to_python(ret)
        yield env.remote('wave_acl', 'switch', dft['file'])

    def setup_test(self):
        # be sure log is flushed
        time.sleep(.5)

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
    @defer.inlineCallbacks
    def test_002(self):
        f = open('../log/wave.access.log', 'r')
        f.seek(0, os.SEEK_END)

        yield self._set_acl(enabled='false')

        # here we start
        c = MqttClient("conformity", connect=4)
        c.subscribe("foo/bar", qos=1)
        c.unsubscribe("foo/bar")

        f.readline() # skip CONNECT
        if not _match(f, {'request_method': 'SUBSCRIBE', 'request_url': 'foo/bar',
                          'status': '200', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)
        if not _match(f, {'request_method': 'UNSUBSCRIBE', 'request_url': 'foo/bar',
                          'status': '200', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        # test w/ acls on
        yield self._set_acl(enabled='true', file=self.acl_file)
        c.subscribe("foo/bar", qos=0)
        if not _match(f, {'request_method': 'SUBSCRIBE', 'request_url': 'foo/bar',
                          'status': '403', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        c.subscribe("foo/bar", qos=1)
        if not _match(f, {'request_method': 'SUBSCRIBE', 'request_url': 'foo/bar',
                          'status': '403', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        c.subscribe("foo/bar", qos=2)
        if not _match(f, {'request_method': 'SUBSCRIBE', 'request_url': 'foo/bar',
                          'status': '403', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        c.subscribe("foo/baz", qos=0)
        if not _match(f, {'request_method': 'SUBSCRIBE', 'request_url': 'foo/baz',
                          'status': '200', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)


        c.unsubscribe("foo/baz")
        c.disconnect()
        defer.returnValue(True)

    @catch
    @desc("PUBLISH")
    @defer.inlineCallbacks
    def test_003(self):
        f = open('../log/wave.access.log', 'r')
        f.seek(0, os.SEEK_END)

        yield self._set_acl(enabled='false')

        # here we start
        c = MqttClient("conformity", connect=4)
        c.publish("foo/bar", "baz", qos=1)

        f.readline() # skip CONNECT
        if not _match(f, {'request_method': 'PUBLISH', 'request_url': 'foo/bar', 'response_bytes_clf': '3',
                          'status': '200', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        # test w/ acls on
        yield self._set_acl(enabled='true', file=self.acl_file)
        c.publish("foo/bar", "", qos=0)
        if not _match(f, {'request_method': 'PUBLISH', 'request_url': 'foo/bar', 'response_bytes_clf': '0',
                          'status': '403', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        c.publish("foo/bar", "", qos=1)
        if not _match(f, {'request_method': 'PUBLISH', 'request_url': 'foo/bar', 'response_bytes_clf': '0',
                          'status': '403', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        c.publish("foo/bar", "", qos=2)
        if not _match(f, {'request_method': 'PUBLISH', 'request_url': 'foo/bar', 'response_bytes_clf': '0',
                          'status': '403', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        c.publish("foo/bat", "", qos=0)
        if not _match(f, {'request_method': 'PUBLISH', 'request_url': 'foo/bat', 'response_bytes_clf': '0',
                          'status': '200', 'request_header_user_agent': c.client_id}):
            defer.returnValue(False)

        c.disconnect()
        defer.returnValue(True)

    @catch
    @desc("PUBLISH ($ prefixed - rejected)")
    def test_004(self):
        f = open('../log/wave.access.log', 'r')
        f.seek(0, os.SEEK_END)

        # here we start
        # NOTE: invalid publish cause disconnection
        for qos in (0,1,2):
            c = MqttClient("conformity", connect=4)
            time.sleep(.5); f.readline() # skip CONNECT
            c.publish("$SYS/bar", "baz", qos=qos)

            if not _match(f, {'request_method': 'PUBLISH', 'request_url': '$SYS/bar', 'response_bytes_clf': '3',
                              'status': '403', 'request_header_user_agent': c.client_id}):
                return False


        return True

    #TODO: test PUBLISH already inflight (409)
