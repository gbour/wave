# -*- coding: UTF8 -*-

import ssl
import os.path

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *
from lib.env import debug

# TLS > v1 not available on python2.7 except for Debian
# TLSv1 and lower are disabled in OTP >= 18
SSL_VERSION = ssl.PROTOCOL_TLSv1_2 if hasattr(ssl, 'PROTOCOL_TLSv1_2') else ssl.PROTOCOL_TLSv1

# no socket.version() with python2.7 ssl
def version(sock):
    import inspect
    for (name, val) in inspect.getmembers(ssl):
        if not name.startswith('PROTOCOL_'):
            continue

        if sock.ssl_version == val:
            return name.split('_', 1)[-1]

    return None


class SSL(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "SSL")

    @catch
    @desc("CONNECT")
    def test_001(self):
        c = MqttClient("reg", ssl=True, ssl_opts={'ssl_version': SSL_VERSION})
        evt = c.connect()
        debug("Using SSL: version={0}, cipher={1}".format(version(c._c.sock), c._c.sock.cipher()))

        if not isinstance(evt, EventConnack):
            return False

        c.disconnect()
        return True

    @catch
    @desc("CONNECTION ERROR - FAILING certificate checking")
    def test_002(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED
        })

        evt = c.connect()
        if not isinstance(evt, EventConnack):
            return True

        c.disconnect()
        return False

    @catch
    @desc("CONNECTION OK - SUCCESSFULL certificate checking")
    def test_003(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED,
            'ca_certs': os.path.join(os.path.dirname(__file__), "../../", "etc/wave_cert.pem")
        })

        evt = c.connect()
        if not isinstance(evt, EventConnack):
            return False

        c.disconnect()
        return True

    @catch
    @desc("CONNECTION ERROR - invalid cipher")
    def test_004(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED,
            'ca_certs': os.path.join(os.path.dirname(__file__), "../../", "etc/wave_cert.pem"),
            'ciphers': 'NOT_A_VALID_CIPHER'
        })

        evt = c.connect()
        if not isinstance(evt, EventConnack):
            return True

        c.disconnect()
        return False

    @catch
    @desc("CONNECTION OK - forcing cipher")
    def test_005(self):
        c = MqttClient("reg", ssl=True, ssl_opts={
            'ssl_version': SSL_VERSION,
            'cert_reqs': ssl.CERT_REQUIRED,
            'ca_certs': os.path.join(os.path.dirname(__file__), "../../", "etc/wave_cert.pem"),
            #'ciphers': 'HIGH:!DHE:!ECDHE'
            'ciphers': 'AES256-SHA'
        })

        evt = c.connect()
        debug("Using SSL: version={0}, cipher={1}".format(version(c._c.sock), c._c.sock.cipher()))
        if not isinstance(evt, EventConnack):
            return False

        c.disconnect()
        return True

