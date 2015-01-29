#!/usr/bin/env python
# -*- coding: UTF8 -*-

import time
import random
from nyamuk import nyamuk
from nyamuk.event import *

class MqttClient(object):
    def __init__(self, prefix):
        self._c = nyamuk.Nyamuk("test:{0}:{1}".format(prefix, random.randint(0,9999)), None, None, 'localhost')

    def disconnect(self):
        self._c.disconnect(); self._c.packet_write()

    def do(self, action, *args):
        getattr(self._c, action)(*args)

        r = self._c.packet_write()
        r = self._c.loop()
        return self._c.pop_event()

    def __getattr__(self, name):
        def _(*args):
            return self.do(name, *args)
            
        return _

