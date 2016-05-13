#!/usr/bin/env python
# -*- coding: utf8 -*-

import random
from twisted.internet import defer

db = None
twotp = None

def gen_msg(msglen):
    return ''.join([chr(48+random.randint(0,42)) for x in xrange(msglen)])

@defer.inlineCallbacks
def remote(mod, fun, *args):
    """ """
    ret = yield twotp.callRemote('wave@127.0.0.1', mod, fun, *args)
    defer.returnValue(ret)

    
