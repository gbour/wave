#!/usr/bin/env python
# -*- coding: utf8 -*-

import random

db = None
twotp = None

def gen_msg(msglen):
    return ''.join([chr(48+random.randint(0,42)) for x in xrange(msglen)])
