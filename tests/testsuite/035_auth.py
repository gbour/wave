# -*- coding: UTF8 -*-

import os
import time
import socket
import tempfile
import subprocess

from lib import env
from lib.env import debug
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *
from nyamuk.mqtt_pkt import MqttPkt

from twisted.internet import defer
from twotp import Atom, to_python, Tuple

@defer.inlineCallbacks
def set_env(values):
    types = {'required': Atom, 'file': str}
    dft = {
        'required': 'false',
        'file'    : '/tmp/wave.passwd'
    }

    dft.update(values)

    ret = yield env.remote('application', 'set_env', Atom('wave'), Atom('auth'),
                      [Tuple([Atom(k), types[k](v)]) for k,v in dft.iteritems()])
    defer.returnValue(to_python(ret))


class Auth(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "Authentication")

    @defer.inlineCallbacks
    def cleanup(self):
        # set back default values (required = false) so following tests are working :)
        yield set_env({})


    @catch
    @desc("anonymous connection: auth optional")
    @defer.inlineCallbacks
    def test_001(self):
        yield set_env({'required': 'false'})

        c = MqttClient("auth", connect=False)
        ret = c.connect(version=4)
        if not isinstance(ret, EventConnack) or\
                ret.ret_code != 0:
            debug(ret)
            defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("anonymous connection: auth required")
    @defer.inlineCallbacks
    def test_002(self):
        yield set_env({'required': 'true'})

        c = MqttClient("auth", connect=False)
        ret = c.connect(version=4)
        if isinstance(ret, EventConnack) and ret.ret_code == 4:
            defer.returnValue(True)

        debug(ret)
        defer.returnValue(False)

    @catch
    @desc("connection w/ credentials: not password file")
    @defer.inlineCallbacks
    def test_003(self):
        tmp = tempfile.mktemp(suffix='wave-testsuite')
        yield set_env({'required': 'true', 'file': tmp})

        c = MqttClient("auth", connect=False)
        ret = c.connect(version=4)
        if isinstance(ret, EventConnack) and ret.ret_code == 4:
            defer.returnValue(True)

        debug(ret)
        defer.returnValue(False)

    @catch
    @desc("w/ credentials: username not found")
    @defer.inlineCallbacks
    def test_004(self):
        tmp = tempfile.mktemp(suffix='wave-testsuite')
        subprocess.Popen("echo \"bar\"|../bin/mkpasswd -c {0} foo".format(tmp),
                         shell=True, stdout=subprocess.PIPE).wait()
        yield set_env({'required': 'true', 'file': tmp})
        yield env.remote('wave_auth', 'switch', tmp)

        c = MqttClient("auth", connect=False, username="fez", password="bar")
        ret = c.connect(version=4)
        # auth rejected
        if isinstance(ret, EventConnack) and ret.ret_code == 4:
            defer.returnValue(True)

        debug(ret)
        defer.returnValue(False)

    @catch
    @desc("w/ credentials: invalid password")
    @defer.inlineCallbacks
    def test_005(self):
        tmp = tempfile.mktemp(suffix='wave-testsuite')
        subprocess.Popen("echo \"bar\"|../bin/mkpasswd -c {0} foo".format(tmp),
                         shell=True, stdout=subprocess.PIPE).wait()
        yield set_env({'required': 'true', 'file': tmp})
        yield env.remote('wave_auth', 'switch', tmp)

        c = MqttClient("auth", connect=False, username="foo", password="baz")
        ret = c.connect(version=4)
        # auth rejected
        if isinstance(ret, EventConnack) and ret.ret_code == 4:
            defer.returnValue(True)

        debug(ret)
        defer.returnValue(False)

    @catch
    @desc("w/ credentials: valid auth")
    @defer.inlineCallbacks
    def test_006(self):
        tmp = tempfile.mktemp(suffix='wave-testsuite')
        subprocess.Popen("echo \"bar\"|../bin/mkpasswd -c {0} foo".format(tmp),
                         shell=True, stdout=subprocess.PIPE).wait()
        yield set_env({'required': 'true', 'file': tmp})
        yield env.remote('wave_auth', 'switch', tmp)

        c = MqttClient("auth", connect=False, username="foo", password="bar")
        ret = c.connect(version=4)
        # auth accepted
        if isinstance(ret, EventConnack) and ret.ret_code == 0:
            defer.returnValue(True)

        debug(ret)
        defer.returnValue(False)

    @catch
    @desc("w/ credentials: updated password")
    @defer.inlineCallbacks
    def test_007(self):
        tmp = tempfile.mktemp(suffix='wave-testsuite')
        subprocess.Popen("echo \"bar\"|../bin/mkpasswd -c {0} foo".format(tmp),
                         shell=True, stdout=subprocess.PIPE).wait()
        yield set_env({'required': 'true', 'file': tmp})
        yield env.remote('wave_auth', 'switch', tmp)

        c = MqttClient("auth", connect=False, username="foo", password="baz")
        ret = c.connect(version=4)
        # auth rejected
        if not isinstance(ret, EventConnack) or ret.ret_code == 0:
            debug(ret)
            defer.returnValue(False)

        # updating password
        subprocess.Popen("echo \"baz\"|../bin/mkpasswd {0} foo".format(tmp),
                         shell=True, stdout=subprocess.PIPE).wait()
        # file is monitored each 2 secs in debug context
        time.sleep(3)

        ret = c.connect(version=4)
        # auth accepted
        if not isinstance(ret, EventConnack) or ret.ret_code != 0:
            debug(ret)
            defer.returnValue(False)

        defer.returnValue(True)

    @catch
    @desc("w/ credentials: deleted password")
    @defer.inlineCallbacks
    def test_008(self):
        tmp = tempfile.mktemp(suffix='wave-testsuite')
        subprocess.Popen("echo \"bar\"|../bin/mkpasswd -c {0} foo".format(tmp),
                         shell=True, stdout=subprocess.PIPE).wait()
        yield set_env({'required': 'true', 'file': tmp})
        yield env.remote('wave_auth', 'switch', tmp)

        c = MqttClient("auth", connect=False, username="foo", password="bar")
        ret = c.connect(version=4)
        # auth rejected
        if not isinstance(ret, EventConnack) or ret.ret_code != 0:
            debug(ret)
            defer.returnValue(False)

        # deleting password
        subprocess.Popen("../bin/mkpasswd -D {0} foo".format(tmp),
                         shell=True, stdout=subprocess.PIPE).wait()
        # file is monitored each 2 secs in debug context
        time.sleep(3)

        ret = c.connect(version=4)
        # auth accepted
        if not isinstance(ret, EventConnack) or ret.ret_code != 4:
            debug(ret)
            defer.returnValue(False)

        defer.returnValue(True)

