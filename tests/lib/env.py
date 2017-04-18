#!/usr/bin/env python
# -*- coding: utf8 -*-

import os
import random
from inspect import currentframe, getframeinfo

from twisted.internet import defer

db = None
twotp = None

def gen_msg(msglen=16):
    return ''.join([chr(48+random.randint(0,42)) for x in xrange(msglen)])

@defer.inlineCallbacks
def remote(mod, fun, *args):
    """ """
    ret = yield twotp.callRemote('wave@127.0.0.1', mod, fun, *args)
    defer.returnValue(ret)


def _nodebug(msg):
    pass

def _debug(msg, depth=0):
    frame = currentframe().f_back
    for i in range(depth): frame = frame.f_back

    nfo = getframeinfo(frame)
    print " D({0}:{1}): {2}".format(nfo.function, nfo.lineno, msg)

DEBUG = os.environ.get('DEBUG', '0')
if DEBUG == '0':
    debug = _nodebug
else:
    debug = _debug

