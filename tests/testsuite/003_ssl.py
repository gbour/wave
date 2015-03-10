#!/usr/bin/env python
# -*- coding: UTF8 -*-

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

import ssl
import os
import os.path

# TLS > v1 not available on python2.7 except for Debian
SSL_VERSION = ssl.PROTOCOL_TLSv1_2 if hasattr(ssl, 'PROTOCOL_TLSv1_2') else ssl.PROTOCOL_TLSv1

class Basic(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "SSL")

    @catch
    @desc("CONNECT")
    def test_01(self):
        c = MqttClient("reg", ssl=True, ssl_opts={'ssl_version': SSL_VERSION})
        evt = c.do("connect")
        print "Using SSL version:", c._c.sock.version()

        if not isinstance(evt, EventConnack):
            return False

        return True

    @catch
    @desc("CONNECTION ERROR - FAILING certificate checking")
    def test_02(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED
        })
        evt = c.do("connect")

        if not isinstance(evt, EventConnack):
            return True

        return False

    @catch
    @desc("CONNECTION OK - SUCCESSFULL certificate checking")
    def test_03(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED,
            'ca_certs': os.path.join(os.path.dirname(__file__), "../../", "etc/wave_cert.pem")
        })
        evt = c.do("connect")

        if not isinstance(evt, EventConnack):
            return False

        return True

    @catch
    @desc("CONNECTION ERROR - invalid cipher")
    def test_04(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED,
            'ca_certs': os.path.join(os.path.dirname(__file__), "../../", "etc/wave_cert.pem"),
            'ciphers': 'DES_CBC_SHA'
        })
        try:
            evt = c.do("connect")
        except ssl.SSLError, e:
            print "SSLError=", e
            return True

        return False

    @catch
    @desc("CONNECTION OK - valid cipher")
    def test_05(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED,
            'ca_certs': os.path.join(os.path.dirname(__file__), "../../", "etc/wave_cert.pem"),
            'ciphers': 'DHE-RSA-AES256-SHA256'
        })
        try:
            evt = c.do("connect")
        except ssl.SSLError, e:
            print "SSLError=", e
            return False

        if not isinstance(evt, EventConnack):
            return False

        return True
