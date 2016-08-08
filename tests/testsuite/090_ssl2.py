# -*- coding: UTF8 -*-

"""
    NOTE: as this test module is stopping/starting broker server, it is important
          to be executed at the end so it does not disturb other tests
"""
import os, re
import ssl
import time
import signal
import os.path
import tempfile
import subprocess

from TestSuite import TestSuite, desc, catch
from mqttcli import MqttClient
from nyamuk.event import *

import twotp
from twisted.internet import reactor, defer

import erl_terms as eterms

from lib import env as ctx
from lib.env import debug
from lib.broker_ctrl import BrokerCtrl


class SSL2(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "SSL2")

    def setup_suite(self):
        self.stop_external_wave()

    def stop_external_wave(self):
        p = subprocess.Popen("pidof beam.smp", shell=True, stdout=subprocess.PIPE)
        (outdata, errdata) = p.communicate()
        p.wait()

        pids = outdata.strip().split(' ')
        for pid in pids:
            with open("/proc/{0}/cmdline".format(pid), 'r') as f:
                cmdline = f.read()

            if 'wave_app' in cmdline:
                debug('killing wave server (pid {0})'.format(pid))
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except Exception,e:
                    debug(e)

    def start_wave(self, config):
        env = os.environ.get('env', 'travis')

        broker = BrokerCtrl()
        broker.start(config=config, env=env)
        time.sleep(5)

        # re-established twotp connection
        ctx.twotp = twotp.Process('wave_tests@127.0.0.1', 'wave')

        return broker

    def update_config(self, certfile, keyfile):
        env = os.environ.get('env', 'travis')

        [conf] = eterms.from_file('../.wave.{0}.config'.format(env))
        conf.wave.ssl.certfile   = certfile
        conf.wave.ssl.cacertfile = certfile
        conf.wave.ssl.keyfile    = keyfile

        (fh, outfile) = tempfile.mkstemp(prefix='wave-', suffix='.config')
        debug("config saved to {0}".format(outfile))
        eterms.to_file([conf], outfile)

        return outfile

    def check_certificate(self):
        # other solution: timeout secs command
        #                 timeout 10 openssl s_client ...
        p = subprocess.Popen("echo \"Q\"|/usr/bin/openssl s_client -connect localhost:8883", shell=True,
                stderr=subprocess.PIPE, stdout=subprocess.PIPE
        )
        (outdata, errdata) = p.communicate()
        #print outdata, ';', errdata
        p.wait()
        #m = re.search("---\nCertificate chain\n(.*?)\n---", outdata, re.S|re.M)
        #print m.group(1)
        m = re.search("Verify return code: ([0-9]+) ([^\n]+)", outdata, re.S|re.M)
        if not m: return (-1, None)

        return m.groups()



    @catch
    @desc("auto-signed certificate")
    def test_001(self):
        # generates new config
        conf = self.update_config('./etc/wave_cert.pem', './etc/wave_key.pem')
        brok = self.start_wave(conf)

        ret = True
        (errno, msg) = self.check_certificate()
        if int(errno) != 18:
            debug("{0}: {1}".format(errno, msg))
            ret = False

        time.sleep(2) # to be sure file buffers are flushed
        brok.kill()

        return ret

    @catch
    @desc("chained certificate")
    def test_002(self):
        # generates new config
        conf = self.update_config('./etc/wave_chained_cert.pem', './etc/wave_chained_key.pem')
        brok = self.start_wave(conf)

        ret = True
        (errno, msg) = self.check_certificate()
        if int(errno) != 19:
            debug("{0}: {1}".format(errno, msg))
            ret = False

        time.sleep(2) # to be sure file buffers are flushed
        brok.kill()

        return ret


