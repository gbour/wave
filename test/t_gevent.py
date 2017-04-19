#!/usr/bin/env python
# -*- coding: utf8 -*-

import time
import gevent

from gevent import monkey
monkey.patch_time()

import logging
from nyamuk import nyamuk
from nyamuk.event import *
import nyamuk.nyamuk_const as NC

monkey.patch_socket()
monkey.patch_select()

def myfunc(a):
    print "{0}: started".format(a)
    time.sleep(5)
    print "{0}: stopped".format(a)


cur = 0
prev = 0
total = 0

def mqttcli(a):
    global cur, prev, total

    c = nyamuk.Nyamuk("gevt:{0}".format(a), None, None, 'localhost', log_level=logging.ERROR)
    ret = c.connect()
    cur +=1; total +=1

    if ret != NC.ERR_SUCCESS:
        return ret

    r = c.packet_write()
    r = c.loop()
    e = c.pop_event()
    #print e.ret_code # must be 0
    time.sleep(90)

    c.disconnect()
    c.packet_write()

    total -=1

def monitor():
    global cur, prev, total

    while True:
        print "clients/s: {0}, connected: {1}".format(cur-prev, total)
        prev = cur
        time.sleep(1)

if __name__ == '__main__':
    m = gevent.spawn(monitor)
    m.start()
    print "monitor:", m

    #jobs = [gevent.spawn(myfunc, i) for i in xrange(10)]
    jobs = [gevent.spawn(mqttcli, i) for i in xrange(5000)]
    print "jobs:", len(jobs)
    gevent.joinall(jobs)
    #[j.start() for j in jobs]
    #[j.join() for j in jobs]
    #gevent.joinall(jobs)
    m.kill()


