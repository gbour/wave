#!/usr/bin/env python
# -*- coding: utf8 -*-

import os
import signal
import subprocess

class BrokerCtrl(object):
    def __init__(self):
        pass

    def kill(self):
        if self._proc is None:
            print "no process"; return

        os.killpg(os.getpgid(self._proc.pid), signal.SIGTERM)
        self._proc = None

    def start(self, env="travis", config='.wave.{env}.config'):
        # _build/env
        config = config.format(env=env)

        cmd = "erl -pa `find -L _build/{env} -name ebin` -s wave_app -config {config} -noinput -name 'wave@127.0.0.1' -setcookie wave".format(env=env, config=config)
        proc = subprocess.Popen(cmd, shell=True,
                                stderr=subprocess.STDOUT, stdout=subprocess.PIPE,
                                close_fds=True,
                                preexec_fn=os.setsid,
                                # runned from tests/ directory
                                cwd="..")

        #while True:
        #    print proc.stdout.readline(),
        #print 'pid=', proc.pid, proc.returncode
        self._proc = proc

    def __del__(self):
        # safety check
        self.kill()

